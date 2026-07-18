import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { HerdrClient, HerdrRpcError } from '../src/herdr-client.mjs';

async function withMockHerdr(handler, body) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'herddeck-herdr-'));
  const socketPath = path.join(directory, 'herdr.sock');
  const server = net.createServer((socket) => {
    socket.setEncoding('utf8');
    let buffer = '';
    socket.on('data', (chunk) => {
      buffer += chunk;
      if (!buffer.includes('\n')) return;
      const line = buffer.slice(0, buffer.indexOf('\n'));
      const request = JSON.parse(line);
      handler(socket, request);
    });
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(socketPath, resolve);
  });
  try {
    await body(new HerdrClient({ socketPath, timeoutMs: 1000 }));
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
}

test('HerdrClient unwraps session.snapshot', async () => {
  await withMockHerdr((socket, request) => {
    assert.equal(request.method, 'session.snapshot');
    socket.end(`${JSON.stringify({
      id: request.id,
      result: {
        type: 'session_snapshot',
        snapshot: {
          version: '0.10.0', protocol: 1,
          workspaces: [], tabs: [], panes: [], layouts: [], agents: [],
        },
      },
    })}\n`);
  }, async (client) => {
    const snapshot = await client.snapshot();
    assert.equal(snapshot.version, '0.10.0');
    assert.deepEqual(snapshot.agents, []);
  });
});

test('HerdrClient sends exact pane input params', async () => {
  await withMockHerdr((socket, request) => {
    assert.equal(request.method, 'pane.send_input');
    assert.deepEqual(request.params, { pane_id: 'p1', text: 'hello', keys: ['enter'] });
    socket.end(`${JSON.stringify({ id: request.id, result: { type: 'ok' } })}\n`);
  }, async (client) => {
    const result = await client.sendInput('p1', 'hello', ['enter']);
    assert.equal(result.type, 'ok');
  });
});

test('HerdrClient maps protocol errors', async () => {
  await withMockHerdr((socket, request) => {
    socket.end(`${JSON.stringify({
      id: request.id,
      error: { code: 'agent_not_found', message: 'missing' },
    })}\n`);
  }, async (client) => {
    await assert.rejects(
      () => client.rpc('agent.get', { target: 'missing' }),
      (error) => error instanceof HerdrRpcError && error.code === 'agent_not_found',
    );
  });
});

test('HerdrClient keeps events.subscribe open and forwards pushed events', async () => {
  await withMockHerdr((socket, request) => {
    assert.equal(request.method, 'events.subscribe');
    assert.deepEqual(request.params.subscriptions, [{ type: 'workspace.created' }]);
    socket.write(`${JSON.stringify({
      id: request.id,
      result: { type: 'events_subscribed', subscription_count: 1 },
    })}\n`);
    socket.write(`${JSON.stringify({
      event: 'workspace_created',
      data: { workspace: { workspace_id: 'w1' } },
    })}\n`);
  }, async (client) => {
    const event = await new Promise(async (resolve, reject) => {
      const subscription = client.subscribe(
        [{ type: 'workspace.created' }],
        { onEvent: resolve, onError: reject },
      );
      try {
        await subscription.ready;
      } catch (error) {
        reject(error);
      }
      setTimeout(() => subscription.close(), 25).unref?.();
    });
    assert.equal(event.event, 'workspace_created');
    assert.equal(event.data.workspace.workspace_id, 'w1');
  });
});
