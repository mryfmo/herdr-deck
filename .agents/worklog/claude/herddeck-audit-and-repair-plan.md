# HerdDeck 0.2.0 網羅監査と修正計画

作成: 2026-07-18 / orchestrator: claude-fable5high-herddeck(監査エージェント 3 系統 + オーケストレータ裏取り済み)

## 1. 趣旨と意図の把握

HerdDeck は「Mac 上の Herdr + Claude Code + Codex + AGMSG を iPhone/iPad から監視・操作する」システム。

- **iOS (SwiftUI, iOS 18+)**: thin client。snapshot ライブ同期(SSE)、Herd 概観、Mission、AGMSG timeline、Rich/Terminal/Raw の 3 表示、Wi-Fi/携帯網ルーティング + 携帯網時 embedded Mosh、Keychain/生体認証
- **Gateway (Node 22 stdlib のみ, loopback-only)**: HTTP/JSON + SSE、Herdr Unix socket adapter、AGMSG 公式 script adapter(SQLite 直接触禁止)、Mosh broker、Mission orchestrator(mission 固有 identity、durable store、delivery assist、MISSION_DONE 検出)、監査ログ、bearer 認証
- **配布**: source-ready。Makefile 検証、XcodeGen 3 仕様(full/lite/mosh)、bootstrap/doctor/launchd/Tailscale Serve スクリプト群

## 2. 総括(headline)

出荷状態では中核機能が動作しない。

1. **iOS アプリはコンパイル不能**(C-2: Swift 6 actor 分離違反。full/lite 両ビルド)。full ビルドはさらに C-3 で不能
2. コンパイルを直しても **SSE ライブ同期が一切機能しない**(C-1: パーサのイベント境界検出が到達不能)→ 手動リフレッシュ専用アプリになる
3. **Gateway の AGMSG 読み取り半分が全滅**(C-4: 存在しない `api.sh` に依存)→ AGMSG REST 3 種、delivery assist、MISSION_DONE 検出が全 mission で不動作。さらに C-5 により herdr ステータスによる完了フォールバックも到達不能で、**mission は永遠に completed にならない**
4. **セットアップ導線も破損**(C-6: bootstrap-mac.sh が対話 REPL を起動してハング / H-B1,B2: `make validate` が素の macOS で通らない)
5. テストスイートは 23/23 green だが、C-4 と C-5 を**構造的に検出できない作り**(存在しない api.sh のフィクスチャ、本番で到達不能なパスの検証)

## 3. 所見一覧

裏取り状況: ★ = オーケストレータが独立に再確認済み。他は監査エージェントがコード/実行で検証済み。

### Critical(6 件)

| ID    | 場所                                                                                 | 問題                                                                                                                                                                                                                                         |
| ----- | ------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C-1 ★ | iOS `Networking/GatewayClient.swift:212-226`                                         | SSE パーサが `line.isEmpty` でのみイベント確定するが、`AsyncBytes.lines` は空行を produce しない → yield 到達不能。全ライブ同期(snapshot/mission/agmsg/gateway-error)死亡+`dataLines` 無限成長                                               |
| C-2 ★ | iOS `Services/NetworkPathService.swift:30`                                           | nonisolated な `pathUpdateHandler` 内から @MainActor 分離の `Self.interface(for:)` を同期呼び出し → Swift 6 でコンパイルエラー(swiftc 実証済み)。full/lite 両方ビルド不能                                                                    |
| C-3 ★ | iOS `Console/MoshSessionController.swift:160` vs `HerdDeckMosh/HerdMoshSession.h:23` | ObjC `resizeWithColumns:rows:` は Swift へ `resize(withColumns:rows:)` で import されるが `resize(columns:rows:)` で呼んでいる → full(Mosh)ビルドのみコンパイルエラー。`#if HERDDECK_EMBEDDED_MOSH` 内のため Makefile typecheck では検出不能 |
| C-4 ★ | gateway `agmsg-client.mjs:17,36,55,67`                                               | 読み取り系すべてが `<agmsgRoot>/scripts/api.sh` を呼ぶが、インストール済み agmsg skill に api.sh は存在しない(grep 実証)。`/v1/agmsg/*` 3 種・delivery assist(`workflow.mjs:279`)・MISSION_DONE 検出(`workflow.mjs:600`)が ENOENT で全滅     |
| C-5 ★ | gateway `workflow.mjs:593-627`                                                       | `#reconcileSnapshot` 内の未ガード `await this.agmsg.messages()` が throw すると per-mission ループ全体が中断 → ARCHITECTURE.md が約束する「herdr status による完了フォールバック」が本番で到達不能。mission が完了しない                     |
| C-6 ★ | `scripts/bootstrap-mac.sh:17-29`                                                     | 未クォート heredoc 内のバッククォート `` `claude` `` `` `codex` `` がコマンド置換として実行 → 対話 REPL が起動しブートストラップがハング                                                                                                     |

### High(7 件)

| ID     | 場所                                                      | 問題                                                                                                                                                                                      |
| ------ | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| H-G1   | gateway `agmsg-client.mjs:86` vs config.mjs:23 vs join.sh | runtime whitelist が三者不整合: config は `'other'` を許可 →join で必ず throw。`'opencode'` は gateway 通過 →script で exit 1。`'antigravity'` は script 対応済みなのに gateway が拒否    |
| H-G2   | gateway `sse.mjs:21-51` + `index.mjs:98-107`              | SSE client response に `'error'` listener なし。非同期 error → uncaughtException → `process.exit(1)`。**iPhone 1 台の切断タイミングで Gateway 全体が死ぬ**                                |
| H-G3   | gateway `router.mjs:114-116`                              | client 制御の `x-request-id` を try/catch 外で `setHeader` → 不正値で unhandledRejection → プロセス終了(pre-auth クラッシュベクタ)                                                        |
| H-I1   | iOS `Console/TerminalInputMapper.swift:44-52`             | 未知のエスケープシーケンス(mouse reporting/app-cursor/bracketed paste)を「esc キー + 残骸テキスト」に分解して送信 → TUI 状態破壊+ゴミ注入。`TerminalEmulatorView` は mouse reporting 有効 |
| H-I2   | iOS `TerminalInputMapper.swift:50` + gateway 制約         | 改行 33 個超のペーストは keys>32 で 400 一括拒否。かつ text/keys の交互順序が失われ `"line1line2"+[enter,enter]` に再配列                                                                 |
| H-B1 ★ | `Makefile:29`                                             | `swift-format` が素の macOS PATH に無い(`xcrun` 必須)→ `make data-validate`/`validate` 失敗                                                                                               |
| H-B2 ★ | `Makefile:28`                                             | `import yaml`(PyYAML)は stdlib 外で未インストール → 同上失敗。README 前提条件にも記載なし                                                                                                 |

### Medium(13 件)

| ID     | 場所                                    | 問題                                                                                                                                                                     |
| ------ | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| M-G1   | gateway `herdr-client.mjs:229-244`      | snapshot fingerprint に揮発 `scroll` フィールドが含まれ、エージェント出力のたび「変化あり」→ SSE 全配信 + mission ごとの agmsg exec 連発(抑制機構が実質無効)             |
| M-G2   | gateway `router.mjs` 各所               | 「public API は camelCase / normalized snapshot」という API.md の記述に反し、snapshot/read/rpc/profiles/start/SSE が raw snake_case をそのまま返す(正規化層が存在しない) |
| M-G3   | gateway `workflow.mjs:368-373`          | 起動中クラッシュした mission が `starting` のまま永久残留(resumeRunning は running のみ)。復旧・失敗遷移なし                                                             |
| M-G4   | gateway `router.mjs:132-138`            | 認証が rate limit より先 → 無効 token リクエストは無制限。limiter key の token 側は定数で「per token」は虚偽                                                             |
| M-G5   | gateway `router.mjs:309-318`            | `HerdrRpcError` に statusCode が無く pane_not_found 等が 500。agmsg exit code が数値 `error.code` に                                                                     |
| M-G6   | gateway `mosh-manager.mjs:87,174`       | セッション map が書き込み専用の無限リーク(読取・失効・削除・一覧 API なし)                                                                                               |
| M-G7   | gateway `workflow.mjs:255-262`          | delivery-assist の catch 内 `audit.failure` throw でループ死+プロセス終了。agmsg 故障時 1.5 秒ごとの failure 追記が無制限成長                                            |
| M-I1   | iOS `Models/MissionModels.swift:85-89`  | `/v1/profiles/start` 応答デコードが gateway 非保証フィールド(argv、full HerdrAgent)を必須要求 → 起動成功でも decode_failed、副作用喪失                                   |
| M-I2   | iOS `HerdMoshSession.mm:144-149`        | resize が `_windowSize` 更新のみで SIGWINCH 等の通知なし+ロック不整合 → リモート PTY サイズ固定(MOSH.md の記述に反する)                                                  |
| M-I3   | iOS `AppState.swift:347-348`            | 表示モード切替だけで hysteresis task を無条件 cancel → Wi-Fi 復帰待機中の Mosh が即切断                                                                                  |
| M-I4   | iOS `AgentNotificationService.swift:13` | `Dictionary(uniqueKeysWithValues:)` — snapshot 内の terminal_id 重複でクラッシュ(リモート入力で trap)                                                                    |
| M-I5   | iOS `AppState.swift:455-479`            | SSE ループの `guard let self` が strong 化して deinit 不能。retryDelay がリセットされず常時 15 秒待ちに劣化                                                              |
| M-B1 ★ | `Makefile:35` + README                  | `validate` が `test ! -f gateway/config.json` を含み、セットアップ済み Mac では README の指示どおり実行しても必ず無言で失敗                                              |

### Low(主要のみ抜粋、計 ~20 件)

- L-G: 認証前 401 無制限(M-G4 と同根)/ mosh 起動タイムアウト kill が detached server に届かない / `preflightConfig`・`deliveryStatus` デッドコード / token 初回生成の並行競合 / 破損 `missions.json` で起動不能 / orchestrator prompt が runtime 無視で Claude 構文 `/agmsg` 固定(`workflow.mjs:148`)/ JSON body が null/配列だと 500 / profiles 非配列で raw TypeError
- L-I: Rich モード追従スクロールなし / ISO8601 小数秒で全メッセージ時刻が「現在時刻」化 / expensive/constrained 表示が stale / UX.md 記載の poll interval 設定 UI 不在 / lite build に `NSLocalNetworkUsageDescription` 欠落 / onSubmit 二重送信 / 数値 error code で envelope decode 失敗(M-G5 と同根)/ `HerdMoshSession.start` 失敗パス fd リーク
- L-B: `make archive` が `.codex/ .claude/ .agents/ .orchestration/ gateway/*.log` を配布 zip に混入 / `project-mosh.yml` は project.yml と同一の死にファイル / `bash -n` ループが途中失敗を握りつぶす / doctor.sh の KeyError で検査スキップ+token が ps 可視 / generate-token が任意ディレクトリを chmod 700 / launchctl enable の順序 / VERIFICATION.md の swift-format 主張が再現しない(--strict なしで常に exit 0)/ `.codex/hooks.json` が MANIFEST/gitignore 外 / JSON rglob が tree 全域
- **テスト構造欠陥**: `agmsg-client.test.mjs` が存在しない api.sh をフィクスチャで捏造 / `workflow.test.mjs` の完了テストが本番非到達パス(controlAgmsgName なし)を検証 / MissionOrchestrator.start と router が完全未テスト

MANIFEST-SHA256 は全 116 件一致(改竄・欠落なし)。herdr 0.7.3 実 schema との RPC 整合、REST パス/モデルの iOS⇔gateway 契約、Mosh key の監査ログ排除、XcodeGen のソース網羅(directory-based)は検証済みで問題なし。

## 4. 修正計画

方針: 依存順に 4 フェーズ。各フェーズ完了ごとに検証ゲートを通す。修正実装は agmsg ワーカー(codex-gpt56solhigh-herddeck)へ AGMSG-TASK として順次委任し、オーケストレータが adversarial review で受入(sandbox の unix-socket listen 制約があるテスト実行はオーケストレータ側で照合)。

### Phase 0 — ビルド成立とスイート信頼性の回復(C-2, C-3, C-6, H-B1, H-B2, M-B1)

1. `NetworkPathService.swift`: `interface(for:)` を `nonisolated` に(状態非依存の純関数)
2. `MoshSessionController.swift:160`: `resize(withColumns:rows:)` へ修正(または header に `NS_SWIFT_NAME(resize(columns:rows:))`)
3. `bootstrap-mac.sh`: 案内文の heredoc をクォート済み区切り(`<<'MSG'`)へ分離、`$CONFIG` は printf で出力
4. Makefile: `xcrun swift-format`(非 mac fallback 付き)/ PyYAML 依存を排し `xcodegen dump --spec` か python の存在チェック付き skip / `bash -n "$$f" || exit 1` / 配布物 assert(`config.json` 不在等)を `dist-validate` へ分離し `validate` から除外
5. **検証ゲート**: `make validate` が素の macOS で成功、`swiftc -typecheck`(全 Swift ファイル + `-D HERDDECK_EMBEDDED_MOSH` 両条件)が成功

### Phase 1 — 中核機能の復旧(C-1, C-4, C-5, H-G1, H-G2, H-G3)

6. **AGMSG 読み取り経路の再実装**(最重要・要設計判断): SQLite 直接読取は ARCHITECTURE 方針で禁止のため、リポジトリ内に JSONL を出力する読み取りアダプタ script(`gateway/scripts/agmsg-read.sh`: `history.sh`/`inbox.sh`/team config を JSONL 化)を追加し、`agmsg-client.mjs` の `run('api.sh',…)` をそこへ向ける。preflight の required リストも実在 script に合わせる。テストは実 script 出力形式のフィクスチャに差し替え
7. `workflow.mjs #reconcileSnapshot`: agmsg 読取を mission ごとに try/catch し、失敗時 `explicitCompletion=false` でフォールバック継続。delivery-assist の catch 内 audit throw もガード+バックオフ(M-G7 同時修正)
8. `GatewayClient.swift` SSE: `.lines` をやめ byte stream から手動フレーミング(空行=イベント境界、`\r\n` 対応)。`dataLines` 上限も導入。M-I5(weak self / retryDelay リセット)を同時修正
9. `sse.mjs`: `response.on('error', …)` で client 除去。`router.mjs`: `X-Request-ID` 処理を try 内へ移動+値 sanitize
10. runtime whitelist の単一情報源化: join.sh の実 case リスト(`claude-code|codex|gemini|antigravity|copilot`)に gateway 側(config 検証・join)を揃え、`'other'` は mission validation で明示拒否
11. **検証ゲート**: gateway 全テスト green(捏造フィクスチャ排除後)+ 実機 smoke: 実 herdr/agmsg に対し gateway を起動し `/v1/agmsg/teams`・SSE snapshot 受信・mission 完了遷移を確認(これは sandbox 制約のためオーケストレータ側で実施)

### Phase 2 — 実用性・安定性(H-I1, H-I2, M-G1〜G6, M-I1〜I4)

12. `TerminalInputMapper`: 未知 `ESC [`/`ESC O` シーケンスは丸ごと破棄(分解禁止)、gateway ルートでは mouse reporting 無効化。text/keys を交互チャンクの逐次 `/input` 送信に変更(32 keys 制限内へ自然に収まる)
13. gateway: fingerprint から `scroll` 等揮発フィールド除去 / `starting` 残留 mission を起動時 `failed` 化 / rate limit を認証前へ+key 修正 / `HerdrRpcError`→4xx マップ+code 文字列化(iOS L-7 同根解消)/ mosh session map に TTL または削除
14. iOS: `AgentStartedResponse` を slim 化(argv optional、paneId/terminalId のみ必須)/ `Dictionary(…, uniquingKeysWith:)` / hysteresis cancel を transportPolicy 変更時のみに限定 / `HerdMoshSession` resize の SIGWINCH 通知+ロック統一
15. **検証ゲート**: gateway 単体テスト+router/orchestrator.start の新規テスト(テスト欠陥 3 件の解消)、iOS は `xcodebuild test`(Mac + Xcode 環境)

### Phase 3 — 配布物・ドキュメント・Low 一掃

16. `make archive` 除外リスト拡充(`.codex/ .claude/ .agents/ .orchestration/ *.log`)、`.gitignore` 追補、`project-mosh.yml` 削除(または `--with-mosh` を実配線)、MANIFEST 再生成
17. doctor.sh(`c.get()`+欠落 fail 化、token を argv から排除)、generate/rotate-token の chmod 限定、launchctl enable 順序
18. API.md/ARCHITECTURE.md を実装に合わせ改訂(snake_case 実態 or 正規化層導入のどちらかへ確定)、MOSH.md/UX.md/RENDERING.md/VERIFICATION.md の虚偽記述修正、Low 級 iOS/gateway 残件(時刻 parse、スクロール追従、二重送信、fd リーク等)
19. **最終検証ゲート**: `make validate` + `make dist-validate` + gateway 実機 smoke + full/lite 両 XcodeGen 生成 + MANIFEST 再検証

### 委任単位(AGMSG-TASK 案)

- T002: Phase 0(scripts+Makefile+Swift 2 行修正。allowed: Makefile, scripts/bootstrap-mac.sh, iOS の該当 2 ファイル)
- T003: Phase 1 gateway 側(agmsg 読取アダプタ+workflow/sse/router ガード+テスト差替)
- T004: Phase 1 iOS 側(SSE パーサ再実装+M-I5)
- T005〜: Phase 2 を gateway/iOS で分割、Phase 3 は一括
- 各タスク: allowed_files を該当ファイルに限定、forbidden: 依存追加・API 破壊変更。RESULT ごとにオーケストレータが独立再実行で照合

## 5. リスクと未確定事項

- **AGMSG 読取アダプタの形**(Phase 1-6)が最大の設計判断: skill 側に api.sh を追加するか、repo 内アダプタか。repo 内アダプタを推奨(配布物の自己完結性、skill 更新非依存)
- iOS の実機/シミュレータ E2E は Xcode 環境が必要(本監査は swiftc 静的検証と契約照合まで)
- Codex sandbox は unix-socket/TCP listen 不可のため、ワーカー委任時のテスト実行はオーケストレータ側検証で補完する
