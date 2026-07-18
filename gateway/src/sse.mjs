export class SseHub {
  constructor() {
    this.clients = new Set();
    this.keepAlive = setInterval(() => this.comment('keepalive'), 15_000);
    this.keepAlive.unref?.();
  }

  add(response) {
    response.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    response.write('retry: 1500\n\n');
    this.clients.add(response);
    const remove = () => this.clients.delete(response);
    response.on('close', remove);
    response.on('error', remove);
    return remove;
  }

  publish(event, data) {
    const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
    for (const response of this.clients) {
      try {
        response.write(payload);
      } catch {
        this.clients.delete(response);
      }
    }
  }

  send(response, event, data) {
    if (!this.clients.has(response)) return false;
    try {
      response.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      return true;
    } catch {
      this.clients.delete(response);
      return false;
    }
  }

  comment(text) {
    for (const response of this.clients) {
      try {
        response.write(`: ${text}\n\n`);
      } catch {
        this.clients.delete(response);
      }
    }
  }

  close() {
    clearInterval(this.keepAlive);
    for (const response of this.clients) response.end();
    this.clients.clear();
  }
}
