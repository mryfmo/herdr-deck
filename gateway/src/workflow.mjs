import { randomUUID } from 'node:crypto';
import { realpath, stat } from 'node:fs/promises';
import { basename } from 'node:path';
import {
  assertIdentifier,
  isPathAllowed,
  readJson,
  requestError,
  shortId,
  sleep,
  slug,
  writeJsonAtomic,
} from './utils.mjs';

export function publicProfile(profile) {
  return {
    id: profile.id,
    displayName: profile.displayName,
    runtime: profile.runtime,
    role: profile.role,
    agmsgName: profile.agmsgName,
    modelLabel: profile.modelLabel,
    effortLabel: profile.effortLabel,
    accent: profile.accent ?? 'neutral',
    commandPreview: profile.argv.join(' '),
  };
}

export function scopedAgmsgName(baseName, missionSuffix, ordinal = undefined) {
  const base = slug(baseName, 'agent').slice(0, 48);
  const suffix = String(missionSuffix).replace(/[^A-Za-z0-9]/g, '').slice(0, 12) || 'mission';
  const tail = ordinal === undefined ? suffix : `${suffix}-${ordinal}`;
  return `${base}-${tail}`.slice(0, 80);
}

function agmsgCommand(runtime) {
  return runtime === 'codex' ? '$agmsg' : '/agmsg';
}

export class MissionStore {
  constructor(path) {
    this.path = path;
    this.records = [];
    this.loaded = false;
    this.loadPromise = null;
    this.writeQueue = Promise.resolve();
    this.audit = null;
  }

  async load() {
    if (this.loaded) return;
    if (!this.loadPromise) {
      this.loadPromise = (async () => {
        const document = await readJson(
          this.path,
          { version: 1, missions: [] },
          async (error, corruptPath) => {
            if (!this.audit) return;
            await this.audit.failure('mission_store.corrupt', error, {
              path: this.path,
              corruptPath,
            }).catch(() => undefined);
          },
        );
        this.records = Array.isArray(document.missions) ? document.missions : [];
        this.loaded = true;
      })();
    }
    await this.loadPromise;
  }

  async persist() {
    await writeJsonAtomic(this.path, { version: 1, missions: this.records });
  }

  async list() {
    await this.writeQueue;
    await this.load();
    return [...this.records].sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  }

  async get(id) {
    await this.writeQueue;
    await this.load();
    return this.records.find((record) => record.id === id) ?? null;
  }

  async create(record) {
    return this.#write(async () => {
      this.records.unshift(record);
      return record;
    });
  }

  async update(id, patch) {
    return this.#write(async () => {
      const index = this.records.findIndex((record) => record.id === id);
      if (index < 0) return null;
      this.records[index] = { ...this.records[index], ...patch, updatedAt: new Date().toISOString() };
      return this.records[index];
    });
  }

  #write(operation) {
    const result = this.writeQueue.then(async () => {
      await this.load();
      const value = await operation();
      await this.persist();
      return value;
    });
    this.writeQueue = result.catch(() => undefined);
    return result;
  }
}

function normalizeMissionSpec(spec) {
  if (!spec || typeof spec !== 'object') throw requestError('Mission body is required');
  const title = String(spec.title ?? '').trim();
  const goal = String(spec.goal ?? '').trim();
  const projectPath = String(spec.projectPath ?? '').trim();
  const team = String(spec.team ?? '').trim();
  if (title.length < 2 || title.length > 120) throw requestError('title must be 2-120 characters');
  if (goal.length < 10 || goal.length > 24_000) throw requestError('goal must be 10-24000 characters');
  if (!projectPath) throw requestError('projectPath is required');
  assertIdentifier(team, 'team');
  const maxRounds = Math.min(Math.max(Number(spec.maxRounds) || 8, 1), 30);
  const orchestratorProfileId = String(spec.orchestratorProfileId ?? '');
  const executorProfileIds = Array.isArray(spec.executorProfileIds)
    ? spec.executorProfileIds.map(String).filter(Boolean)
    : [];
  if (!orchestratorProfileId) throw requestError('orchestratorProfileId is required');
  if (executorProfileIds.length === 0) throw requestError('At least one executorProfileId is required');
  if (executorProfileIds.length > 4) throw requestError('A mission may start at most four executors');
  if (new Set(executorProfileIds).size !== executorProfileIds.length) {
    throw requestError('executorProfileIds must not contain duplicates');
  }
  return {
    title,
    goal,
    projectPath,
    team,
    maxRounds,
    orchestratorProfileId,
    executorProfileIds,
    deliveryAssist: spec.deliveryAssist !== false,
  };
}

export function buildOrchestratorPrompt({
  mission,
  profile,
  executors,
  controlRecipient,
  orchestratorAgmsgName = profile.agmsgName,
}) {
  const executorLines = executors
    .map((entry) => {
      const executorProfile = entry.profile ?? entry;
      const agmsgName = entry.agmsgName ?? executorProfile.agmsgName;
      return `- ${agmsgName}: ${executorProfile.modelLabel} (${executorProfile.effortLabel}), implementation/review executor`;
    })
    .join('\n');
  return `${agmsgCommand(profile.runtime)} actas ${orchestratorAgmsgName}\n\n` +
    `You are the orchestration lead for a HerdDeck mission.\n` +
    `MISSION: ${mission.title}\n` +
    `TEAM: ${mission.team}\n` +
    `PROJECT: ${mission.projectPath}\n` +
    `MAX COORDINATION ROUNDS: ${mission.maxRounds}\n\n` +
    `HERDDECK CONTROL RECIPIENT: ${controlRecipient}\n` +
    `HERDDECK MISSION ID: ${mission.id}\n\n` +
    `GOAL:\n${mission.goal}\n\n` +
    `PEERS:\n${executorLines}\n\n` +
    `OPERATING PROTOCOL:\n` +
    `1. Inspect the repository, form a concrete plan, then delegate bounded task packets through agmsg.\n` +
    `2. Every packet must include acceptance criteria, relevant paths, constraints, and the expected artifact or commit reference.\n` +
    `3. Ask executors to reply with ACK, BLOCKED <reason>, REVIEW <artifact>, or DONE <summary + paths/commit>.\n` +
    `4. Keep messages concise; store large output in files and send paths or commit SHAs through agmsg.\n` +
    `5. Validate executor work, run tests, request revisions when needed, and integrate the final result.\n` +
    `6. Avoid duplicate ownership. Do not dispatch the same writable scope to two executors simultaneously.\n` +
    `7. Stop after ${mission.maxRounds} coordination rounds or when the goal is satisfied.\n` +
    `8. After final validation, use agmsg to send ${controlRecipient} a concise message beginning exactly ` +
      `MISSION_DONE ${mission.id}. Do not send this marker before the integrated result and tests are ready.\n` +
    `9. When blocked on human input, send ${controlRecipient} a message beginning exactly ` +
      `NEEDS_INPUT ${mission.id}, then continue monitoring the team.\n` +
    `10. Stay within the project and preserve user data. Do not weaken sandbox or approval settings.\n\n` +
    `Begin by checking the team roster and sending the first task through agmsg.`;
}

export function buildExecutorPrompt({
  mission,
  profile,
  ordinal,
  agmsgName = profile.agmsgName,
  orchestratorAgmsgName = 'orchestrator',
}) {
  const command = agmsgCommand(profile.runtime);
  return `${command} actas ${agmsgName}\n\n` +
    `You are autonomous executor ${ordinal} for a HerdDeck mission.\n` +
    `MISSION: ${mission.title}\n` +
    `TEAM: ${mission.team}\n` +
    `PROJECT: ${mission.projectPath}\n` +
    `MODEL PROFILE: ${profile.modelLabel} / ${profile.effortLabel}\n\n` +
    `ORCHESTRATOR: ${orchestratorAgmsgName}\n\n` +
    `GOAL CONTEXT:\n${mission.goal}\n\n` +
    `OPERATING PROTOCOL:\n` +
    `1. Check agmsg for a task from orchestrator; ACK it before substantial work.\n` +
    `2. Work autonomously inside the repository and its configured workspace-write sandbox.\n` +
    `3. Run focused tests and inspect your diff before reporting completion.\n` +
    `4. Put large reports or generated artifacts in the repository; send concise summaries and file paths or commit SHAs through agmsg.\n` +
    `5. Reply BLOCKED with the smallest actionable question when human or orchestrator input is required.\n` +
    `6. Never silently broaden scope, bypass approvals, or modify credentials.\n` +
    `7. Finish each assignment with DONE <summary; tests; paths/commit>, then check agmsg once for follow-up.\n\n` +
    `Wait for or retrieve the first task from orchestrator now.`;
}

export function buildCodexDeliveryPrompt({ team, agent, messages }) {
  const field = (value) => String(value ?? '')
    .replace(/[\r\n\[\]]/g, '_')
    .slice(0, 160);
  const sections = messages.map((message) =>
    `[message id=${field(message.id)} from=${field(message.from)} to=${field(message.to)}]\n${String(message.body ?? '')}`,
  );
  return `[AGMSG DELIVERY team=${field(team)} recipient=${field(agent)}]\n` +
    `${sections.join('\n\n')}\n` +
    `[END AGMSG DELIVERY]\n` +
    `Process these messages in order. Reply through ${agmsgCommand('codex')} using your active actas identity; ` +
    `send concise status and artifact paths or commit SHAs to the named sender.`;
}

function codexDeliveryBatch(inbound, maxMessages = 8, maxBytes = 60_000) {
  const batch = [];
  let bytes = 0;
  for (const message of inbound) {
    const size = Buffer.byteLength(String(message.body ?? ''), 'utf8') + 256;
    if (batch.length > 0 && (batch.length >= maxMessages || bytes + size > maxBytes)) break;
    batch.push(message);
    bytes += size;
  }
  return batch;
}

export class DeliveryAssist {
  constructor({ herdr, agmsg, monitor, config, audit, store }) {
    this.herdr = herdr;
    this.agmsg = agmsg;
    this.monitor = monitor;
    this.config = config;
    this.audit = audit;
    this.store = store;
    this.jobs = new Map();
  }

  async start(mission) {
    if (!this.config.deliveryAssist.enabled || !mission.spec.deliveryAssist) return;
    this.stop(mission.id);
    const state = {
      mission,
      seenMessageIds: new Map(),
      pending: new Set(),
      timer: null,
      running: true,
      failureCount: 0,
      nextAuditAt: 0,
    };
    for (const agent of mission.agents) {
      const persisted = mission.deliveryCursors?.[agent.agmsgName] ?? [];
      state.seenMessageIds.set(agent.agmsgName, new Set(persisted.map(String)));
    }
    this.jobs.set(mission.id, state);

    const tick = async () => {
      if (!state.running) return;
      try {
        await this.poll(state);
        state.failureCount = 0;
        state.nextAuditAt = 0;
      } catch (error) {
        state.failureCount += 1;
        const now = Date.now();
        if (now >= state.nextAuditAt) {
          const backoffMs = Math.min(
            this.config.deliveryAssist.pollMs * (2 ** (state.failureCount - 1)),
            60_000,
          );
          state.nextAuditAt = now + backoffMs;
          try {
            await this.audit.failure('delivery_assist.poll', error, { missionId: mission.id });
          } catch {
            // Delivery retries must not depend on audit availability.
          }
        }
      } finally {
        if (state.running) {
          state.timer = setTimeout(tick, this.config.deliveryAssist.pollMs);
          state.timer.unref?.();
        }
      }
    };
    state.timer = setTimeout(tick, this.config.deliveryAssist.pollMs);
    state.timer.unref?.();
  }

  stop(missionId) {
    const state = this.jobs.get(missionId);
    if (!state) return;
    state.running = false;
    if (state.timer) clearTimeout(state.timer);
    this.jobs.delete(missionId);
  }

  async poll(state) {
    const snapshot = this.monitor.latest ?? await this.herdr.snapshot();
    for (const agent of state.mission.agents) {
      const messages = await this.agmsg.messages(state.mission.spec.team, {
        agent: agent.agmsgName,
        limit: 100,
      });
      const seen = state.seenMessageIds.get(agent.agmsgName) ?? new Set();
      const inbound = messages.filter(
        (message) => message.to === agent.agmsgName && !seen.has(String(message.id)),
      );
      if (inbound.length) state.pending.add(agent.agmsgName);
      if (!state.pending.has(agent.agmsgName)) {
        state.seenMessageIds.set(
          agent.agmsgName,
          new Set(messages.map((message) => String(message.id))),
        );
        continue;
      }

      const herdrAgent = snapshot.agents?.find(
        (candidate) => candidate.name === agent.herdrName || candidate.pane_id === agent.paneId,
      );
      if (!herdrAgent) continue;
      const status = herdrAgent.agent_status ?? 'unknown';
      if (this.config.deliveryAssist.onlyWhenAgentNotWorking && !['idle', 'done'].includes(status)) continue;

      let deliveredInbound = inbound;
      let input;
      if (agent.runtime === 'codex') {
        // Codex actas is send-side only in current AGMSG. Reading via a generic
        // $agmsg nudge can resolve the wrong project identity when multiple
        // roles exist, so the Gateway reads the durable targeted messages and
        // injects an explicit, bounded delivery prompt into this exact pane.
        deliveredInbound = codexDeliveryBatch(inbound);
        input = buildCodexDeliveryPrompt({
          team: state.mission.spec.team,
          agent: agent.agmsgName,
          messages: deliveredInbound,
        });
      } else {
        input = agmsgCommand(agent.runtime);
      }
      await this.herdr.sendText(herdrAgent.pane_id, input);
      await sleep(this.config.deliveryAssist.inputDelayMs);
      await this.herdr.sendKeys(herdrAgent.pane_id, ['enter']);
      const deliveredIds = new Set(deliveredInbound.map((message) => String(message.id)));
      const remainingInbound = inbound.filter((message) => !deliveredIds.has(String(message.id)));
      if (remainingInbound.length === 0) state.pending.delete(agent.agmsgName);
      const nextSeen = new Set(seen);
      for (const message of messages) {
        const id = String(message.id);
        if (!remainingInbound.some((candidate) => String(candidate.id) === id)) nextSeen.add(id);
      }
      state.seenMessageIds.set(agent.agmsgName, nextSeen);
      if (this.store) {
        const deliveryCursors = Object.fromEntries(
          [...state.seenMessageIds].map(([name, ids]) => [name, [...ids].slice(-500)]),
        );
        const updated = await this.store.update(state.mission.id, { deliveryCursors });
        if (updated) state.mission = updated;
      }
      await this.audit.success('delivery_assist.nudge', {
        missionId: state.mission.id,
        agent: agent.agmsgName,
        paneId: herdrAgent.pane_id,
        mode: agent.runtime === 'codex' ? 'direct-message-batch' : 'skill-inbox',
        messageCount: deliveredInbound.length,
      });
    }
  }
}

export class MissionOrchestrator {
  constructor({ herdr, agmsg, monitor, config, store, audit, events }) {
    this.herdr = herdr;
    this.agmsg = agmsg;
    this.monitor = monitor;
    this.config = config;
    this.store = store;
    if (store instanceof MissionStore) store.audit = audit;
    this.audit = audit;
    this.events = events;
    this.delivery = new DeliveryAssist({ herdr, agmsg, monitor, config, audit, store });
    this.reconcileQueue = Promise.resolve();
  }

  profile(id) {
    const profile = this.config.profiles.find((candidate) => candidate.id === id);
    if (!profile) throw requestError(`Unknown agent profile: ${id}`);
    return profile;
  }

  async resumeRunning() {
    const records = await this.store.list();
    for (const mission of records.filter((record) => record.status === 'starting')) {
      const failed = await this.store.update(mission.id, {
        status: 'failed',
        error: 'gateway restarted during start',
      });
      this.events.publish('mission', failed);
    }
    for (const mission of records.filter((record) => record.status === 'running')) {
      await this.delivery.start(mission);
    }
  }

  async validateProjectPath(candidate) {
    let resolved;
    try {
      resolved = await realpath(candidate);
    } catch (error) {
      if (error?.code === 'ENOENT') throw requestError(`projectPath does not exist: ${candidate}`);
      throw error;
    }
    const info = await stat(resolved);
    if (!info.isDirectory()) throw requestError('projectPath must be a directory');
    const roots = [];
    for (const root of this.config.projectRoots) {
      try {
        roots.push(await realpath(root));
      } catch {
        roots.push(root);
      }
    }
    if (!isPathAllowed(resolved, roots)) {
      throw requestError(`projectPath is outside configured projectRoots: ${resolved}`, 403, 'project_path_denied');
    }
    return resolved;
  }

  async start(rawSpec) {
    const spec = normalizeMissionSpec(rawSpec);
    spec.projectPath = await this.validateProjectPath(spec.projectPath);
    const orchestratorProfile = this.profile(spec.orchestratorProfileId);
    const executorProfiles = spec.executorProfileIds.map((id) => this.profile(id));
    if (orchestratorProfile.role !== 'orchestrator') {
      throw requestError(`${orchestratorProfile.id} is not an orchestrator profile`);
    }
    for (const profile of executorProfiles) {
      if (profile.role !== 'executor') {
        throw requestError(`${profile.id} is not an executor profile`);
      }
    }

    const id = randomUUID();
    const suffix = shortId(id);
    const controlAgmsgName = `herddeck-${suffix}`;
    const orchestratorAgmsgName = scopedAgmsgName(orchestratorProfile.agmsgName, suffix);
    const executorEntries = executorProfiles.map((profile, index) => ({
      profile,
      agmsgName: scopedAgmsgName(profile.agmsgName, suffix, index + 1),
    }));
    const record = {
      id,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      status: 'starting',
      spec,
      agents: [],
      workspaceId: null,
      tabId: null,
      controlAgmsgName,
      deliveryCursors: {},
      error: null,
    };
    await this.store.create(record);
    this.events.publish('mission', record);

    let createdWorkspaceId = null;
    try {
      await this.agmsg.join({
        team: spec.team,
        name: orchestratorAgmsgName,
        type: orchestratorProfile.runtime,
        project: spec.projectPath,
      });
      for (const entry of executorEntries) {
        await this.agmsg.join({
          team: spec.team,
          name: entry.agmsgName,
          type: entry.profile.runtime,
          project: spec.projectPath,
        });
      }
      await this.agmsg.join({
        team: spec.team,
        name: controlAgmsgName,
        type: 'claude-code',
        project: spec.projectPath,
      });

      const workspaceResult = await this.herdr.rpc('workspace.create', {
        cwd: spec.projectPath,
        focus: true,
        label: `HD · ${spec.title}`.slice(0, 80),
        env: { HERDDECK_MISSION_ID: id, HERDDECK_TEAM: spec.team },
      });
      if (workspaceResult?.type !== 'workspace_created') {
        throw new Error(`Unexpected workspace.create response: ${JSON.stringify(workspaceResult)}`);
      }
      const workspaceId = workspaceResult.workspace.workspace_id;
      createdWorkspaceId = workspaceId;
      const tabId = workspaceResult.tab.tab_id;
      const rootPaneId = workspaceResult.root_pane.pane_id;

      const orchestratorPrompt = buildOrchestratorPrompt({
        mission: { ...spec, id },
        profile: orchestratorProfile,
        executors: executorEntries,
        controlRecipient: controlAgmsgName,
        orchestratorAgmsgName,
      });
      const orchestratorName = `hd-${suffix}-orch`;
      const orchestratorResult = await this.herdr.startAgent({
        name: orchestratorName,
        cwd: spec.projectPath,
        workspace_id: workspaceId,
        tab_id: tabId,
        split: 'right',
        focus: true,
        argv: [...orchestratorProfile.argv, orchestratorPrompt],
        env: {
          ...orchestratorProfile.env,
          HERDDECK_MISSION_ID: id,
          HERDDECK_TEAM: spec.team,
          HERDDECK_ROLE: 'orchestrator',
        },
      });

      const agents = [{
        profileId: orchestratorProfile.id,
        runtime: orchestratorProfile.runtime,
        role: 'orchestrator',
        agmsgName: orchestratorAgmsgName,
        herdrName: orchestratorName,
        paneId: orchestratorResult.agent.pane_id,
        terminalId: orchestratorResult.agent.terminal_id,
      }];

      for (const [index, entry] of executorEntries.entries()) {
        const { profile } = entry;
        const herdrName = `hd-${suffix}-exec${index + 1}`;
        const prompt = buildExecutorPrompt({
          mission: spec,
          profile,
          ordinal: index + 1,
          agmsgName: entry.agmsgName,
          orchestratorAgmsgName,
        });
        const result = await this.herdr.startAgent({
          name: herdrName,
          cwd: spec.projectPath,
          workspace_id: workspaceId,
          tab_id: tabId,
          split: index % 2 === 0 ? 'down' : 'right',
          focus: false,
          argv: [...profile.argv, prompt],
          env: {
            ...profile.env,
            HERDDECK_MISSION_ID: id,
            HERDDECK_TEAM: spec.team,
            HERDDECK_ROLE: profile.role,
          },
        });
        agents.push({
          profileId: profile.id,
          runtime: profile.runtime,
          role: profile.role,
          agmsgName: entry.agmsgName,
          herdrName,
          paneId: result.agent.pane_id,
          terminalId: result.agent.terminal_id,
        });
      }

      try {
        await this.herdr.rpc('pane.close', { pane_id: rootPaneId });
      } catch (error) {
        await this.audit.failure('mission.close_bootstrap_pane', error, { missionId: id, paneId: rootPaneId });
      }

      const updated = await this.store.update(id, {
        status: 'running',
        workspaceId,
        tabId,
        agents,
      });
      await this.monitor.refresh({ force: true }).catch(() => undefined);
      await this.delivery.start(updated);
      await this.audit.success('mission.start', {
        missionId: id,
        team: spec.team,
        project: spec.projectPath,
        profiles: [orchestratorProfile.id, ...executorProfiles.map((profile) => profile.id)],
      });
      this.events.publish('mission', updated);
      return updated;
    } catch (error) {
      if (createdWorkspaceId) {
        try {
          await this.herdr.rpc('workspace.close', { workspace_id: createdWorkspaceId });
        } catch (cleanupError) {
          await this.audit.failure('mission.cleanup_workspace', cleanupError, {
            missionId: id,
            workspaceId: createdWorkspaceId,
          });
        }
      }
      const failed = await this.store.update(id, { status: 'failed', error: error.message });
      await this.audit.failure('mission.start', error, { missionId: id, team: spec.team });
      this.events.publish('mission', failed);
      throw error;
    }
  }

  reconcileSnapshot(snapshot) {
    this.reconcileQueue = this.reconcileQueue
      .then(() => this.#reconcileSnapshot(snapshot))
      .catch(async (error) => {
        await this.audit.failure('mission.reconcile', error);
      });
    return this.reconcileQueue;
  }

  async #reconcileSnapshot(snapshot) {
    const records = await this.store.list();
    for (const mission of records.filter((record) => record.status === 'running')) {
      const orchestratorAgent = mission.agents.find((agent) => agent.role === 'orchestrator');
      if (!orchestratorAgent) continue;
      let explicitCompletion = false;
      if (mission.controlAgmsgName) {
        try {
          const messages = await this.agmsg.messages(mission.spec.team, {
            agent: mission.controlAgmsgName,
            limit: 100,
          });
          explicitCompletion = messages.some((message) =>
            message.to === mission.controlAgmsgName &&
            message.from === orchestratorAgent.agmsgName &&
            String(message.body ?? '').trimStart().startsWith(`MISSION_DONE ${mission.id}`),
          );
        } catch (error) {
          try {
            await this.audit.failure('mission.agmsg_read', error, { missionId: mission.id });
          } catch {
            // Reconciliation must not depend on audit availability.
          }
          try {
            this.events.publish('gateway-warning', {
              source: 'agmsg',
              missionId: mission.id,
              message: error.message,
              at: new Date().toISOString(),
            });
          } catch {
            // Continue with Herdr status fallback for every mission.
          }
        }
      }
      const liveByPane = new Map((snapshot.agents ?? []).map((agent) => [agent.pane_id, agent]));
      const orchestratorLive = liveByPane.get(orchestratorAgent.paneId);
      if (!explicitCompletion && orchestratorLive?.agent_status !== 'done') continue;

      const everyExecutorSettled = mission.agents
        .filter((agent) => agent.role !== 'orchestrator')
        .every((agent) => {
          const status = liveByPane.get(agent.paneId)?.agent_status;
          return status === 'done' || status === 'idle';
        });
      if (!explicitCompletion && !everyExecutorSettled) continue;

      const completed = await this.store.update(mission.id, { status: 'completed', error: null });
      this.delivery.stop(mission.id);
      await this.audit.success('mission.complete', { missionId: mission.id });
      this.events.publish('mission', completed);
    }
  }

  async startProfile(raw) {
    const profile = this.profile(String(raw?.profileId ?? ''));
    const projectPath = await this.validateProjectPath(String(raw?.projectPath ?? ''));
    const id = randomUUID();
    const name = String(raw?.name || `hd-${slug(profile.role)}-${shortId(id)}`).slice(0, 80);
    const initialPrompt = String(raw?.prompt ?? '').trim();
    const argv = initialPrompt ? [...profile.argv, initialPrompt] : [...profile.argv];
    const result = await this.herdr.startAgent({
      name,
      cwd: projectPath,
      split: raw?.split === 'down' ? 'down' : 'right',
      focus: raw?.focus !== false,
      argv,
      env: { ...profile.env, HERDDECK_PROFILE_ID: profile.id },
    });
    await this.audit.success('profile.start', {
      profileId: profile.id,
      project: projectPath,
      paneId: result.agent.pane_id,
    });
    await sleep(100);
    await this.monitor.refresh({ force: true }).catch(() => undefined);
    return result;
  }
}
