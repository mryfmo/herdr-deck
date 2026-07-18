import assert from 'node:assert/strict';
import test from 'node:test';
import { HerdrRpcError } from '../src/herdr-client.mjs';
import { createRouter } from '../src/router.mjs';

function response() {
  return {
    headers: new Map(),
    status: null,
    body: '',
    setHeader(name, value) { this.headers.set(name, value); },
    writeHead(status) { this.status = status; },
    end(body = '') { this.body = body; },
  };
}

function request(path, {
  authorization,
  remoteAddress = '100.64.0.7',
  method = 'GET',
  body,
} = {}) {
  return {
    method,
    url: path,
    headers: {
      host: 'localhost',
      ...(authorization ? { authorization } : {}),
    },
    socket: { remoteAddress },
    async *[Symbol.asyncIterator]() {
      if (body !== undefined) yield Buffer.from(body);
    },
  };
}

function router(overrides = {}) {
  return createRouter({
    config: { allowedOrigins: [] },
    configPath: '/tmp/config.json',
    token: 'secret',
    tokenFingerprint: 'constant-fingerprint',
    limiter: { allow() { return true; } },
    herdr: {},
    monitor: {},
    agmsg: {},
    missions: {},
    orchestrator: {},
    mosh: {},
    events: {},
    audit: { async failure() {} },
    ...overrides,
  });
}

function errorBody(result) {
  return JSON.parse(result.body).error;
}

test('/healthz does not require authentication or consume rate limit', async () => {
  let limited = false;
  const result = response();
  await router({ limiter: { allow() { limited = true; return false; } } })(
    request('/healthz'),
    result,
  );
  assert.equal(result.status, 200);
  assert.equal(limited, false);
});

test('protected routes return 401 without a bearer token', async () => {
  const result = response();
  await router()(request('/v1/profiles'), result);
  assert.equal(result.status, 401);
  assert.equal(errorBody(result).code, 'unauthorized');
});

test('rate limit is keyed by source address and precedes authorization', async () => {
  const keys = [];
  const route = router({
    limiter: {
      allow(key) {
        keys.push(key);
        return keys.length === 1;
      },
    },
  });

  const unauthorized = response();
  await route(request('/v1/profiles'), unauthorized);
  assert.equal(unauthorized.status, 401);

  const limited = response();
  await route(request('/v1/profiles', { authorization: 'Bearer secret' }), limited);
  assert.equal(limited.status, 429);
  assert.deepEqual(keys, ['100.64.0.7', '100.64.0.7']);
});

for (const [code, status] of [
  ['pane_not_found', 404],
  ['agent_not_found', 404],
  ['invalid_pane_id', 400],
]) {
  test(`HerdrRpcError ${code} maps to HTTP ${status}`, async () => {
    const result = response();
    await router({
      herdr: {
        async readPane() { throw new HerdrRpcError(code, 'rpc failed', 'request-1'); },
      },
    })(
      request('/v1/herdr/panes/p1/read', { authorization: 'Bearer secret' }),
      result,
    );
    assert.equal(result.status, status);
    assert.deepEqual(errorBody(result), { code, message: 'rpc failed' });
  });
}

test('HerdrRpcError fallback is 502 and its envelope code is always a string', async () => {
  const result = response();
  await router({
    herdr: {
      async readPane() { throw new HerdrRpcError(17, 'rpc failed', 'request-1'); },
    },
  })(
    request('/v1/herdr/panes/p1/read', { authorization: 'Bearer secret' }),
    result,
  );
  assert.equal(result.status, 502);
  assert.deepEqual(errorBody(result), { code: '17', message: 'rpc failed' });
});

for (const body of ['null', '[]', '"text"', '42']) {
  test(`JSON body ${body} returns invalid_request`, async () => {
    const result = response();
    await router()(
      request('/v1/missions', {
        authorization: 'Bearer secret',
        method: 'POST',
        body,
      }),
      result,
    );
    assert.equal(result.status, 400);
    assert.equal(errorBody(result).code, 'invalid_request');
  });
}
