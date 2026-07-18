# HerdDeck 0.2.0

HerdDeck は、MacBook 上で動く **Herdr + Claude Code + Codex + AGMSG** を、iPhone / iPad から監視・操作・再利用するためのネイティブ SwiftUI クライアントと、loopback-only Gateway です。

0.2.0 では、通信と表示を独立したレイヤーとして実装しました。

- **Control plane:** エージェント状態、Mission、AGMSG、Rich / Raw 出力は常に認証済み HTTPS/SSE over Tailscale
- **Interactive terminal:** Wi-Fi では Gateway、携帯網では embedded Mosh を自動選択可能
- **Rendering:** `Rich` / `Terminal` / `Raw` をいつでも切り替え可能

> **配布形態:** source-ready build。署名済み IPA、Provisioning Profile、App Store archive は含みません。iOS 実機ビルドには Xcode 16 以降、XcodeGen、Apple Developer signing が必要です。

## 主要機能

- Herdr `session.snapshot` + `events.subscribe` によるライブ状態同期
- `blocked / working / done / idle` を優先表示する Herd 画面
- Claude Code Fable / high を orchestrator、Codex GPT-5.6-Sol / high を executor とする Mission
- AGMSG の公式 script API を使った永続的な agent-to-agent coordination
- Mission 固有 identity、完了シグナル、Codex delivery assist、再起動可能な cursor
- iPhone / iPad 向けの Rich / Terminal / Raw 表示
- SwiftTerm による ANSI、VT100/Xterm、Unicode、日本語、絵文字、罫線、外付けキーボード対応
- `NWPathMonitor` による Wi-Fi / 携帯網判定
- 携帯網時の embedded Mosh terminal roaming
- Tailscale Serve、Bearer token、Keychain、Face ID / Touch ID、RPC allowlist、監査ログ
- macOS `launchd`、doctor、token rotation、QR pairing

## 動作構成

```text
iPhone / iPad
└─ HerdDeck
   ├─ Control Plane
   │  ├─ agents / missions / AGMSG
   │  ├─ Rich / Raw output
   │  └─ HTTPS + SSE over Tailscale
   │
   └─ Interactive Terminal
      ├─ Wi-Fi: HTTPS → Gateway → Herdr pane
      └─ Cellular: HTTPS bootstrap → Mosh UDP → herdr agent attach
             │
             ▼
MacBook
├─ Tailscale Serve → 127.0.0.1:8787
├─ HerdDeck Gateway
│  ├─ Herdr Unix socket adapter
│  ├─ Mosh session broker
│  ├─ AGMSG official script adapter
│  ├─ Mission orchestrator
│  └─ audit / persistent mission state
├─ Herdr
│  ├─ Claude Code orchestrator
│  └─ Codex executor(s)
└─ Ghostty — 同じ Herdr session のローカル操作面
```

Mosh は control plane を置き換えません。iPhone が携帯網へ移動したとき、**Terminal 表示だけ**が Mosh に切り替わります。Rich / Raw、agent state、Mission、AGMSG は HTTPS を継続します。

## 表示モード

### Rich

AI の出力をモバイル向けに再構成します。

- 見出し、段落、強調、リンク
- 箇条書き、引用、区切り
- fenced code block とコピー
- Markdown table
- 日本語、複合絵文字、国旗、ZWJ sequence

### Terminal

SwiftTerm の `TerminalView` へ ANSI stream を供給します。

- VT100 / Xterm state
- 16 / 256 color と True Color
- cursor、alternate screen、scrollback
- Unicode grapheme cluster、日本語全角、絵文字
- mouse reporting、OSC 8 link、外付けキーボード
- `Esc`、`Tab`、`Ctrl+C`、`Ctrl+D`、矢印、Enter の mobile key rail

### Raw

Herdr の plain-text output を加工せず、検索・選択しやすい monospaced view で表示します。

詳細は [docs/RENDERING.md](docs/RENDERING.md) を参照してください。

## 携帯網での Mosh

自動ポリシーでは次のように動作します。

```text
Wi-Fi             → Gateway terminal
Cellular          → Mosh terminal
Wi-Fiへ復帰       → 設定した hysteresis 後に Gatewayへ戻る
Mosh利用不可      → Gatewayへ安全にfallback
Rich / Raw        → 常にGateway
```

Gateway は認証済み HTTPS request を受けて Mac 上で `mosh-server` を起動し、`herdr agent attach <pane> --takeover` を実行します。iOS に SSH private key を持たせる必要はありません。Mosh session key は no-store HTTPS response で一度だけ渡され、監査ログには保存しません。

詳細は [docs/MOSH.md](docs/MOSH.md) を参照してください。

## デフォルト agent profile

### Claude Code orchestrator

```bash
claude \
  --model fable \
  --effort high \
  --name herddeck-orchestrator
```

### Codex autonomous executor

```bash
codex \
  --model gpt-5.6-sol \
  -c 'model_reasoning_effort="high"' \
  --sandbox workspace-write \
  --add-dir "$HOME/.agents/skills/agmsg"
```

モデル、effort、sandbox、追加 writable root は `gateway/config.json` の profile で管理します。利用中の CLI / account で該当モデルが使えない場合は profile の `argv` を変更してください。

## 前提条件

MacBook:

- macOS、Herdr、Claude Code、Codex、AGMSG、Tailscale
- Node.js 22 以降、Python 3
- Mosh terminal を使う場合は `mosh-server`
- iOS build 用に Xcode 16 以降と XcodeGen

iPhone / iPad:

- iOS / iPadOS 18 以降
- Mac と同じ tailnet

## セットアップ

### 1. Herdr integration

Claude Code と Codex のログインを済ませ、Mac で実行します。

```bash
herdr integration install claude
herdr integration install codex
herdr integration status
herdr
```

### 2. AGMSG

```bash
npx agmsg
```

インストール後、既存の Claude Code / Codex session を再起動して skill と hook を読み込ませます。

### 3. Gateway

```bash
cd /path/to/HerdDeck-0.2.0
cp gateway/config.example.json gateway/config.json
$EDITOR gateway/config.json
./scripts/bootstrap-mac.sh
```

最低限、次を実環境へ合わせます。

- `projectRoots`
- `herdrSocket`
- `agmsgRoot`
- agent profile の model / CLI flags

`projectRoots` の外にある working directory は拒否されます。

### 4. Mosh を有効化

```bash
./scripts/bootstrap-mosh-mac.sh
```

表示された Tailscale IP / MagicDNS 情報を `gateway/config.json` の `mosh` block へ設定し、`enabled` を `true` にします。

```json
"mosh": {
  "enabled": true,
  "serverPath": "/opt/homebrew/bin/mosh-server",
  "herdrPath": "/opt/homebrew/bin/herdr",
  "advertiseHost": "100.64.0.10",
  "bindAddress": "100.64.0.10",
  "portRange": "60000:61000",
  "predictionMode": "adaptive",
  "startupTimeoutMs": 6000,
  "networkTimeoutSeconds": 604800,
  "takeover": true
}
```

インターネット向けルーターポート開放は不要です。tailnet ACL / grants と macOS firewall では、必要な iPhone / iPad から Mac の UDP range だけを許可してください。

### 5. Gateway 常駐と Tailscale Serve

```bash
./scripts/doctor.sh
./scripts/install-launch-agent.sh
./scripts/tailscale-serve.sh
```

**Tailscale Funnel は使用しません。** Gateway は loopback のままにし、Serve で tailnet 内だけへ公開します。

### 6. iOS project

フル版は embedded Mosh を含みます。

```bash
brew install xcodegen
./scripts/build-mosh-ios.sh
./scripts/generate-xcode-project.sh
open HerdDeck.xcodeproj
```

Xcode が pinned Blink Mosh / Protobuf XCFramework と SwiftTerm を Swift Package Manager で取得します。Signing Team と必要なら Bundle Identifier を設定して実機へ Build & Run します。

Mosh をリンクしない Lite build:

```bash
./scripts/generate-xcode-project.sh --lite
open HerdDeckLite.xcodeproj
```

Lite build でも Rich / Terminal / Raw と SwiftTerm は利用できますが、携帯網 Terminal は HTTPS Gateway を使います。

### 7. Pairing

```bash
brew install qrencode   # 任意
./scripts/pairing-qr.sh
```

QR に bearer token が含まれるため、画面共有やスクリーンショット保存を避けてください。

## Mission workflow

Missions で goal、acceptance criteria、repository、AGMSG team、orchestrator、1〜4 個の executor を選択します。

1. Gateway が project path を realpath 化し allowlist を確認
2. Mission 専用 Herdr workspace と AGMSG identity を生成
3. Claude orchestrator が task を分割
4. Codex executor が sandbox 内で実装・test・review
5. AGMSG では短い summary、artifact path、commit SHA を交換
6. Claude が統合・検証し `MISSION_DONE <mission-id>` を送信
7. Gateway が durable log から完了を確定

詳細は [docs/ORCHESTRATION.md](docs/ORCHESTRATION.md) を参照してください。

## 検証

Linux / macOS で実行できる静的・Gateway 検証:

```bash
make validate
```

macOS + Xcode では追加で実行します。

```bash
./scripts/generate-xcode-project.sh
xcodebuild \
  -project HerdDeck.xcodeproj \
  -scheme HerdDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

この配布物で実施済みの検証は [VERIFICATION.md](VERIFICATION.md) に記載しています。

## セキュリティ

HerdDeck は Mac の PTY へ入力できるため、認証済みクライアントは実質的にその Mac user の shell 権限を持ちます。

- Gateway は `127.0.0.1` / `::1` 以外への bind を拒否
- Tailscale Serve のみ使用
- 256-bit 相当 bearer token と constant-time compare
- iOS Keychain `WhenUnlockedThisDeviceOnly`
- Face ID / Touch ID / device passcode
- process / project / RPC allowlist
- terminal input、message、request、rate の上限
- Mosh key と terminal body を audit log に記録しない
- Codex は `workspace-write` を維持
- dangerous permission / sandbox bypass を初期 profile に含めない

詳細は [docs/SECURITY.md](docs/SECURITY.md) を参照してください。

## 現在の境界

- Xcode / iOS SDK が必要な最終 link、code signing、実機 E2E は対象 Mac で実施してください
- APNs relay は未実装のため、アプリ suspend 中の即時通知は保証しません
- Rich renderer は CommonMark 全仕様、Mermaid、任意 HTML、artifact image browser をまだ実装していません
- Mosh は iOS background execution を無制限にはできません。foreground 復帰時に再接続・再 bootstrap します
- Mosh は interactive terminal 専用で、Mission / AGMSG / state API の offline queue ではありません
- Mosh `--takeover` を有効にすると、同じ agent への別 direct-attach client の input ownership を引き継ぎます

## ライセンス

HerdDeck 自身のコードは MIT License です。

- SwiftTerm: MIT
- Mosh: GNU GPL v3 or later
- Blink の pinned Mosh / Protobuf XCFramework: 各 upstream license に従う

フル版を build すると GPL の Mosh とリンクします。リンク済み binary を第三者へ配布する場合は、GPLv3-or-later の source / notice / corresponding-source 要件を満たす前提で扱い、App Store 配布については法務確認を行ってください。Mosh をリンクしない `--lite` build も用意しています。

詳細は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) と [LICENSES/GPL-3.0.txt](LICENSES/GPL-3.0.txt) を参照してください。

## ドキュメント

- [Architecture](docs/ARCHITECTURE.md)
- [Mosh transport](docs/MOSH.md)
- [Rendering](docs/RENDERING.md)
- [Orchestration](docs/ORCHESTRATION.md)
- [Security](docs/SECURITY.md)
- [Gateway API](docs/API.md)
- [UI / UX](docs/UX.md)
- [Reviewed sources](docs/SOURCES.md)
- [Verification](VERIFICATION.md)