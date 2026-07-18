import { appendFile } from 'node:fs/promises';
import { ensureParent, normalizeError } from './utils.mjs';

export class AuditLog {
  constructor(path) {
    this.path = path;
  }

  async write(event, fields = {}) {
    await ensureParent(this.path);
    const record = {
      at: new Date().toISOString(),
      event,
      ...fields,
    };
    await appendFile(this.path, `${JSON.stringify(record)}\n`, { mode: 0o600 });
  }

  async success(event, fields = {}) {
    return this.write(event, { outcome: 'success', ...fields });
  }

  async failure(event, error, fields = {}) {
    return this.write(event, { outcome: 'failure', error: normalizeError(error), ...fields });
  }
}
