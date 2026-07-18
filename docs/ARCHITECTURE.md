# HerdDeck Architecture

## 1. 設計目標

HerdDeck は次の責務を分離します。

- **Mac:** shell、PTY、Git、ファイル、Claude Code、Codex、Herdr、AGMSG を実行する trusted execution host
- **iPhone:** 状態監視、指示、承認、ターミナル入力、ミッション管理を行う thin client
- **Tailscale:** 公開インターネットを使わず、端末間の暗号化された到達性を提供

iOS 上で Herdr や coding agent 本体を動かす構成にはしていません。長時間実行、PTY、リポジトリ、credential、バックグラウンド制約を Mac 側へ集約します。

## 2. コンポーネント

### HerdDeck iOS

SwiftUI のネイティブアプリです。

- `AppState`: 接続状態、snapshot、profiles、missions、AGMSG state の単一ストア
- `GatewayClient`: HTTPS REST と SSE
- `NetworkPathService`: Wi-Fi / cellular / constrained path の監視
- `HerdOverviewView`: agent state と reusable profiles
- `TerminalConsoleView`: Rich / Terminal / Raw、transport routing、composer、special-key rail
- `TerminalEmulatorView`: SwiftTerm VT100/Xterm renderer
- `MoshSessionController`: embedded Mosh lifecycle と retry
- `MissionsView`: orchestration lifecycle
- `MessagesView`: AGMSG timeline と送信
- `OnboardingView`: pairing、HTTPS 検証、token 保存、biometric 設定

### HerdDeck Gateway

Node.js 22 標準ライブラリだけで動作する loopback-only service です。

- HTTP/JSON API
- SSE event fan-out
- Herdr Unix socket client
- AGMSG script adapter
- Mosh session broker
- mission orchestrator
- delivery assist
- mission store
- append-only audit log
- bearer authentication と rate limit

外部 npm package を使わないため、Mac 側の supply-chain surface を小さくしています。

### Herdr adapter

Herdr の Unix domain socket に newline-delimited JSON を送ります。

起動シーケンス:

1. `session.snapshot` で完全状態を取得
2. `events.subscribe` を長時間接続で開始
3. lifecycle event または `pane.agent_status_changed` を受信
4. 45 ms debounce 後に snapshot を再取得
5. topology 変更時は pane filter を再構成して再購読
6. subscription が利用できない場合は 5 秒ごとに snapshot を再取得

iOS へ Herdr の内部イベントをそのまま state source として渡さず、Gateway で再同期済み snapshot に変換します。これによりイベント欠落、順序の入れ替わり、クライアント再接続に耐えます。

### AGMSG adapter

Gateway の JavaScript process は AGMSG の SQLite DB や team config を直接読み書きしません。読み取りは repository 内の read-only adapter `gateway/scripts/agmsg-api.sh` が SQLite と team config を参照し、JSONL を返します。

読み取り:

```text
gateway/scripts/agmsg-api.sh get teams
gateway/scripts/agmsg-api.sh get teams <team> members
gateway/scripts/agmsg-api.sh get teams <team> messages ...
```

書き込み:

```text
send.sh
join.sh
delivery.sh
```

メッセージ ID は数値として仮定せず、opaque string として処理します。現行 JSONL と旧版の team 出力にも対応します。

## 3. データフロー

```text
Herdr server ── Unix socket / NDJSON ── SnapshotMonitor ──┐
                                                         │
AGMSG scripts ── JSONL ── MissionOrchestrator ───────────┤
                                                         ▼
                                                   HTTPS / SSE
                                                         │
                                                         ▼
                                                    iOS AppState

Interactive Terminal only:
iOS ── HTTPS bootstrap ── Gateway ── mosh-server ──┐
  └──────────────── Mosh UDP over Tailscale ──────┘
                           │
                           ▼
                  herdr agent attach <pane>
```

### Terminal transport

- Rich / Raw は常に `pane.read` over HTTPS
- Wi-Fi の Terminal は `pane.read?format=ansi` + `pane.send_input`
- cellular の Terminal は設定により embedded Mosh
- Gateway は `mosh-server new ... -- herdr agent attach <pane> --takeover` を起動
- Mosh key は response にだけ含め、Gateway state / audit には保持しない
- Wi-Fi 復帰時は hysteresis を置き、短時間の interface flap で再接続を繰り返さない
- Mosh unavailable / disabled の場合は Gateway terminal へ fallback

### Rendering

- Rich: `recent_unwrapped` textを block parser + `AttributedString` で表示
- Terminal: SwiftTermへ ANSI / Mosh byte streamをfeed
- Raw: `recent` plain textを無解釈で表示
- rendering mode と transport route は独立。Mosh は Rich renderer を置き換えない
- terminal body は audit log に記録せず、byte count と key metadata のみ記録

### Agent reuse

`POST /v1/profiles/start` は config の immutable profile とユーザー指定の project path / prompt を組み合わせ、Herdr `agent.start` を呼びます。iOS は CLI command を自由入力しないため、実行可能ファイルと安全設定の authority は Mac 側 config にあります。

Mission では profile の `agmsgName` を identity の**基底名**として扱い、`<base>-<mission-short-id>[-<ordinal>]` へ展開します。これにより同じ profile を別 Mission で再利用しても AGMSG の role exclusivity と衝突せず、Herdr pane、AGMSG identity、永続メッセージ履歴を Mission 単位で追跡できます。

## 4. Mission lifecycle

```text
starting
  ├─ validate project root
  ├─ join AGMSG identities
  ├─ create Herdr workspace
  ├─ start orchestrator
  ├─ start executor(s)
  └─ close bootstrap shell pane
       ▼
running
  ├─ AGMSG handoffs
  ├─ delivery assist
  ├─ Herdr state updates
  └─ explicit MISSION_DONE signal
       ▼
completed
```

起動途中で失敗した場合、専用 Herdr workspace を best-effort で閉じ、Mission を `failed` にします。

完了は次の優先順位で判定します。

1. orchestrator から mission 専用 AGMSG control recipient への `MISSION_DONE <id>`
2. fallback として orchestrator が `done`、executor が `idle` または `done`

AGMSG の明示シグナルを優先することで、Claude Code の interactive process が終了せず idle のままでも完了を表現できます。

## 5. State ownership

| State | Authority | Persistence |
|---|---|---|
| pane / workspace / agent state | Herdr | Herdr session state |
| terminal content | Herdr PTY | Herdr scrollback |
| terminal network route | iOS policy + Gateway capability | iOS preferences |
| Mosh connection key | mosh-server → iOS one-time response | not persisted |
| agent coordination messages | AGMSG | AGMSG storage |
| mission metadata | Gateway | `missionStore` JSON |
| delivery cursor per mission identity | Gateway | `missionStore` JSON |
| API credential | Gateway + iOS Keychain | token file / Keychain |
| UI selection | iOS | in-memory |
| Gateway activity metadata | Gateway | JSONL audit log |

## 6. Failure model

- **iPhone disconnect:** agents continue on Mac。再接続時に snapshot を再取得
- **SSE disconnect:** exponential reconnect。初回 REST state は維持
- **Wi-Fi / cellular change:** Terminal task を cancelし、route policyを再評価
- **Mosh UDP failure:** bounded retry。Rich / Raw / control planeはHTTPSで継続
- **Mosh clientなし:** full functionalityのうちTerminal roamingだけをGatewayへfallback
- **Gateway restart:** `running` Mission と AGMSG delivery cursor を復元し、未配送 ID を再処理
- **Herdr event stream unsupported:** snapshot polling へ fallback
- **Gateway restart:** mission store と AGMSG log から復元。Mosh session descriptorは再発行
- **Mac sleep/offline:** iPhone から到達不能。Mac の電源・sleep 設定が必要
- **AGMSG script unavailable:** health check が失敗し、mission start はエラー
- **Model/CLI rename:** `gateway/config.json` の profile を更新

## 7. バージョニング方針

Herdr JSON は未知 field を無視する tolerant decoder を iOS で採用しています。Gateway は必要な result type を検証し、破壊的な protocol mismatch を明示エラーにします。

モデル名や effort は iOS enum に固定せず、Mac 側 profile metadata と argv から配信します。
