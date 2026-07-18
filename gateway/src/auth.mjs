import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { chmod, readFile, writeFile } from 'node:fs/promises';
import { ensureParent } from './utils.mjs';

export async function loadOrCreateToken(path) {
  try {
    const token = (await readFile(path, 'utf8')).trim();
    if (token.length < 32) throw new Error(`Token at ${path} is too short`);
    return token;
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
    const token = randomBytes(32).toString('base64url');
    await ensureParent(path);
    await writeFile(path, `${token}\n`, { mode: 0o600, flag: 'wx' });
    await chmod(path, 0o600);
    return token;
  }
}

export function tokenFingerprint(token) {
  return createHash('sha256').update(token).digest('hex').slice(0, 12);
}

export function bearerToken(request) {
  const header = request.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) return null;
  return header.slice('Bearer '.length).trim();
}

export function constantTimeEqual(expected, actual) {
  if (typeof actual !== 'string') return false;
  const left = Buffer.from(expected);
  const right = Buffer.from(actual);
  if (left.length !== right.length) return false;
  return timingSafeEqual(left, right);
}

export function authorize(request, expectedToken) {
  return constantTimeEqual(expectedToken, bearerToken(request));
}

export class SlidingWindowRateLimiter {
  constructor({ windowMs, maxRequests }) {
    this.windowMs = windowMs;
    this.maxRequests = maxRequests;
    this.entries = new Map();
  }

  allow(key, now = Date.now()) {
    const floor = now - this.windowMs;
    const samples = (this.entries.get(key) ?? []).filter((timestamp) => timestamp >= floor);
    if (samples.length >= this.maxRequests) {
      this.entries.set(key, samples);
      return false;
    }
    samples.push(now);
    this.entries.set(key, samples);
    if (this.entries.size > 2048) this.prune(now);
    return true;
  }

  prune(now = Date.now()) {
    const floor = now - this.windowMs;
    for (const [key, samples] of this.entries) {
      const active = samples.filter((timestamp) => timestamp >= floor);
      if (active.length === 0) this.entries.delete(key);
      else this.entries.set(key, active);
    }
  }
}
