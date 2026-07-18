import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { expandTemplate } from './utils.mjs';

const DEFAULT_CONFIG_PATH = new URL('../config.json', import.meta.url);

function asInteger(value, fallback, minimum, maximum) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) return fallback;
  return parsed;
}

function validateProfile(profile) {
  const required = ['id', 'displayName', 'runtime', 'role', 'agmsgName', 'modelLabel', 'effortLabel'];
  for (const key of required) {
    if (typeof profile[key] !== 'string' || profile[key].trim() === '') {
      throw new Error(`Profile ${profile.id ?? '<unknown>'} is missing ${key}`);
    }
  }
  if (!Array.isArray(profile.argv) || profile.argv.length === 0 || profile.argv.some((x) => typeof x !== 'string')) {
    throw new Error(`Profile ${profile.id} must contain a non-empty string argv array`);
  }
  if (!['claude-code', 'codex', 'gemini', 'antigravity', 'copilot'].includes(profile.runtime)) {
    throw new Error(`Profile ${profile.id} has unsupported runtime ${profile.runtime}`);
  }
  if (!['orchestrator', 'executor'].includes(profile.role)) {
    throw new Error(`Profile ${profile.id} has unsupported role ${profile.role}`);
  }
  if (!/^[A-Za-z0-9._-]{1,80}$/.test(profile.agmsgName)) {
    throw new Error(`Profile ${profile.id} agmsgName must match [A-Za-z0-9._-] and be 1-80 characters`);
  }
  return {
    env: {},
    accent: 'neutral',
    ...profile,
  };
}

export async function loadConfig(path = process.env.HERDDECK_CONFIG) {
  const configPath = path ? resolve(path) : DEFAULT_CONFIG_PATH;
  let raw;
  try {
    raw = JSON.parse(await readFile(configPath, 'utf8'));
  } catch (error) {
    if (error?.code === 'ENOENT') {
      throw new Error(
        `Gateway config not found at ${configPath}. Copy config.example.json to config.json and edit projectRoots.`,
      );
    }
    throw error;
  }

  const expanded = expandTemplate(raw);
  const config = {
    bindHost: '127.0.0.1',
    port: 8787,
    allowedOrigins: [],
    projectRoots: [],
    snapshotPollMs: 5000,
    terminalReadLimit: 400,
    requestBodyLimitBytes: 262_144,
    rateLimit: { windowMs: 60_000, maxRequests: 240 },
    deliveryAssist: { enabled: true, pollMs: 1500, onlyWhenAgentNotWorking: false, inputDelayMs: 140 },
    mosh: {
      enabled: false,
      serverPath: 'mosh-server',
      herdrPath: 'herdr',
      advertiseHost: '',
      bindAddress: '',
      portRange: '60000:61000',
      predictionMode: 'adaptive',
      startupTimeoutMs: 6000,
      networkTimeoutSeconds: 604800,
      takeover: true,
    },
    profiles: [],
    ...expanded,
  };

  if (config.bindHost !== '127.0.0.1' && config.bindHost !== '::1') {
    throw new Error('bindHost must be loopback (127.0.0.1 or ::1). Use Tailscale Serve for tailnet access.');
  }
  config.port = asInteger(config.port, 8787, 1, 65535);
  config.snapshotPollMs = asInteger(config.snapshotPollMs, 5000, 1000, 60_000);
  config.terminalReadLimit = asInteger(config.terminalReadLimit, 400, 20, 1000);
  config.requestBodyLimitBytes = asInteger(config.requestBodyLimitBytes, 262_144, 4096, 2_097_152);
  config.rateLimit = {
    windowMs: asInteger(config.rateLimit?.windowMs, 60_000, 1000, 3_600_000),
    maxRequests: asInteger(config.rateLimit?.maxRequests, 240, 10, 100_000),
  };
  config.deliveryAssist = {
    enabled: config.deliveryAssist?.enabled !== false,
    pollMs: asInteger(config.deliveryAssist?.pollMs, 1500, 500, 60_000),
    onlyWhenAgentNotWorking: config.deliveryAssist?.onlyWhenAgentNotWorking === true,
    inputDelayMs: asInteger(config.deliveryAssist?.inputDelayMs, 140, 50, 2000),
  };
  config.mosh = {
    enabled: config.mosh?.enabled === true,
    serverPath: typeof config.mosh?.serverPath === 'string' && config.mosh.serverPath.trim()
      ? config.mosh.serverPath.trim()
      : 'mosh-server',
    herdrPath: typeof config.mosh?.herdrPath === 'string' && config.mosh.herdrPath.trim()
      ? config.mosh.herdrPath.trim()
      : 'herdr',
    advertiseHost: typeof config.mosh?.advertiseHost === 'string' ? config.mosh.advertiseHost.trim() : '',
    bindAddress: typeof config.mosh?.bindAddress === 'string' ? config.mosh.bindAddress.trim() : '',
    portRange: typeof config.mosh?.portRange === 'string' ? config.mosh.portRange.trim() : '60000:61000',
    predictionMode: ['adaptive', 'always', 'never'].includes(config.mosh?.predictionMode)
      ? config.mosh.predictionMode
      : 'adaptive',
    startupTimeoutMs: asInteger(config.mosh?.startupTimeoutMs, 6000, 1000, 15_000),
    networkTimeoutSeconds: asInteger(config.mosh?.networkTimeoutSeconds, 604800, 60, 2_592_000),
    takeover: config.mosh?.takeover !== false,
  };
  if (config.mosh.enabled && !config.mosh.advertiseHost) {
    throw new Error('mosh.advertiseHost is required when Mosh is enabled; use the Mac Tailscale IP or MagicDNS name');
  }
  if (!Array.isArray(config.projectRoots) || config.projectRoots.length === 0) {
    throw new Error('projectRoots must contain at least one allowed project directory');
  }
  config.projectRoots = config.projectRoots.map((entry) => resolve(entry));
  config.allowedOrigins = Array.isArray(config.allowedOrigins) ? config.allowedOrigins : [];
  if (!Array.isArray(config.profiles)) throw new Error('profiles must be an array');
  config.profiles = config.profiles.map(validateProfile);
  if (config.profiles.length === 0) throw new Error('At least one agent profile is required');
  const profileIds = new Set();
  const agmsgNames = new Set();
  for (const profile of config.profiles) {
    if (profileIds.has(profile.id)) throw new Error(`Duplicate profile id: ${profile.id}`);
    if (agmsgNames.has(profile.agmsgName)) throw new Error(`Duplicate profile agmsgName: ${profile.agmsgName}`);
    profileIds.add(profile.id);
    agmsgNames.add(profile.agmsgName);
  }

  for (const key of ['herdrSocket', 'tokenFile', 'auditLog', 'missionStore', 'agmsgRoot']) {
    if (typeof config[key] !== 'string' || config[key] === '') throw new Error(`Missing ${key}`);
    config[key] = resolve(config[key]);
  }

  return { config, configPath: String(configPath) };
}
