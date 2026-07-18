import { access, constants } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertIdentifier, parseJsonLines, requestError, runFile } from './utils.mjs';

const AGMSG_API = fileURLToPath(new URL('../scripts/agmsg-api.sh', import.meta.url));

export class AgmsgClient {
  constructor({ root, timeoutMs = 30_000 }) {
    this.root = root;
    this.scripts = join(root, 'scripts');
    this.timeoutMs = timeoutMs;
  }

  script(name) {
    return join(this.scripts, name);
  }

  async preflight() {
    const required = [
      ...['send.sh', 'join.sh', 'delivery.sh'].map((name) => ({ name, path: this.script(name) })),
      { name: 'agmsg-api.sh', path: AGMSG_API },
    ];
    const checks = [];
    for (const { name, path } of required) {
      try {
        await access(path, constants.R_OK | constants.X_OK);
        checks.push({ name, path, ok: true });
      } catch (error) {
        checks.push({ name, path, ok: false, error: error.message });
      }
    }
    return checks;
  }

  async run(name, args) {
    return runFile(this.script(name), args, { timeout: this.timeoutMs });
  }

  async read(args) {
    return runFile(AGMSG_API, args, {
      timeout: this.timeoutMs,
      env: { ...process.env, AGMSG_ROOT: this.root },
    });
  }

  async teams() {
    const { stdout } = await this.read(['get', 'teams']);
    return stdout
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        try {
          const value = JSON.parse(line);
          if (typeof value === 'string') return value;
          if (value && typeof value.name === 'string') return value.name;
        } catch {
          // agmsg versions before the uniform JSONL API returned plain team names.
        }
        return line;
      });
  }

  async members(team) {
    assertIdentifier(team, 'team');
    const { stdout } = await this.read(['get', 'teams', team, 'members']);
    return parseJsonLines(stdout);
  }

  async messages(team, { agent, limit = 50, beforeId } = {}) {
    assertIdentifier(team, 'team');
    const args = ['get', 'teams', team, 'messages', '--limit', String(Math.min(Math.max(limit, 1), 500))];
    if (agent) {
      assertIdentifier(agent, 'agent');
      args.push('--agent', agent);
    }
    if (beforeId !== undefined) args.push('--before-id', String(beforeId));
    const { stdout } = await this.read(args);
    return parseJsonLines(stdout);
  }

  async send({ team, from, to, body }) {
    assertIdentifier(team, 'team');
    assertIdentifier(from, 'from agent');
    assertIdentifier(to, 'to agent');
    if (typeof body !== 'string' || body.trim() === '') throw requestError('message body must not be empty');
    if (Buffer.byteLength(body, 'utf8') > 32_768) {
      throw requestError('message body exceeds 32 KiB', 413, 'message_too_large');
    }
    await this.run('send.sh', [team, from, to, body]);
    return { ok: true };
  }

  async join({ team, name, type, project }) {
    assertIdentifier(team, 'team');
    assertIdentifier(name, 'agent');
    if (!['claude-code', 'codex', 'gemini', 'antigravity', 'copilot'].includes(type)) {
      throw new Error(`Unsupported agmsg agent type: ${type}`);
    }
    await this.run('join.sh', [team, name, type, project]);
    return { ok: true };
  }
}
