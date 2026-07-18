import http from 'node:http';
import { SlidingWindowRateLimiter, loadOrCreateToken, tokenFingerprint } from './auth.mjs';
import { loadConfig } from './config.mjs';
import { AgmsgClient } from './agmsg-client.mjs';
import { AuditLog } from './audit.mjs';
import { HerdrClient, SnapshotMonitor } from './herdr-client.mjs';
import { createRouter } from './router.mjs';
import { SseHub } from './sse.mjs';
import { MissionOrchestrator, MissionStore } from './workflow.mjs';
import { MoshSessionManager } from './mosh-manager.mjs';

const { config, configPath } = await loadConfig();
const token = await loadOrCreateToken(config.tokenFile);
const fingerprint = tokenFingerprint(token);
const audit = new AuditLog(config.auditLog);
const events = new SseHub();
const herdr = new HerdrClient({ socketPath: config.herdrSocket });
const monitor = new SnapshotMonitor(herdr, config.snapshotPollMs);
const agmsg = new AgmsgClient({ root: config.agmsgRoot });
const missions = new MissionStore(config.missionStore);
const limiter = new SlidingWindowRateLimiter(config.rateLimit);
const mosh = new MoshSessionManager({ config: config.mosh, monitor, audit });
await mosh.initialize();
const orchestrator = new MissionOrchestrator({
  herdr,
  agmsg,
  monitor,
  config,
  store: missions,
  audit,
  events,
});

monitor.on('snapshot', (snapshot) => {
  events.publish('snapshot', { snapshot });
  void orchestrator.reconcileSnapshot(snapshot);
});
monitor.on('error', (error) => events.publish('gateway-error', {
  code: error.code ?? 'herdr_unavailable',
  message: error.message,
  at: new Date().toISOString(),
}));
monitor.on('warning', (error) => events.publish('gateway-warning', {
  code: error.code ?? 'herdr_event_stream_unavailable',
  message: error.message,
  at: new Date().toISOString(),
}));
monitor.on('herdr-event', (event) => events.publish('herdr-event', event));
await orchestrator.resumeRunning();
monitor.start();

const router = createRouter({
  config,
  configPath,
  token,
  tokenFingerprint: fingerprint,
  limiter,
  herdr,
  monitor,
  agmsg,
  missions,
  orchestrator,
  mosh,
  events,
  audit,
});

const server = http.createServer((request, response) => {
  void router(request, response);
});
server.requestTimeout = 35_000;
server.headersTimeout = 10_000;
server.keepAliveTimeout = 5_000;
server.maxRequestsPerSocket = 1000;

server.listen(config.port, config.bindHost, async () => {
  const address = `http://${config.bindHost}:${config.port}`;
  console.log(`HerdDeck Gateway listening on ${address}`);
  console.log(`Config: ${configPath}`);
  console.log(`Token: ${config.tokenFile} (sha256:${fingerprint})`);
  console.log('Expose only with: tailscale serve --bg http://127.0.0.1:' + config.port);
  await audit.success('gateway.start', { address, configPath, tokenFingerprint: fingerprint });
});

async function shutdown(signal) {
  console.log(`\n${signal}: shutting down HerdDeck Gateway`);
  monitor.stop();
  events.close();
  server.close(async () => {
    await audit.success('gateway.stop', { signal }).catch(() => undefined);
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('uncaughtException', async (error) => {
  console.error(error);
  await audit.failure('gateway.uncaught_exception', error).catch(() => undefined);
  process.exit(1);
});
process.on('unhandledRejection', async (error) => {
  console.error(error);
  await audit.failure('gateway.unhandled_rejection', error).catch(() => undefined);
  process.exit(1);
});
