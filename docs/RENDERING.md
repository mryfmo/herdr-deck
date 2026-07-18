# Rendering: Rich / Terminal / Raw

## 設計原則

通信品質と表示品質は別問題です。Mosh の有無にかかわらず、HerdDeck は同じ出力に対して三つの presentation を提供します。

```text
Transport
├─ HTTPS pane read / input
└─ Mosh terminal state

Rendering
├─ Rich
├─ Terminal
└─ Raw
```

Mosh は Terminal mode の transport になり得ますが、Rich text renderer ではありません。

## Rich mode

`RichOutputParser` が Herdr `recent_unwrapped` text を mobile-friendly block へ分解します。

対応 block:

- ATX heading `#`〜`######`
- paragraph
- inline Markdown emphasis / code / link
- unordered / ordered list item
- quote
- horizontal divider
- fenced code block（backtick / tilde）
- Markdown table

Code block は横スクロールと copy button を持ちます。Table は iPhone では横スクロール、iPad では利用可能幅を活用します。

現時点で未実装:

- CommonMark の完全な nested block grammar
- syntax highlighter
- Mermaid
- arbitrary HTML
- remote image / attachment browser
- terminal transcriptからの厳密な「最終回答」抽出

Rich mode は読みやすさを優先するため、terminal cursor / alternate-screen state は再現しません。

## Terminal mode

`TerminalEmulatorView` は SwiftTerm `TerminalView` を埋め込み、Gateway の ANSI snapshotまたは Mosh byte streamをfeedします。

利用している機能:

- VT100 / Xterm control sequence
- standard / bright / 256-color / True Color
- bold / italic / underline / inverse
- cursor、alternate screen、scrollback
- box drawing用 custom glyph
- mouse reporting
- implicit / OSC 8 links
- clipboard copy
- external keyboard input
- Metal-capable native renderer

### Unicode / emoji

Swift `String` と JSON は UTF-8 / Unicode を保持し、Rich / Raw は system text stack が grapheme cluster を描画します。Terminal は SwiftTerm の terminal cell modelを使います。

対象例:

```text
日本語
🙂 🚀 ✅
👨‍💻
🇯🇵
1️⃣
é
罫線 ┌─┬─┐
```

Terminal では code point 数ではなく、grapheme cluster と terminal cell width が重要です。SwiftTerm を使うことで、単純な SwiftUI `Text` に ANSI output を入れる方式より cursor / table / box drawing の整合性を高めています。

フォントに glyph がない場合は iOS font fallback が使われます。特定の Nerd Font private-use glyph は system font で代替表示または tofu になる可能性があります。

### Input

- Mosh route: SwiftTerm の raw bytesをそのまま Moshへ送る
- Gateway route: common CSI / control bytesを Herdr key namesへ変換し、UTF-8 textと分離して `pane.send_input` へ送る

Mobile key rail:

```text
Esc  Tab  Ctrl+C  Ctrl+D  ←  ↓  ↑  →  Enter
```

Native composer は日本語IME、dictation、pasteを担当します。

## Raw mode

Herdr `recent` plain textを monospaced `Text` で表示します。

- text selection
- horizontal / vertical scroll
- revision表示
- truncation表示
- ANSI interpretationなし

escape sequenceを実行せず内容を調査したい場合、logをcopyしたい場合、Rich parserの解釈を避けたい場合に使用します。

## Networkとの関係

| Mode | Wi-Fi | Cellular |
|---|---|---|
| Rich | HTTPS | HTTPS |
| Terminal | HTTPS by default | Mosh by automatic policy |
| Raw | HTTPS | HTTPS |

Rich / Raw は control planeに残すことで、Mosh UDP pathが利用できない環境でも agent state と成果物を確認できます。

## Security

- Rich の Markdown は `AttributedString` とnative viewで描画し、任意HTML / JavaScriptを実行しない
- Terminal linkは `http` / `https` schemeだけを `UIApplication.open` へ渡す
- Raw はANSIを解釈しない
- clipboard actionはユーザー操作時だけ
- terminal input本文はGateway auditに保存しない

## Accessibility

- Rich / Raw は Dynamic Type と text selection
- statusは色だけでなくlabel / iconを併用
- Terminal viewにaccessibility label
- iPad landscapeとhardware keyboard

今後は VoiceOver 向け line navigation、terminal font size control、reduced-motion tuning、structured diff / test result rendererを追加します。