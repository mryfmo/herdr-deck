import test from 'node:test';
import assert from 'node:assert/strict';
import { chmod, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { MoshSessionManager, __test } from '../src/mosh-manager.mjs';

async function executable(directory, name, body) {
  const path = join(directory, name);
  await writeFile(path, `#!/bin/sh\n${body}\n`, 'utf8');
  await chmod(path, 0o755);
  return path;
}

test('normalizes and validates Mosh port ranges', () => {
  assert.equal(__test.normalizePortRange('60000:61000'), '60000:61000');
  assert.equal(__test.normalizePortRange('60001'), '60001');
  assert.throws(() => __test.normalizePortRange('61000:60000'));
  assert.throws(() => __test.normalizePortRange('not-a-port'));
});

test('reports disabled capability without throwing', async () => {
  const manager = new MoshSessionManager({
    config: { enabled: false },
    monitor: { latest: { panes: [] } },
    audit: { success: async () => undefined },
  });
  await manager.initialize();
  assert.equal(manager.capabilities().enabled, false);
  assert.equal(manager.capabilities().reason, 'disabled');
});

test('starts a session and never includes the key in audit data', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'herddeck-mosh-'));
  try {
    const fakeMosh = await executable(
      directory,
      'mosh-server',
      "printf 'MOSH CONNECT 60042 dGVzdC1rZXk\\n[mosh-server detached, pid = 4242]\\n'",
    );
    const fakeHerdr = await executable(directory, 'herdr', 'exit 0');
    const auditRecords = [];
    const manager = new MoshSessionManager({
      config: {
        enabled: true,
        serverPath: fakeMosh,
        herdrPath: fakeHerdr,
        advertiseHost: 'macbook.example.ts.net',
        bindAddress: '100.64.0.10',
        portRange: '60000:61000',
      },
      monitor: { latest: { panes: [{ pane_id: 'w1:p1' }] } },
      audit: { success: async (name, data) => auditRecords.push({ name, data }) },
    });
    await manager.initialize();
    const session = await manager.createSession({
      paneId: 'w1:p1',
      columns: 120,
      rows: 42,
      predictionMode: 'always',
    });
    assert.equal(session.host, 'macbook.example.ts.net');
    assert.equal(session.port, 60042);
    assert.equal(session.key, 'dGVzdC1rZXk');
    assert.equal(session.predictionMode, 'always');
    assert.equal(auditRecords.length, 1);
    assert.equal(JSON.stringify(auditRecords).includes(session.key), false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('expires stored session metadata after ten minutes', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const directory = await mkdtemp(join(tmpdir(), 'herddeck-mosh-'));
  try {
    const fakeMosh = await executable(
      directory,
      'mosh-server',
      "printf 'MOSH CONNECT 60042 dGVzdC1rZXk\\n'",
    );
    const fakeHerdr = await executable(directory, 'herdr', 'exit 0');
    const manager = new MoshSessionManager({
      config: {
        enabled: true,
        serverPath: fakeMosh,
        herdrPath: fakeHerdr,
        advertiseHost: 'macbook.example.ts.net',
      },
      monitor: { latest: { panes: [{ pane_id: 'w1:p1' }] } },
      audit: { success: async () => undefined },
    });
    await manager.initialize();
    const session = await manager.createSession({ paneId: 'w1:p1' });
    assert.equal(manager.sessions.has(session.id), true);

    t.mock.timers.tick(600_000);

    assert.equal(manager.sessions.has(session.id), false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('rejects unsupported prediction modes before launching mosh-server', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'herddeck-mosh-'));
  try {
    const fakeMosh = await executable(directory, 'mosh-server', 'exit 0');
    const fakeHerdr = await executable(directory, 'herdr', 'exit 0');
    const manager = new MoshSessionManager({
      config: {
        enabled: true,
        serverPath: fakeMosh,
        herdrPath: fakeHerdr,
        advertiseHost: '100.64.0.10',
      },
      monitor: { latest: { panes: [{ pane_id: 'w1:p1' }] } },
      audit: { success: async () => undefined },
    });
    await manager.initialize();
    await assert.rejects(
      () => manager.createSession({ paneId: 'w1:p1', predictionMode: 'experimental' }),
      (error) => error.code === 'invalid_prediction_mode' && error.statusCode === 400,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('rejects unknown panes before launching mosh-server', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'herddeck-mosh-'));
  try {
    const fakeMosh = await executable(directory, 'mosh-server', 'exit 0');
    const fakeHerdr = await executable(directory, 'herdr', 'exit 0');
    const manager = new MoshSessionManager({
      config: {
        enabled: true,
        serverPath: fakeMosh,
        herdrPath: fakeHerdr,
        advertiseHost: '100.64.0.10',
      },
      monitor: { latest: { panes: [] } },
      audit: { success: async () => undefined },
    });
    await manager.initialize();
    await assert.rejects(
      () => manager.createSession({ paneId: 'w1:p404' }),
      (error) => error.code === 'pane_not_found' && error.statusCode === 404,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
