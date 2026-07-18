# UI / UX Design

## Product principle

HerdDeck は「スマートフォンにデスクトップターミナルを縮小表示する」設計ではありません。

情報密度の高い TUI をそのまま常時表示するのではなく、モバイルで重要な判断を GUI に昇格させます。

- 誰が作業中か
- 誰が入力待ちか
- どの mission が進行中か
- Claude と Codex が何を引き継いだか
- どの pane に降りればよいか

詳細操作だけを terminal surface に残します。

## Navigation

### Herd

最初に見る運用画面です。

- `blocked` を最上位
- `working`、`done`、`idle` の順に整理
- agent runtime / role / cwd / custom status
- reusable profile launcher
- active mission pulse

カードから Console へ直接遷移します。

### Console

TUI と GUI の接点です。

- 横スクロールの agent rail
- `Rich / Terminal / Raw` segmented presentation
- network interface と active terminal route の status pill
- SwiftTerm の VT100/Xterm surface
- `Esc`、`Tab`、`Ctrl+C`、`Ctrl+D`、矢印、Enter
- multiline native text composer
- agent / pane inspector
- 低遅延 foreground polling
- cellular 時は Terminal だけを Moshへ自動切替

通常の日本語入力、音声入力、paste は native text editor に任せ、制御キーだけ専用 UI に分離します。

Rich / Raw は Mosh の状態に依存せず HTTPS で利用できます。Mosh 接続中でもユーザーは Rich に切り替えて読みやすい出力を確認できます。

### Missions

目的ベースの orchestration UI です。

- title / goal / project / team
- orchestrator / executor profile selection
- max rounds
- delivery assist
- agent role badge
- mission history

CLI command や model flag は mission composer へ露出せず、Mac 管理者が profile で統制します。

### Messages

AGMSG の durable coordination log を人間が読み書きする面です。

- team switcher
- member list
- from / to selection
- message timeline
- manual intervention

大きな成果物は path / commit を開発環境側で確認する前提です。

### Settings

- connection health
- Gateway / Herdr / AGMSG diagnostics
- active network interface / expensive / constrained state
- `Mosh on cellular / Gateway only / Prefer Mosh` policy
- Wi-Fi return hysteresis
- Mosh prediction mode と server / embedded-client health
- default Rich / Terminal / Raw presentation
- endpoint
- biometric lock
- terminal poll interval
- security reminders
- forget / re-pair

## Visual language

- dark adaptive background
- subtle grid / depth
- glass cards
- violet: orchestrator / planning
- cyan: executor / terminal
- mint: healthy / completed
- rose: failed / blocked
- monospaced typography for IDs、paths、terminal

色だけに依存せず、icon、label、position を併用します。

## Interaction rules

- destructive operation を主要画面に常設しない
- blocked agent を最短 1 tap で開く
- connection loss でも最後の snapshot を急に消さない
- terminal input は送信前にユーザーが確認可能
- special key は誤操作を減らすため text composer と分離
- model / sandbox authority は iOS ではなく Mac config
- app background 時に biometric lock を再適用

## Accessibility

- Dynamic Type 対応の system font
- VoiceOver で意味が分かる SF Symbols + text label
- status は色以外の文字 label を表示
- external keyboard で native input を利用可能
- iPad landscape を許可
- Rich / Raw は text selection を許可
- Terminal は Unicode / emoji / custom box glyphをnative描画

今後、hardware keyboard shortcut、VoiceOver 向け terminal line navigation、reduced-motion tuning を追加予定です。

## TUI fidelity の方針

Terminal mode は SwiftTerm の VT100/Xterm emulator を使用します。一方で、Herd / Missions / Messages を primary surface とし、terminal は詳細操作面という product hierarchy は維持します。

- agent status は terminal screen scraping だけに依存せず Herdr metadata を表示
- final answer の可読性は Rich mode で補う
- ANSI interpretation が不要な調査は Raw mode で行う
- mobile で頻繁に必要な control key は専用 rail に置く

完全な desktop terminal clone を目標にせず、GUI で判断し、必要な瞬間だけ忠実な TUI へ降りる構成です。
