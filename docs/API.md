# Gateway API

Base URL:

```text
https://<mac-magicdns-name>
```

認証:

```http
Authorization: Bearer <token>
```

すべての `/v1/*` endpoint は認証必須です。`/healthz` だけは process liveness 用に unauthenticated です。Gateway 自体は loopback にしか bind しません。

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/healthz` | Gateway process liveness |
| GET | `/v1/health` | Gateway / Herdr / AGMSG diagnostics |
| GET | `/v1/mosh/capabilities` | Mosh server/client bootstrap capability |
| POST | `/v1/mosh/sessions` | create a short-lived Mosh descriptor for a Herdr pane |
| GET | `/v1/profiles` | reusable launch profiles |
| POST | `/v1/profiles/start` | start an agent from an allowlisted profile |
| GET | `/v1/herdr/snapshot` | full Herdr snapshot |
| GET | `/v1/herdr/panes/:id/read` | read visible/recent pane output |
| POST | `/v1/herdr/panes/:id/input` | send text and/or special keys |
| POST | `/v1/herdr/rpc` | call a restricted Herdr method |
| GET | `/v1/events` | SSE stream |
| GET | `/v1/agmsg/teams` | list teams |
| GET | `/v1/agmsg/teams/:team/members` | list team members |
| GET | `/v1/agmsg/teams/:team/messages` | message history/inbox |
| POST | `/v1/agmsg/messages` | send an AGMSG message |
| GET | `/v1/missions` | list missions |
| POST | `/v1/missions` | start mission |
| GET | `/v1/missions/:id` | mission details |

## Examples

### Health

```bash
TOKEN="$(cat ~/.config/herddeck/token)"
curl -sS \
  -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8787/v1/health
```

### Start reusable profile

```json
POST /v1/profiles/start
{
  "profileId": "codex-sol-executor",
  "projectPath": "/Users/me/Developer/project",
  "name": "reviewer",
  "prompt": "Review the current diff and run focused tests.",
  "split": "right",
  "focus": true
}
```

App-authored request objects such as profile, mission, Mosh, and terminal input use camelCase JSON. Herdr snapshot/read/RPC responses and snapshot SSE payloads preserve Herdr's snake_case fields; the iOS decoder absorbs those fields with `convertFromSnakeCase`.

### Read terminal

```http
GET /v1/herdr/panes/<pane-id>/read?source=visible&lines=400&format=text
```

`format=ansi` は Terminal mode、`format=text` は Rich / Raw で使用します。

### Mosh capability

```http
GET /v1/mosh/capabilities
```

```json
{
  "mosh": {
    "enabled": true,
    "configured": true,
    "embeddedClientRequired": true,
    "advertiseHost": "100.64.0.10",
    "portRange": "60000:61000",
    "predictionMode": "adaptive",
    "serverAvailable": true,
    "herdrAvailable": true,
    "reason": null
  }
}
```

### Create Mosh terminal session

```json
POST /v1/mosh/sessions
{
  "paneId": "w1:p2",
  "columns": 100,
  "rows": 34,
  "predictionMode": "adaptive"
}
```

Success response is `201` with `host`, `port`, and a Mosh session `key`. The response is `Cache-Control: no-store`. The key is deliberately absent from audit logs and Gateway persisted state.

Validation:

- pane must exist in the current Herdr snapshot
- columns: clamped to 20...500
- rows: clamped to 6...300
- prediction mode: `adaptive`, `always`, or `never`
- server / Herdr executable and advertise host must pass capability checks

`columns` / `rows` are advisory bootstrap dimensions. They seed the attached client environment but do not synchronously resize an already-running Herdr pane; subsequent embedded-Mosh resize events update the Mosh window size.

### Send terminal input

```json
POST /v1/herdr/panes/<pane-id>/input
{
  "text": "Please run the failing test again.",
  "keys": ["enter"]
}
```

Special-key-only example:

```json
{
  "text": "",
  "keys": ["ctrl+c"]
}
```

### Start mission

```json
POST /v1/missions
{
  "title": "Implement offline sync",
  "goal": "Implement the feature, add tests, review the diff, and produce a concise handoff.",
  "projectPath": "/Users/me/Developer/app",
  "team": "app-sync",
  "maxRounds": 8,
  "orchestratorProfileId": "claude-fable-orchestrator",
  "executorProfileIds": ["codex-sol-executor"],
  "deliveryAssist": true
}
```

## SSE events

`GET /v1/events` returns `text/event-stream`.

| Event | Data |
|---|---|
| `hello` | request ID and timestamp |
| `snapshot` | Herdr snapshot with snake_case fields preserved |
| `mission` | updated mission record |
| `agmsg` | team and timestamp hint |
| `herdr-event` | raw Herdr event envelope for diagnostics |
| `gateway-warning` | recoverable subscription warning |
| `gateway-error` | Herdr/Gateway error |

The client treats SSE as an invalidation/update stream and may refetch REST resources. It must not assume every event is delivered exactly once.

## Mobile RPC allowlist

Allowed groups include:

- `ping`
- `session.snapshot`
- `workspace.list/get/focus/rename`
- `tab.list/get/focus/rename`
- `pane.list/get/current/rename/read/zoom/layout/focus_direction/resize`
- `agent.list/get/read/explain/focus/rename`

Terminal writes use the dedicated, size-limited `/v1/herdr/panes/:id/input` endpoint. Creation, lifecycle, and raw-send operations used by MissionOrchestrator are internal Gateway calls and are not exposed through the generic mobile RPC endpoint.

## Limits

- JSON body: default 256 KiB
- terminal text input: 64 KiB
- Mosh bootstrap output: bounded to 256 KiB while parsing `MOSH CONNECT`
- Mosh startup timeout: config 1...15 seconds
- AGMSG body: 32 KiB
- terminal read: max 1000 lines, config default 400
- messages: max 500 records
- special keys per request: max 32
- each special-key string: 1-64 characters
- rate limit: default 240 requests / 60 seconds per source address

## Error responses

Error envelopes always contain a string `error.code`.

| Status | Meaning |
|---|---|
| 400 | invalid JSON/object body or Herdr `invalid_*` request |
| 401 | missing or invalid bearer token |
| 403 | denied origin, project, or RPC method |
| 404 | route/resource or Herdr `not_found` / `*_not_found` |
| 413 | request, terminal input, or message too large |
| 429 | source-address rate limit exceeded |
| 502 | other Herdr RPC failure |
| 503 | required local service unavailable |
