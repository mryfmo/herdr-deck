import net from 'node:net';
import { randomUUID } from 'node:crypto';
import { EventEmitter } from 'node:events';

export class HerdrRpcError extends Error {
  constructor(code, message, requestId) {
    super(message);
    this.name = 'HerdrRpcError';
    this.code = code;
    this.requestId = requestId;
  }
}

export class HerdrClient {
  constructor({ socketPath, timeoutMs = 10_000 }) {
    this.socketPath = socketPath;
    this.timeoutMs = timeoutMs;
  }

  rpc(method, params = {}, timeoutMs = this.timeoutMs) {
    const id = randomUUID();
    const request = JSON.stringify({ id, method, params });

    return new Promise((resolve, reject) => {
      let buffer = '';
      let settled = false;
      const socket = net.createConnection({ path: this.socketPath });
      const timer = setTimeout(() => {
        finish(new Error(`Herdr RPC ${method} timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      const finish = (error, value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        socket.destroy();
        if (error) reject(error);
        else resolve(value);
      };

      socket.setEncoding('utf8');
      socket.on('connect', () => socket.write(`${request}\n`));
      socket.on('data', (chunk) => {
        buffer += chunk;
        while (buffer.includes('\n')) {
          const newline = buffer.indexOf('\n');
          const line = buffer.slice(0, newline).trim();
          buffer = buffer.slice(newline + 1);
          if (!line) continue;
          let message;
          try {
            message = JSON.parse(line);
          } catch (error) {
            finish(new Error(`Herdr returned malformed JSON: ${error.message}`));
            return;
          }
          if (message.id !== id) continue;
          if (message.error) {
            finish(new HerdrRpcError(message.error.code, message.error.message, id));
            return;
          }
          finish(null, message.result);
          return;
        }
      });
      socket.on('error', (error) => finish(error));
      socket.on('end', () => {
        if (!settled) finish(new Error(`Herdr closed the socket before replying to ${method}`));
      });
    });
  }

  async ping() {
    return this.rpc('ping', {});
  }

  async snapshot() {
    const result = await this.rpc('session.snapshot', {});
    if (result?.type !== 'session_snapshot' || !result.snapshot) {
      throw new Error(`Unexpected session.snapshot response: ${JSON.stringify(result)}`);
    }
    return result.snapshot;
  }

  async readPane(paneId, options = {}) {
    const result = await this.rpc('pane.read', {
      pane_id: paneId,
      source: options.source ?? 'visible',
      lines: options.lines,
      format: options.format ?? 'text',
      strip_ansi: options.stripAnsi ?? true,
    });
    if (result?.type !== 'pane_read' || !result.read) {
      throw new Error(`Unexpected pane.read response: ${JSON.stringify(result)}`);
    }
    return result.read;
  }

  async sendText(paneId, text) {
    return this.rpc('pane.send_text', { pane_id: paneId, text });
  }

  async sendKeys(paneId, keys) {
    return this.rpc('pane.send_keys', { pane_id: paneId, keys });
  }

  async sendInput(paneId, text = '', keys = []) {
    return this.rpc('pane.send_input', { pane_id: paneId, text, keys });
  }

  async startAgent(params) {
    const result = await this.rpc('agent.start', params, 30_000);
    if (result?.type !== 'agent_started' || !result.agent) {
      throw new Error(`Unexpected agent.start response: ${JSON.stringify(result)}`);
    }
    return result;
  }

  async sendAgent(target, text) {
    return this.rpc('agent.send', { target, text });
  }

  subscribe(subscriptions, handlers = {}) {
    if (!Array.isArray(subscriptions) || subscriptions.length === 0) {
      throw new Error('Herdr event subscription requires at least one subscription');
    }

    const id = randomUUID();
    const request = JSON.stringify({
      id,
      method: 'events.subscribe',
      params: { subscriptions },
    });
    const socket = net.createConnection({ path: this.socketPath });
    let buffer = '';
    let acknowledged = false;
    let intentionalClose = false;
    let settled = false;
    let resolveReady;
    let rejectReady;

    const ready = new Promise((resolve, reject) => {
      resolveReady = resolve;
      rejectReady = reject;
    });
    const timer = setTimeout(() => {
      const error = new Error(`Herdr events.subscribe timed out after ${this.timeoutMs}ms`);
      if (!settled) {
        settled = true;
        rejectReady(error);
      }
      handlers.onError?.(error);
      socket.destroy();
    }, this.timeoutMs);

    const fail = (error) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        rejectReady(error);
      }
      if (!intentionalClose) handlers.onError?.(error);
    };

    socket.setEncoding('utf8');
    socket.on('connect', () => socket.write(`${request}\n`));
    socket.on('data', (chunk) => {
      buffer += chunk;
      while (buffer.includes('\n')) {
        const newline = buffer.indexOf('\n');
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (!line) continue;

        let message;
        try {
          message = JSON.parse(line);
        } catch (error) {
          fail(new Error(`Herdr event stream returned malformed JSON: ${error.message}`));
          socket.destroy();
          return;
        }

        if (message.id === id) {
          if (message.error) {
            fail(new HerdrRpcError(message.error.code, message.error.message, id));
            socket.destroy();
            return;
          }
          if (!acknowledged) {
            acknowledged = true;
            if (!settled) {
              settled = true;
              clearTimeout(timer);
              resolveReady(message.result);
            }
            handlers.onReady?.(message.result);
          }
          continue;
        }

        if (message.event) handlers.onEvent?.(message);
        else handlers.onMessage?.(message);
      }
    });
    socket.on('error', fail);
    socket.on('close', () => {
      clearTimeout(timer);
      if (!settled && !intentionalClose) {
        const error = new Error('Herdr closed the event subscription before acknowledging it');
        settled = true;
        rejectReady(error);
      }
      handlers.onClose?.({ intentional: intentionalClose, acknowledged });
    });

    return {
      id,
      ready,
      close() {
        intentionalClose = true;
        clearTimeout(timer);
        socket.destroy();
      },
    };
  }
}

function snapshotFingerprint(snapshot) {
  if (!snapshot) return '';
  // Terminal output mutates pane.scroll and pane/agent revision; neither changes
  // the topology or agent state represented by a snapshot notification.
  const panes = snapshot.panes?.map(({ scroll: _scroll, revision: _revision, ...pane }) => pane);
  const agents = snapshot.agents?.map(({ revision: _revision, ...agent }) => agent);
  const compact = {
    version: snapshot.version,
    protocol: snapshot.protocol,
    focused_workspace_id: snapshot.focused_workspace_id,
    focused_tab_id: snapshot.focused_tab_id,
    focused_pane_id: snapshot.focused_pane_id,
    workspaces: snapshot.workspaces,
    tabs: snapshot.tabs,
    panes,
    layouts: snapshot.layouts,
    agents,
  };
  return JSON.stringify(compact);
}

const LIFECYCLE_SUBSCRIPTIONS = [
  'workspace.created',
  'workspace.updated',
  'workspace.renamed',
  'workspace.moved',
  'workspace.closed',
  'workspace.focused',
  'worktree.created',
  'worktree.opened',
  'worktree.removed',
  'tab.created',
  'tab.closed',
  'tab.focused',
  'tab.renamed',
  'tab.moved',
  'pane.created',
  'pane.closed',
  'pane.focused',
  'pane.moved',
  'pane.exited',
  'pane.agent_detected',
  'layout.updated',
];

const TOPOLOGY_EVENTS = new Set([
  'workspace_created',
  'workspace_closed',
  'tab_created',
  'tab_closed',
  'pane_created',
  'pane_closed',
  'pane_moved',
  'pane_exited',
  'pane_agent_detected',
  'workspace.created',
  'workspace.closed',
  'tab.created',
  'tab.closed',
  'pane.created',
  'pane.closed',
  'pane.moved',
  'pane.exited',
  'pane.agent_detected',
]);

function subscriptionsForSnapshot(snapshot) {
  const subscriptions = LIFECYCLE_SUBSCRIPTIONS.map((type) => ({ type }));
  const paneIds = new Set([
    ...(snapshot?.panes ?? []).map((pane) => pane.pane_id),
    ...(snapshot?.agents ?? []).map((agent) => agent.pane_id),
  ].filter(Boolean));
  for (const paneId of paneIds) {
    subscriptions.push({ type: 'pane.agent_status_changed', pane_id: paneId });
  }
  return subscriptions;
}

export class SnapshotMonitor extends EventEmitter {
  constructor(client, fallbackPollMs = 5000) {
    super();
    this.client = client;
    this.fallbackPollMs = fallbackPollMs;
    this.timer = null;
    this.debounceTimer = null;
    this.reconnectTimer = null;
    this.subscription = null;
    this.subscriptionGeneration = 0;
    this.running = false;
    this.refreshPromise = null;
    this.latest = null;
    this.updatedAt = null;
    this.fingerprint = '';
    this.lastError = null;
    this.lastWarning = null;
    this.resubscribeAfterRefresh = false;
  }

  async refresh({ force = false } = {}) {
    if (this.refreshPromise) return this.refreshPromise;
    this.refreshPromise = (async () => {
      try {
        const snapshot = await this.client.snapshot();
        const fingerprint = snapshotFingerprint(snapshot);
        const changed = force || fingerprint !== this.fingerprint;
        this.latest = snapshot;
        this.updatedAt = new Date().toISOString();
        this.fingerprint = fingerprint;
        this.lastError = null;
        if (changed) this.emit('snapshot', snapshot);
        return snapshot;
      } catch (error) {
        const key = `${error.code ?? ''}:${error.message}`;
        if (key !== this.lastError) {
          this.lastError = key;
          this.emit('error', error);
        }
        throw error;
      } finally {
        this.refreshPromise = null;
      }
    })();
    return this.refreshPromise;
  }

  warn(error) {
    const key = `${error.code ?? ''}:${error.message}`;
    if (key === this.lastWarning) return;
    this.lastWarning = key;
    this.emit('warning', error);
  }

  scheduleRefresh({ resubscribe = false } = {}) {
    this.resubscribeAfterRefresh ||= resubscribe;
    if (this.debounceTimer) return;
    this.debounceTimer = setTimeout(async () => {
      this.debounceTimer = null;
      const shouldResubscribe = this.resubscribeAfterRefresh;
      this.resubscribeAfterRefresh = false;
      try {
        await this.refresh();
        if (shouldResubscribe) this.openSubscription();
      } catch {
        // The fallback timer and subscription reconnect path keep retrying.
      }
    }, 45);
    this.debounceTimer.unref?.();
  }

  handleEvent(event) {
    this.emit('herdr-event', event);
    this.scheduleRefresh({ resubscribe: TOPOLOGY_EVENTS.has(event.event) });
  }

  scheduleSubscriptionReconnect() {
    if (!this.running || this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.openSubscription();
    }, Math.min(this.fallbackPollMs, 1500));
    this.reconnectTimer.unref?.();
  }

  openSubscription() {
    if (!this.running || !this.latest) return;
    this.subscription?.close();
    this.subscription = null;
    const generation = ++this.subscriptionGeneration;
    const subscription = this.client.subscribe(subscriptionsForSnapshot(this.latest), {
      onEvent: (event) => {
        if (generation === this.subscriptionGeneration) this.handleEvent(event);
      },
      onError: (error) => {
        if (generation !== this.subscriptionGeneration || !this.running) return;
        this.warn(new Error(`Herdr event subscription unavailable; using snapshot fallback: ${error.message}`));
      },
      onClose: ({ intentional }) => {
        if (generation !== this.subscriptionGeneration || intentional || !this.running) return;
        this.subscription = null;
        this.scheduleSubscriptionReconnect();
      },
    });
    this.subscription = subscription;
    void subscription.ready.then(() => {
      if (generation === this.subscriptionGeneration) {
        this.lastWarning = null;
        this.emit('subscription-ready');
      }
    }).catch((error) => {
      if (generation !== this.subscriptionGeneration || !this.running) return;
      this.warn(new Error(`Herdr event subscription failed; using snapshot fallback: ${error.message}`));
      this.scheduleSubscriptionReconnect();
    });
  }

  scheduleFallback() {
    if (!this.running) return;
    this.timer = setTimeout(async () => {
      if (!this.running) return;
      try {
        await this.refresh();
        if (!this.subscription) this.openSubscription();
      } catch {
        // Error is emitted and retried on the next fallback tick.
      }
      this.scheduleFallback();
    }, this.fallbackPollMs);
    this.timer.unref?.();
  }

  start() {
    if (this.running) return;
    this.running = true;
    void (async () => {
      try {
        await this.refresh({ force: true });
        this.openSubscription();
      } catch {
        // The fallback poll will continue attempting to bootstrap.
      }
      this.scheduleFallback();
    })();
  }

  stop() {
    this.running = false;
    if (this.timer) clearTimeout(this.timer);
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.subscriptionGeneration += 1;
    this.subscription?.close();
    this.subscription = null;
    this.timer = null;
    this.debounceTimer = null;
    this.reconnectTimer = null;
  }
}
