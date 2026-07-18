import { spawn } from 'node:child_process';
import { access, constants } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { randomUUID } from 'node:crypto';
import { requestError, runFile } from './utils.mjs';

const CONNECT_PATTERN = /MOSH CONNECT\s+(\d+)\s+([A-Za-z0-9+/=_-]+)/;
const DETACHED_PATTERN = /mosh-server detached, pid\s*=\s*(\d+)/i;

async function resolveExecutable(command) {
  if (!command) return null;
  if (isAbsolute(command)) {
    try {
      await access(command, constants.X_OK);
      return command;
    } catch {
      return null;
    }
  }
  try {
    const result = await runFile('/usr/bin/env', ['which', command], { timeout: 3000, maxBuffer: 64 * 1024 });
    return result.stdout.trim() || null;
  } catch {
    return null;
  }
}

function normalizePortRange(value) {
  const text = String(value ?? '60000:61000').trim();
  const match = text.match(/^(\d{1,5})(?::(\d{1,5}))?$/);
  if (!match) throw new Error(`Invalid Mosh port range: ${text}`);
  const first = Number(match[1]);
  const last = Number(match[2] ?? match[1]);
  if (first < 1024 || first > 65535 || last < first || last > 65535) {
    throw new Error(`Invalid Mosh port range: ${text}`);
  }
  return `${first}${last === first ? '' : `:${last}`}`;
}

function publicCapabilities(config, serverPath, herdrPath) {
  const enabled = config.enabled && Boolean(serverPath) && Boolean(herdrPath) && Boolean(config.advertiseHost);
  return {
    enabled,
    configured: config.enabled,
    embeddedClientRequired: true,
    advertiseHost: enabled ? config.advertiseHost : null,
    portRange: config.portRange,
    predictionMode: config.predictionMode,
    serverAvailable: Boolean(serverPath),
    herdrAvailable: Boolean(herdrPath),
    reason: enabled
      ? null
      : !config.enabled
        ? 'disabled'
        : !config.advertiseHost
          ? 'advertise_host_missing'
          : !serverPath
            ? 'mosh_server_missing'
            : 'herdr_missing',
  };
}

export class MoshSessionManager {
  constructor({ config, monitor, audit }) {
    this.config = {
      enabled: config?.enabled === true,
      serverPath: config?.serverPath ?? 'mosh-server',
      herdrPath: config?.herdrPath ?? 'herdr',
      advertiseHost: String(config?.advertiseHost ?? '').trim(),
      bindAddress: String(config?.bindAddress ?? '').trim(),
      portRange: normalizePortRange(config?.portRange),
      predictionMode: ['adaptive', 'always', 'never'].includes(config?.predictionMode)
        ? config.predictionMode
        : 'adaptive',
      startupTimeoutMs: Number.isInteger(config?.startupTimeoutMs)
        ? Math.min(Math.max(config.startupTimeoutMs, 1000), 15_000)
        : 6000,
      networkTimeoutSeconds: Number.isInteger(config?.networkTimeoutSeconds)
        ? Math.min(Math.max(config.networkTimeoutSeconds, 60), 2_592_000)
        : 604_800,
      takeover: config?.takeover !== false,
    };
    this.monitor = monitor;
    this.audit = audit;
    this.serverPath = null;
    this.herdrPath = null;
    this.sessions = new Map();
  }

  async initialize() {
    this.serverPath = await resolveExecutable(this.config.serverPath);
    this.herdrPath = await resolveExecutable(this.config.herdrPath);
    return this.capabilities();
  }

  capabilities() {
    return publicCapabilities(this.config, this.serverPath, this.herdrPath);
  }

  async preflight() {
    if (!this.serverPath || !this.herdrPath) await this.initialize();
    const capabilities = this.capabilities();
    return [
      {
        name: 'mosh-server',
        label: 'Mosh server',
        path: this.serverPath ?? this.config.serverPath,
        ok: capabilities.serverAvailable,
        error: capabilities.serverAvailable ? null : 'mosh-server was not found or is not executable',
      },
      {
        name: 'herdr-cli',
        label: 'Herdr CLI',
        path: this.herdrPath ?? this.config.herdrPath,
        ok: capabilities.herdrAvailable,
        error: capabilities.herdrAvailable ? null : 'herdr was not found or is not executable',
      },
      {
        name: 'mosh-advertise-host',
        label: 'Mosh advertise host',
        path: this.config.advertiseHost || null,
        ok: Boolean(this.config.advertiseHost),
        error: this.config.advertiseHost ? null : 'Set mosh.advertiseHost to the Mac Tailscale IP or MagicDNS name',
      },
    ];
  }

  async createSession({ paneId, columns = 100, rows = 34, predictionMode }) {
    const capabilities = this.capabilities();
    if (!capabilities.enabled) {
      throw requestError(`Mosh is unavailable: ${capabilities.reason}`, 503, 'mosh_unavailable');
    }
    if (typeof paneId !== 'string' || paneId.length < 1 || paneId.length > 160) {
      throw requestError('paneId is required', 400, 'invalid_pane_id');
    }
    const snapshot = this.monitor.latest ?? await this.monitor.refresh();
    const pane = snapshot.panes?.find((candidate) => candidate.pane_id === paneId || candidate.paneId === paneId);
    if (!pane) throw requestError('The requested Herdr pane does not exist', 404, 'pane_not_found');

    const safeColumns = Math.min(Math.max(Number(columns) || 100, 20), 500);
    const safeRows = Math.min(Math.max(Number(rows) || 34, 6), 300);
    if (predictionMode !== undefined && !['adaptive', 'always', 'never'].includes(predictionMode)) {
      throw requestError('predictionMode must be adaptive, always, or never', 400, 'invalid_prediction_mode');
    }
    const effectivePredictionMode = predictionMode ?? this.config.predictionMode;
    const args = ['new', '-p', this.config.portRange, '-c', '256'];
    if (this.config.bindAddress) args.push('-i', this.config.bindAddress);
    args.push('--', this.herdrPath, 'agent', 'attach', paneId);
    if (this.config.takeover) args.push('--takeover');

    const env = {
      ...process.env,
      TERM: 'xterm-256color',
      COLORTERM: 'truecolor',
      LANG: process.env.LANG?.includes('UTF-8') ? process.env.LANG : 'en_US.UTF-8',
      LC_CTYPE: process.env.LC_CTYPE?.includes('UTF-8') ? process.env.LC_CTYPE : 'en_US.UTF-8',
      MOSH_SERVER_NETWORK_TMOUT: String(this.config.networkTimeoutSeconds),
      HERDDECK_INITIAL_COLUMNS: String(safeColumns),
      HERDDECK_INITIAL_ROWS: String(safeRows),
    };

    const result = await this.#spawnAndParse(args, env);
    const session = {
      id: randomUUID(),
      paneId,
      host: this.config.advertiseHost,
      port: result.port,
      key: result.key,
      predictionMode: effectivePredictionMode,
      createdAt: new Date().toISOString(),
      networkTimeoutSeconds: this.config.networkTimeoutSeconds,
      serverPid: result.serverPid,
    };
    this.sessions.set(session.id, { ...session, key: undefined });
    await this.audit.success('mosh.session.start', {
      sessionId: session.id,
      paneId,
      host: session.host,
      port: session.port,
      serverPid: session.serverPid,
    });
    return session;
  }

  async #spawnAndParse(args, env) {
    return new Promise((resolvePromise, rejectPromise) => {
      const child = spawn(this.serverPath, args, {
        env,
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
      });
      let combined = '';
      let settled = false;
      let serverPid = null;

      const finish = (error, value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        child.stdout?.removeAllListeners();
        child.stderr?.removeAllListeners();
        child.removeAllListeners();
        if (error) rejectPromise(error);
        else resolvePromise(value);
      };

      const inspect = (chunk) => {
        combined += chunk.toString('utf8');
        if (combined.length > 256 * 1024) combined = combined.slice(-128 * 1024);
        const detached = combined.match(DETACHED_PATTERN);
        if (detached) serverPid = Number(detached[1]);
        const connect = combined.match(CONNECT_PATTERN);
        if (connect) {
          finish(null, { port: Number(connect[1]), key: connect[2], serverPid });
        }
      };

      child.stdout?.on('data', inspect);
      child.stderr?.on('data', inspect);
      child.once('error', (error) => finish(requestError(error.message, 503, 'mosh_spawn_failed')));
      child.once('exit', (code, signal) => {
        const connect = combined.match(CONNECT_PATTERN);
        if (connect) {
          finish(null, { port: Number(connect[1]), key: connect[2], serverPid });
          return;
        }
        const detail = combined.trim().slice(-4000);
        finish(requestError(
          `mosh-server exited before publishing a session${detail ? `: ${detail}` : ''}`,
          503,
          'mosh_bootstrap_failed',
        ));
      });

      const timer = setTimeout(() => {
        child.kill('SIGTERM');
        finish(requestError('Timed out waiting for MOSH CONNECT', 504, 'mosh_bootstrap_timeout'));
      }, this.config.startupTimeoutMs);
      timer.unref?.();
    });
  }
}

export const __test = { normalizePortRange, CONNECT_PATTERN, DETACHED_PATTERN };