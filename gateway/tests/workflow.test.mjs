import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createRouter } from '../src/router.mjs';
import { SseHub } from '../src/sse.mjs';
import {
  buildCodexDeliveryPrompt,
  buildExecutorPrompt,
  buildOrchestratorPrompt,
  DeliveryAssist,
  MissionStore,
  MissionOrchestrator,
  publicProfile,
  scopedAgmsgName,
} from '../src/workflow.mjs';

const mission = {
  id: 'mission-123',
  title: 'Ship terminal bridge',
  goal: 'Implement and test a secure bridge.',
  team: 'herddeck',
  projectPath: '/Users/test/Developer/HerdDeck',
  maxRounds: 8,
};

const orchestrator = {
  id: 'claude', displayName: 'Fable Orchestrator', runtime: 'claude-code', role: 'orchestrator',
  agmsgName: 'orchestrator', modelLabel: 'Claude Fable 5', effortLabel: 'High',
  argv: ['claude', '--model', 'fable', '--effort', 'high'], env: { SECRET: 'hidden' }, accent: 'violet',
};
const executor = {
  id: 'codex', displayName: 'Sol Builder', runtime: 'codex', role: 'executor',
  agmsgName: 'builder', modelLabel: 'GPT-5.6 Sol', effortLabel: 'High',
  argv: ['codex', '--model', 'gpt-5.6-sol'], env: {}, accent: 'cyan',
};

test('orchestrator prompt encodes bounded agmsg coordination protocol', () => {
  const prompt = buildOrchestratorPrompt({
    mission,
    profile: orchestrator,
    orchestratorAgmsgName: 'orchestrator-abc123',
    executors: [{ profile: executor, agmsgName: 'builder-abc123-1' }],
    controlRecipient: 'herddeck-control',
  });
  assert.match(prompt, /^\/agmsg actas orchestrator-abc123/);
  assert.match(prompt, /builder-abc123-1: GPT-5.6 Sol/);
  assert.match(prompt, /MAX COORDINATION ROUNDS: 8/);
  assert.match(prompt, /ACK, BLOCKED <reason>, REVIEW <artifact>, or DONE/);
  assert.match(prompt, /MISSION_DONE mission-123/);
  assert.match(prompt, /NEEDS_INPUT mission-123/);
  assert.match(prompt, /HERDDECK CONTROL RECIPIENT: herddeck-control/);
});

test('executor prompt uses Codex skill syntax and safe autonomy constraints', () => {
  const prompt = buildExecutorPrompt({
    mission,
    profile: executor,
    ordinal: 1,
    agmsgName: 'builder-abc123-1',
    orchestratorAgmsgName: 'orchestrator-abc123',
  });
  assert.match(prompt, /^\$agmsg actas builder-abc123-1/);
  assert.match(prompt, /ORCHESTRATOR: orchestrator-abc123/);
  assert.match(prompt, /workspace-write sandbox/);
  assert.match(prompt, /Never silently broaden scope/);
});

test('mission-scoped AGMSG identities are reusable and stay within the identifier contract', () => {
  assert.equal(scopedAgmsgName('orchestrator', 'abc12345'), 'orchestrator-abc12345');
  assert.equal(scopedAgmsgName('builder', 'abc12345', 2), 'builder-abc12345-2');
  assert.match(scopedAgmsgName('Builder / Review', 'ab-cd', 1), /^[A-Za-z0-9._-]{1,80}$/);
  assert.ok(scopedAgmsgName('x'.repeat(100), 'abc12345', 4).length <= 80);
});

test('public profile does not expose environment values', () => {
  const output = publicProfile(orchestrator);
  assert.equal(output.env, undefined);
  assert.equal(JSON.stringify(output).includes('hidden'), false);
});

test('Codex delivery prompt preserves targeted AGMSG envelope and reply protocol', () => {
  const prompt = buildCodexDeliveryPrompt({
    team: 'herddeck',
    agent: 'builder-abc-1',
    messages: [{ id: 'msg-1', from: 'orchestrator-abc', to: 'builder-abc-1', body: 'Implement src/bridge.ts' }],
  });
  assert.match(prompt, /AGMSG DELIVERY team=herddeck recipient=builder-abc-1/);
  assert.match(prompt, /id=msg-1 from=orchestrator-abc to=builder-abc-1/);
  assert.match(prompt, /Implement src\/bridge.ts/);
  assert.match(prompt, /Reply through \$agmsg/);
});

test('Codex delivery prompt sanitizes envelope metadata without rewriting message bodies', () => {
  const prompt = buildCodexDeliveryPrompt({
    team: 'team\nspoof',
    agent: 'builder]spoof',
    messages: [{
      id: 'id\n2',
      from: 'orch]x',
      to: 'builder\ny',
      body: 'Body remains [verbatim]\nwith its own line.',
    }],
  });
  assert.match(prompt, /^\[AGMSG DELIVERY team=team_spoof recipient=builder_spoof\]/);
  assert.match(prompt, /\[message id=id_2 from=orch_x to=builder_y\]/);
  assert.match(prompt, /Body remains \[verbatim\]\nwith its own line\./);
});

test('MissionStore serializes concurrent writes and reloads durable mission state', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'herddeck-missions-'));
  const storePath = path.join(directory, 'missions.json');
  try {
    const store = new MissionStore(storePath);
    await Promise.all(Array.from({ length: 24 }, (_, index) => store.create({
      id: `mission-${index}`,
      createdAt: new Date(2026, 6, 12, 0, 0, index).toISOString(),
      status: 'starting',
    })));
    await Promise.all(Array.from({ length: 24 }, (_, index) =>
      store.update(`mission-${index}`, { status: 'running', ordinal: index }),
    ));

    const records = await store.list();
    assert.equal(records.length, 24);
    assert.equal(records.every((record) => record.status === 'running'), true);

    const reloaded = new MissionStore(storePath);
    const durable = await reloaded.list();
    assert.equal(durable.length, 24);
    assert.equal(durable.find((record) => record.id === 'mission-17')?.ordinal, 17);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('MissionOrchestrator.start persists and publishes a running mission', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'herddeck-mission-start-'));
  try {
    let record;
    const joins = [];
    const published = [];
    const startedAgents = [];
    const service = new MissionOrchestrator({
      herdr: {
        async rpc(method) {
          if (method === 'workspace.create') {
            return {
              type: 'workspace_created',
              workspace: { workspace_id: 'workspace-1' },
              tab: { tab_id: 'tab-1' },
              root_pane: { pane_id: 'root-pane' },
            };
          }
          assert.equal(method, 'pane.close');
          return { type: 'ok' };
        },
        async startAgent(params) {
          startedAgents.push(params);
          return {
            type: 'agent_started',
            agent: {
              pane_id: `pane-${startedAgents.length}`,
              terminal_id: `terminal-${startedAgents.length}`,
            },
          };
        },
      },
      agmsg: { async join(params) { joins.push(params); } },
      monitor: { async refresh() {} },
      config: {
        profiles: [orchestrator, executor],
        projectRoots: [directory],
        deliveryAssist: { enabled: true },
      },
      store: {
        async create(value) { record = value; return value; },
        async update(id, patch) {
          assert.equal(id, record.id);
          record = { ...record, ...patch };
          return record;
        },
      },
      audit: { async success() {}, async failure() {} },
      events: { publish(name, value) { published.push([name, value.status]); } },
    });
    let deliveryStarted;
    service.delivery.start = async (value) => { deliveryStarted = value.id; };

    const result = await service.start({
      title: 'Start mission',
      goal: 'Verify the mission startup path.',
      projectPath: directory,
      team: 'herddeck',
      orchestratorProfileId: orchestrator.id,
      executorProfileIds: [executor.id],
    });

    assert.equal(result.status, 'running');
    assert.equal(result.agents.length, 2);
    assert.equal(joins.length, 3);
    assert.equal(startedAgents.length, 2);
    assert.equal(deliveryStarted, result.id);
    assert.deepEqual(published.map((entry) => entry[1]), ['starting', 'running']);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('delivery assist injects targeted Codex messages with delayed Enter for an opaque id', async () => {
  const calls = [];
  const assist = new DeliveryAssist({
    herdr: {
      async sendText(paneID, text) { calls.push(['text', paneID, text]); },
      async sendKeys(paneID, keys) { calls.push(['keys', paneID, keys]); },
    },
    agmsg: {
      async messages() {
        return [
          { id: 'old-message', from: 'orchestrator', to: 'builder', body: 'old' },
          { id: 'msg_01JZZZ', from: 'orchestrator', to: 'builder', body: 'build it' },
        ];
      },
    },
    monitor: {
      latest: {
        agents: [{ name: 'hd-abc-exec-1', pane_id: 'pane-1', agent_status: 'working' }],
      },
    },
    config: {
      deliveryAssist: {
        enabled: true,
        pollMs: 1000,
        onlyWhenAgentNotWorking: false,
        inputDelayMs: 0,
      },
    },
    audit: { async success() {}, async failure() {} },
  });

  const state = {
    mission: {
      id: 'mission-1',
      spec: { team: 'herddeck' },
      agents: [{
        agmsgName: 'builder',
        herdrName: 'hd-abc-exec-1',
        paneId: 'pane-1',
        runtime: 'codex',
      }],
    },
    seenMessageIds: new Map([['builder', new Set(['old-message'])]]),
    pending: new Set(),
  };

  await assist.poll(state);

  assert.equal(calls.length, 2);
  assert.equal(calls[0][0], 'text');
  assert.equal(calls[0][1], 'pane-1');
  assert.match(calls[0][2], /AGMSG DELIVERY[\s\S]*msg_01JZZZ[\s\S]*build it/);
  assert.deepEqual(calls[1], ['keys', 'pane-1', ['enter']]);
  assert.equal(state.pending.has('builder'), false);
  assert.equal(state.seenMessageIds.get('builder').has('msg_01JZZZ'), true);
});

test('mission reconciliation completes only after the orchestrator is done and executors are settled', async () => {
  let updatedPatch;
  let published;
  let stoppedMission;
  const record = {
    id: 'mission-1',
    status: 'running',
    agents: [
      { role: 'orchestrator', paneId: 'pane-orch' },
      { role: 'executor', paneId: 'pane-build' },
    ],
  };
  const orchestratorService = new MissionOrchestrator({
    herdr: {},
    agmsg: {},
    monitor: {},
    config: { deliveryAssist: { enabled: true } },
    store: {
      async list() { return [record]; },
      async update(id, patch) {
        assert.equal(id, record.id);
        updatedPatch = patch;
        return { ...record, ...patch };
      },
    },
    audit: { async success() {}, async failure() {} },
    events: { publish(_name, value) { published = value; } },
  });
  orchestratorService.delivery.stop = (id) => { stoppedMission = id; };

  await orchestratorService.reconcileSnapshot({
    agents: [
      { pane_id: 'pane-orch', agent_status: 'done' },
      { pane_id: 'pane-build', agent_status: 'idle' },
    ],
  });

  assert.deepEqual(updatedPatch, { status: 'completed', error: null });
  assert.equal(stoppedMission, 'mission-1');
  assert.equal(published.status, 'completed');
});

test('resumeRunning fails stale starting missions and publishes the transition', async () => {
  const records = [
    { id: 'mission-starting', status: 'starting' },
    { id: 'mission-running', status: 'running' },
  ];
  const updates = [];
  const published = [];
  const service = new MissionOrchestrator({
    herdr: {},
    agmsg: {},
    monitor: {},
    config: { deliveryAssist: { enabled: true } },
    store: {
      async list() { return records; },
      async update(id, patch) {
        updates.push([id, patch]);
        return { ...records.find((record) => record.id === id), ...patch };
      },
    },
    audit: {},
    events: { publish(name, value) { published.push([name, value]); } },
  });
  const resumed = [];
  service.delivery.start = async (record) => { resumed.push(record.id); };

  await service.resumeRunning();

  assert.deepEqual(updates, [[
    'mission-starting',
    { status: 'failed', error: 'gateway restarted during start' },
  ]]);
  assert.deepEqual(published, [[
    'mission',
    { id: 'mission-starting', status: 'failed', error: 'gateway restarted during start' },
  ]]);
  assert.deepEqual(resumed, ['mission-running']);
});

test('mission reconciliation accepts an explicit durable AGMSG completion signal', async () => {
  let completed = false;
  const record = {
    id: 'mission-123',
    status: 'running',
    controlAgmsgName: 'herddeck-control',
    spec: { team: 'herddeck' },
    agents: [
      { role: 'orchestrator', agmsgName: 'orchestrator', paneId: 'pane-orch' },
      { role: 'executor', agmsgName: 'builder', paneId: 'pane-build' },
    ],
  };
  const service = new MissionOrchestrator({
    herdr: {},
    agmsg: {
      async messages() {
        return [{
          id: 'msg-done',
          from: 'orchestrator',
          to: 'herddeck-control',
          body: 'MISSION_DONE mission-123 | tests green; artifact ready',
        }];
      },
    },
    monitor: {},
    config: { deliveryAssist: { enabled: true } },
    store: {
      async list() { return [record]; },
      async update(_id, patch) {
        completed = patch.status === 'completed';
        return { ...record, ...patch };
      },
    },
    audit: { async success() {}, async failure() {} },
    events: { publish() {} },
  });
  service.delivery.stop = () => {};

  await service.reconcileSnapshot({
    agents: [
      { pane_id: 'pane-orch', agent_status: 'working' },
      { pane_id: 'pane-build', agent_status: 'working' },
    ],
  });

  assert.equal(completed, true);
});

test('mission reconciliation falls back to Herdr when durable AGMSG reads fail', async () => {
  const completed = [];
  const warnings = [];
  const records = [
    {
      id: 'mission-1',
      status: 'running',
      controlAgmsgName: 'herddeck-control',
      spec: { team: 'herddeck' },
      agents: [
        { role: 'orchestrator', agmsgName: 'orchestrator', paneId: 'pane-orch-1' },
        { role: 'executor', agmsgName: 'builder', paneId: 'pane-build-1' },
      ],
    },
    {
      id: 'mission-2',
      status: 'running',
      agents: [
        { role: 'orchestrator', paneId: 'pane-orch-2' },
        { role: 'executor', paneId: 'pane-build-2' },
      ],
    },
  ];
  const service = new MissionOrchestrator({
    herdr: {},
    agmsg: { async messages() { throw new Error('agmsg unavailable'); } },
    monitor: {},
    config: { deliveryAssist: { enabled: true } },
    store: {
      async list() { return records; },
      async update(id, patch) {
        completed.push(id);
        const record = records.find((candidate) => candidate.id === id);
        return { ...record, ...patch };
      },
    },
    audit: { async success() {}, async failure() { throw new Error('audit unavailable'); } },
    events: { publish(name, value) { if (name === 'gateway-warning') warnings.push(value); } },
  });
  service.delivery.stop = () => {};

  await service.reconcileSnapshot({
    agents: [
      { pane_id: 'pane-orch-1', agent_status: 'done' },
      { pane_id: 'pane-build-1', agent_status: 'idle' },
      { pane_id: 'pane-orch-2', agent_status: 'done' },
      { pane_id: 'pane-build-2', agent_status: 'idle' },
    ],
  });

  assert.deepEqual(completed, ['mission-1', 'mission-2']);
  assert.equal(warnings.length, 1);
  assert.equal(warnings[0].missionId, 'mission-1');
});

test('delivery assist guards audit failures and continues polling with backoff', async () => {
  let polls = 0;
  let audits = 0;
  const assist = new DeliveryAssist({
    herdr: {},
    agmsg: {},
    monitor: {},
    config: {
      deliveryAssist: {
        enabled: true,
        pollMs: 5,
        onlyWhenAgentNotWorking: false,
        inputDelayMs: 0,
      },
    },
    audit: {
      async failure() {
        audits += 1;
        throw new Error('audit unavailable');
      },
    },
  });
  assist.poll = async () => {
    polls += 1;
    throw new Error('poll unavailable');
  };
  const activeMission = {
    id: 'mission-retry',
    spec: { team: 'herddeck', deliveryAssist: true },
    agents: [],
  };

  await assist.start(activeMission);
  await new Promise((resolve) => setTimeout(resolve, 55));
  assist.stop(activeMission.id);

  assert.ok(polls >= 3);
  assert.ok(audits >= 1);
  assert.ok(audits < polls);
});

test('SseHub removes a client when its response emits an error', () => {
  const hub = new SseHub();
  const response = new EventEmitter();
  response.writeHead = () => {};
  response.write = () => true;
  response.end = () => {};

  hub.add(response);
  assert.equal(hub.clients.has(response), true);
  response.emit('error', new Error('client disconnected'));
  assert.equal(hub.clients.has(response), false);
  hub.close();
});

test('router replaces an invalid request id before setting the response header', async () => {
  const headers = new Map();
  let status;
  const response = {
    setHeader(name, value) {
      if (/[\r\n]/.test(value)) throw new TypeError('invalid header');
      headers.set(name, value);
    },
    writeHead(value) { status = value; },
    end() {},
  };
  const route = createRouter({
    config: { allowedOrigins: [] },
    configPath: '/tmp/config.json',
    token: 'token',
    tokenFingerprint: 'fingerprint',
    limiter: { allow() { return true; } },
    herdr: {},
    monitor: {},
    agmsg: {},
    missions: {},
    orchestrator: {},
    mosh: {},
    events: {},
    audit: {},
  });

  await route({
    method: 'GET',
    url: '/healthz',
    headers: { host: 'localhost', 'x-request-id': 'bad\nid' },
    socket: {},
  }, response);

  assert.equal(status, 200);
  assert.match(headers.get('X-Request-ID'), /^[A-Za-z0-9._-]{1,128}$/);
  assert.notEqual(headers.get('X-Request-ID'), 'bad\nid');
});
