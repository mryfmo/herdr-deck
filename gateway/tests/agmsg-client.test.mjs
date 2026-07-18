import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { chmod, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { AgmsgClient } from '../src/agmsg-client.mjs';
import { loadConfig } from '../src/config.mjs';

const execFileAsync = promisify(execFile);
const adapter = fileURLToPath(new URL('../scripts/agmsg-api.sh', import.meta.url));

async function fixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'herddeck-agmsg-'));
  const scripts = path.join(root, 'scripts');
  const teams = path.join(root, 'teams');
  const database = path.join(root, 'db', 'messages.db');
  await Promise.all([
    mkdir(scripts),
    mkdir(path.join(teams, 'alpha'), { recursive: true }),
    mkdir(path.join(teams, 'beta'), { recursive: true }),
    mkdir(path.dirname(database), { recursive: true }),
  ]);
  await writeFile(path.join(teams, 'alpha', 'config.json'), JSON.stringify({
    name: 'alpha',
    agents: {
      builder: {
        registrations: [
          { type: 'codex', project: '/tmp/old' },
          { type: 'codex', project: '/tmp/project' },
        ],
      },
      orchestrator: { type: 'claude-code', project: '/tmp/project' },
    },
  }));
  await writeFile(path.join(teams, 'beta', 'config.json'), JSON.stringify({ name: 'beta', agents: {} }));
  await execFileAsync('sqlite3', [database, `
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      team TEXT NOT NULL,
      from_agent TEXT NOT NULL,
      to_agent TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL,
      read_at TEXT
    );
    INSERT INTO messages VALUES (1, 'alpha', 'orchestrator', 'other', 'old', '2026-07-12T00:00:00Z', NULL);
    INSERT INTO messages VALUES (2, 'alpha', 'orchestrator', 'builder', 'build "it"', '2026-07-12T00:01:00Z', NULL);
    INSERT INTO messages VALUES (3, 'alpha', 'builder', 'orchestrator', 'done', '2026-07-12T00:02:00Z', NULL);
    INSERT INTO messages VALUES (4, 'alpha', 'orchestrator', 'other', 'unrelated', '2026-07-12T00:03:00Z', NULL);
  `]);
  for (const [name, content] of Object.entries({
    'send.sh': '#!/bin/bash\nexit 0\n',
    'join.sh': '#!/bin/bash\nexit 0\n',
    'delivery.sh': '#!/bin/bash\nprintf "turn\\n"\n',
  })) {
    const file = path.join(scripts, name);
    await writeFile(file, content);
    await chmod(file, 0o755);
  }
  return { root, dispose: () => rm(root, { recursive: true, force: true }) };
}

test('AgmsgClient reads teams, members, and ordered messages through the repository adapter', async () => {
  const f = await fixture();
  try {
    const client = new AgmsgClient({ root: f.root });
    assert.deepEqual(await client.teams(), ['alpha', 'beta']);
    assert.deepEqual(await client.members('alpha'), [
      { name: 'builder', type: 'codex', project: '/tmp/project' },
      { name: 'orchestrator', type: 'claude-code', project: '/tmp/project' },
    ]);
    const messages = await client.messages('alpha', { agent: 'builder', limit: 2 });
    assert.deepEqual(messages.map((message) => message.id), [2, 3]);
    assert.deepEqual(messages.map((message) => message.type), ['message', 'message']);
    assert.equal(messages[0].body, 'build "it"');
    assert.deepEqual(
      (await client.messages('alpha', { beforeId: 3, limit: 10 })).map((message) => message.id),
      [1, 2],
    );
    const checks = await client.preflight();
    assert.equal(checks.find((check) => check.name === 'agmsg-api.sh')?.ok, true);
    await client.send({ team: 'alpha', from: 'orchestrator', to: 'builder', body: 'go' });
    await client.join({ team: 'alpha', name: 'agent', type: 'antigravity', project: '/tmp/project' });
    await assert.rejects(
      () => client.join({ team: 'alpha', name: 'agent', type: 'opencode', project: '/tmp/project' }),
      /Unsupported agmsg agent type/,
    );

    const storage = path.join(f.root, 'alternate-storage');
    const alternateDatabase = path.join(storage, 'messages.db');
    await mkdir(storage);
    await execFileAsync('sqlite3', [alternateDatabase, `
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY, team TEXT, from_agent TEXT, to_agent TEXT,
        body TEXT, created_at TEXT, read_at TEXT
      );
      INSERT INTO messages VALUES (99, 'alpha', 'alternate', 'builder', 'override', '2026-07-12T01:00:00Z', NULL);
    `]);
    const { stdout } = await execFileAsync(adapter, [
      'get', 'teams', 'alpha', 'messages', '--limit', '1',
    ], {
      env: { ...process.env, AGMSG_ROOT: f.root, AGMSG_STORAGE_PATH: storage },
    });
    assert.equal(JSON.parse(stdout).id, 99);
  } finally {
    await f.dispose();
  }
});

test('AgmsgClient rejects shell-shaped identities', async () => {
  const f = await fixture();
  try {
    const client = new AgmsgClient({ root: f.root });
    await assert.rejects(() => client.messages('alpha; rm -rf /'), /must match/);
  } finally {
    await f.dispose();
  }
});

test('config accepts only runtimes supported by join.sh', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'herddeck-config-'));
  const configFor = (runtime) => ({
    projectRoots: [directory],
    herdrSocket: path.join(directory, 'herdr.sock'),
    tokenFile: path.join(directory, 'token'),
    auditLog: path.join(directory, 'audit.jsonl'),
    missionStore: path.join(directory, 'missions.json'),
    agmsgRoot: directory,
    profiles: [{
      id: 'agent',
      displayName: 'Agent',
      runtime,
      role: 'orchestrator',
      agmsgName: 'agent',
      modelLabel: 'Model',
      effortLabel: 'High',
      argv: ['agent'],
    }],
  });
  try {
    const accepted = path.join(directory, 'accepted.json');
    await writeFile(accepted, JSON.stringify(configFor('antigravity')));
    assert.equal((await loadConfig(accepted)).config.profiles[0].runtime, 'antigravity');

    const rejected = path.join(directory, 'rejected.json');
    await writeFile(rejected, JSON.stringify(configFor('other')));
    await assert.rejects(() => loadConfig(rejected), /unsupported runtime other/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('config rejects a non-array profiles value explicitly', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'herddeck-config-profiles-'));
  const configPath = path.join(directory, 'config.json');
  try {
    await writeFile(configPath, JSON.stringify({
      projectRoots: [directory],
      herdrSocket: path.join(directory, 'herdr.sock'),
      tokenFile: path.join(directory, 'token'),
      auditLog: path.join(directory, 'audit.jsonl'),
      missionStore: path.join(directory, 'missions.json'),
      agmsgRoot: directory,
      profiles: {},
    }));
    await assert.rejects(() => loadConfig(configPath), /profiles must be an array/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
