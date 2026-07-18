import { execFile } from 'node:child_process';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { promisify } from 'node:util';

const execFilePromise = promisify(execFile);

export function expandTemplate(value, env = process.env) {
  if (typeof value === 'string') {
    return value.replace(/\$\{([A-Z_][A-Z0-9_]*)\}/gi, (_match, name) => env[name] ?? '');
  }
  if (Array.isArray(value)) {
    return value.map((entry) => expandTemplate(entry, env));
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, expandTemplate(entry, env)]),
    );
  }
  return value;
}

export async function readJson(path, fallback = undefined, onCorrupt = undefined) {
  try {
    return JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    if (fallback !== undefined && error?.code === 'ENOENT') return fallback;
    if (fallback !== undefined && error instanceof SyntaxError) {
      const corruptPath = `${path}.corrupt-${Date.now()}`;
      await rename(path, corruptPath);
      await onCorrupt?.(error, corruptPath);
      return fallback;
    }
    throw error;
  }
}

export async function writeJsonAtomic(path, value, mode = 0o600) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const tempPath = `${path}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(tempPath, `${JSON.stringify(value, null, 2)}\n`, { mode });
  await rename(tempPath, path);
}

export async function ensureParent(path) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
}

export async function runFile(file, args = [], options = {}) {
  const {
    cwd,
    env = process.env,
    timeout = 30_000,
    maxBuffer = 4 * 1024 * 1024,
  } = options;
  try {
    const result = await execFilePromise(file, args, {
      cwd,
      env,
      timeout,
      maxBuffer,
      encoding: 'utf8',
      windowsHide: true,
    });
    return {
      stdout: result.stdout ?? '',
      stderr: result.stderr ?? '',
      exitCode: 0,
    };
  } catch (error) {
    const message = error?.stderr?.trim() || error?.message || `Failed to run ${file}`;
    const wrapped = new Error(message, { cause: error });
    wrapped.code = error?.code;
    wrapped.stdout = error?.stdout ?? '';
    wrapped.stderr = error?.stderr ?? '';
    wrapped.exitCode = Number.isInteger(error?.code) ? error.code : undefined;
    throw wrapped;
  }
}

export function parseJsonLines(text) {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        throw new Error(`Invalid JSONL record at line ${index + 1}: ${error.message}`);
      }
    });
}

export function sleep(ms) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}

export function isPathAllowed(candidate, roots) {
  const absoluteCandidate = resolve(candidate);
  return roots.some((root) => {
    const absoluteRoot = resolve(root);
    const rel = relative(absoluteRoot, absoluteCandidate);
    return rel === '' || (!rel.startsWith('..') && !isAbsolute(rel));
  });
}

export function requestError(message, statusCode = 400, code = 'invalid_request') {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

export function assertIdentifier(value, label = 'identifier') {
  if (typeof value !== 'string' || !/^[A-Za-z0-9._-]{1,80}$/.test(value)) {
    throw requestError(`${label} must match [A-Za-z0-9._-] and be 1-80 characters`);
  }
  return value;
}

export function slug(value, fallback = 'mission') {
  const normalized = String(value ?? '')
    .normalize('NFKD')
    .replace(/[^A-Za-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase()
    .slice(0, 36);
  return normalized || fallback;
}

export function shortId(id) {
  return String(id).replace(/-/g, '').slice(0, 8);
}

export function safeJson(value) {
  return JSON.parse(JSON.stringify(value));
}

export function normalizeError(error) {
  return {
    name: error?.name ?? 'Error',
    message: error?.message ?? String(error),
    code: error?.code,
  };
}
