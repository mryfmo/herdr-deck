import { randomUUID } from 'node:crypto';
import { URL } from 'node:url';
import { authorize } from './auth.mjs';
import { normalizeError, requestError } from './utils.mjs';
import { publicProfile } from './workflow.mjs';

const ALLOWED_RPC_METHODS = new Set([
  'ping',
  'session.snapshot',
  'workspace.list',
  'workspace.get',
  'workspace.focus',
  'workspace.rename',
  'tab.list',
  'tab.get',
  'tab.focus',
  'tab.rename',
  'pane.list',
  'pane.current',
  'pane.get',
  'pane.rename',
  'pane.read',
  'pane.zoom',
  'pane.layout',
  'pane.focus_direction',
  'pane.resize',
  'agent.list',
  'agent.get',
  'agent.read',
  'agent.explain',
  'agent.focus',
  'agent.rename',
]);
const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,128}$/;

function securityHeaders(response) {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");
}

function json(response, status, body) {
  securityHeaders(response);
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  response.end(`${JSON.stringify(body)}\n`);
}

function noContent(response) {
  securityHeaders(response);
  response.writeHead(204);
  response.end();
}

async function readJsonBody(request, limit) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > limit) {
      const error = new Error(`Request body exceeds ${limit} bytes`);
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch (error) {
    const wrapped = new Error(`Invalid JSON body: ${error.message}`);
    wrapped.statusCode = 400;
    throw wrapped;
  }
}

function cors(request, response, allowedOrigins) {
  const origin = request.headers.origin;
  if (!origin) return true;
  if (!allowedOrigins.includes(origin)) return false;
  response.setHeader('Access-Control-Allow-Origin', origin);
  response.setHeader('Vary', 'Origin');
  response.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  return true;
}

function decodeSegment(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    throw requestError('Malformed URL segment');
  }
}

export function createRouter(context) {
  const {
    config,
    configPath,
    token,
    tokenFingerprint,
    limiter,
    herdr,
    monitor,
    agmsg,
    missions,
    orchestrator,
    mosh,
    events,
    audit,
  } = context;

  return async function route(request, response) {
    const startedAt = Date.now();
    let requestId;

    try {
      const candidateRequestId = request.headers['x-request-id'];
      requestId = typeof candidateRequestId === 'string' && REQUEST_ID_PATTERN.test(candidateRequestId)
        ? candidateRequestId
        : randomUUID();
      response.setHeader('X-Request-ID', requestId);
      if (!cors(request, response, config.allowedOrigins)) {
        return json(response, 403, { error: { code: 'origin_denied', message: 'Origin is not allowed' } });
      }
      if (request.method === 'OPTIONS') return noContent(response);

      const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`);
      if (request.method === 'GET' && url.pathname === '/healthz') {
        return json(response, 200, { ok: true });
      }

      if (!url.pathname.startsWith('/v1/')) {
        return json(response, 404, { error: { code: 'not_found', message: 'Route not found' } });
      }
      if (!authorize(request, token)) {
        return json(response, 401, { error: { code: 'unauthorized', message: 'Bearer token required' } });
      }
      const rateKey = `${request.socket.remoteAddress ?? 'local'}:${tokenFingerprint}`;
      if (!limiter.allow(rateKey)) {
        return json(response, 429, { error: { code: 'rate_limited', message: 'Too many requests' } });
      }

      if (request.method === 'GET' && url.pathname === '/v1/health') {
        const [ping, agmsgChecks, moshChecks] = await Promise.all([
          herdr.ping().catch((error) => ({ error: normalizeError(error) })),
          agmsg.preflight(),
          mosh.preflight(),
        ]);
        return json(response, 200, {
          gateway: {
            name: 'HerdDeck Gateway',
            version: '0.2.0',
            configPath,
            tokenFingerprint,
            bind: `${config.bindHost}:${config.port}`,
          },
          herdr: ping,
          agmsg: { ok: agmsgChecks.every((check) => check.ok), checks: agmsgChecks },
          mosh: {
            ...mosh.capabilities(),
            checks: moshChecks,
          },
          snapshotAt: monitor.updatedAt,
        });
      }

      if (request.method === 'GET' && url.pathname === '/v1/mosh/capabilities') {
        return json(response, 200, { mosh: mosh.capabilities() });
      }

      if (request.method === 'POST' && url.pathname === '/v1/mosh/sessions') {
        const body = await readJsonBody(request, config.requestBodyLimitBytes);
        const session = await mosh.createSession({
          paneId: body.paneId,
          columns: body.columns,
          rows: body.rows,
          predictionMode: body.predictionMode,
        });
        return json(response, 201, { session });
      }

      if (request.method === 'GET' && url.pathname === '/v1/profiles') {
        return json(response, 200, { profiles: config.profiles.map(publicProfile) });
      }

      if (request.method === 'POST' && url.pathname === '/v1/profiles/start') {
        const body = await readJsonBody(request, config.requestBodyLimitBytes);
        const result = await orchestrator.startProfile(body);
        return json(response, 201, result);
      }

      if (request.method === 'GET' && url.pathname === '/v1/herdr/snapshot') {
        const snapshot = await monitor.refresh();
        return json(response, 200, { snapshot });
      }

      const paneReadMatch = url.pathname.match(/^\/v1\/herdr\/panes\/([^/]+)\/read$/);
      if (request.method === 'GET' && paneReadMatch) {
        const paneId = decodeSegment(paneReadMatch[1]);
        const source = url.searchParams.get('source') ?? 'visible';
        const lines = Math.min(
          Math.max(Number(url.searchParams.get('lines')) || config.terminalReadLimit, 1),
          config.terminalReadLimit,
        );
        const format = url.searchParams.get('format') === 'ansi' ? 'ansi' : 'text';
        const read = await herdr.readPane(paneId, { source, lines, format, stripAnsi: format !== 'ansi' });
        return json(response, 200, { read });
      }

      const paneInputMatch = url.pathname.match(/^\/v1\/herdr\/panes\/([^/]+)\/input$/);
      if (request.method === 'POST' && paneInputMatch) {
        const paneId = decodeSegment(paneInputMatch[1]);
        const body = await readJsonBody(request, config.requestBodyLimitBytes);
        const text = typeof body.text === 'string' ? body.text : '';
        if (body.keys !== undefined && !Array.isArray(body.keys)) {
          throw requestError('keys must be an array of Herdr key-combo strings');
        }
        const keys = body.keys ?? [];
        if (keys.length > 32) {
          throw requestError('At most 32 special keys may be sent per request');
        }
        if (!keys.every((key) => typeof key === 'string' && key.length >= 1 && key.length <= 64)) {
          throw requestError('Each special key must be a 1-64 character string');
        }
        if (Buffer.byteLength(text, 'utf8') > 65_536) {
          throw requestError('Terminal input exceeds 64 KiB', 413, 'terminal_input_too_large');
        }
        const result = await herdr.sendInput(paneId, text, keys);
        await audit.success('pane.input', {
          paneId,
          textBytes: Buffer.byteLength(text, 'utf8'),
          keys,
          requestId,
        });
        return json(response, 200, result);
      }

      if (request.method === 'POST' && url.pathname === '/v1/herdr/rpc') {
        const body = await readJsonBody(request, config.requestBodyLimitBytes);
        const method = String(body.method ?? '');
        if (!ALLOWED_RPC_METHODS.has(method)) {
          const error = new Error(`Herdr method is not allowed through the mobile gateway: ${method}`);
          error.statusCode = 403;
          throw error;
        }
        const result = await herdr.rpc(method, body.params ?? {});
        await audit.success('herdr.rpc', { method, requestId });
        return json(response, 200, { result });
      }

      if (request.method === 'GET' && url.pathname === '/v1/events') {
        securityHeaders(response);
        events.add(response);
        events.send(response, 'hello', { requestId, at: new Date().toISOString() });
        if (monitor.latest) events.send(response, 'snapshot', { snapshot: monitor.latest });
        return;
      }

      if (request.method === 'GET' && url.pathname === '/v1/agmsg/teams') {
        return json(response, 200, { teams: await agmsg.teams() });
      }

      const membersMatch = url.pathname.match(/^\/v1\/agmsg\/teams\/([^/]+)\/members$/);
      if (request.method === 'GET' && membersMatch) {
        const team = decodeSegment(membersMatch[1]);
        return json(response, 200, { members: await agmsg.members(team) });
      }

      const messagesMatch = url.pathname.match(/^\/v1\/agmsg\/teams\/([^/]+)\/messages$/);
      if (request.method === 'GET' && messagesMatch) {
        const team = decodeSegment(messagesMatch[1]);
        const agent = url.searchParams.get('agent') ?? undefined;
        const beforeId = url.searchParams.get('beforeId') ?? undefined;
        const limit = Math.min(Math.max(Number(url.searchParams.get('limit')) || 50, 1), 500);
        return json(response, 200, {
          messages: await agmsg.messages(team, { agent, beforeId, limit }),
        });
      }

      if (request.method === 'POST' && url.pathname === '/v1/agmsg/messages') {
        const body = await readJsonBody(request, config.requestBodyLimitBytes);
        await agmsg.send({ team: body.team, from: body.from, to: body.to, body: body.body });
        await audit.success('agmsg.send', {
          team: body.team,
          from: body.from,
          to: body.to,
          bodyBytes: Buffer.byteLength(String(body.body ?? ''), 'utf8'),
          requestId,
        });
        events.publish('agmsg', { team: body.team, at: new Date().toISOString() });
        return json(response, 201, { ok: true });
      }

      if (request.method === 'GET' && url.pathname === '/v1/missions') {
        return json(response, 200, { missions: await missions.list() });
      }

      if (request.method === 'POST' && url.pathname === '/v1/missions') {
        const body = await readJsonBody(request, config.requestBodyLimitBytes);
        return json(response, 201, { mission: await orchestrator.start(body) });
      }

      const missionMatch = url.pathname.match(/^\/v1\/missions\/([^/]+)$/);
      if (request.method === 'GET' && missionMatch) {
        const mission = await missions.get(decodeSegment(missionMatch[1]));
        if (!mission) return json(response, 404, { error: { code: 'not_found', message: 'Mission not found' } });
        return json(response, 200, { mission });
      }

      return json(response, 404, { error: { code: 'not_found', message: 'Route not found' } });
    } catch (error) {
      const status = error.statusCode || (error.code === 'ENOENT' ? 503 : 500);
      await audit.failure('http.request', error, {
        requestId,
        method: request.method,
        path: request.url,
        durationMs: Date.now() - startedAt,
      }).catch(() => undefined);
      return json(response, status, {
        error: {
          code: error.code || (status === 500 ? 'internal_error' : 'request_error'),
          message: error.message,
        },
      });
    }
  };
}
