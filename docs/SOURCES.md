# Reviewed Sources

最終確認日: **2026-07-17**

HerdDeck 0.2.0 は以下の公式ドキュメントと一次ソースを基準に設計しました。CLI、model catalog、protocol、binary release は変化するため、アップデート時は `./scripts/doctor.sh`、`make validate`、Xcode test を実行してください。

## Herdr

- Socket API: https://herdr.dev/docs/socket-api/
- Integrations: https://herdr.dev/docs/integrations/
- Japanese integrations: https://herdr.dev/ja/docs/integrations/
- Repository: https://github.com/ogulcancelik/herdr
- Reviewed source commit: `3661d99c2e4a4247392fc1a1eed5f37453393f8e`

利用した仕様:

- Unix domain socket + newline-delimited JSON
- `session.snapshot`
- `events.subscribe`
- workspace / tab / pane / agent methods
- `pane.read`、`pane.send_text`、`pane.send_keys`、`pane.send_input`
- `agent.start`
- Claude / Codex integration installation and session reporting

## Claude Code

- CLI reference: https://code.claude.com/docs/en/cli-reference

利用した仕様:

- `--model fable`
- `--effort high`
- `--name`
- interactive positional prompt

Claude Code の flags は `--help` にすべて表示されるとは限らないため、公式 CLI reference を authority とします。

## OpenAI Codex

- Repository: https://github.com/openai/codex
- Model catalog: https://github.com/openai/codex/blob/main/codex-rs/models-manager/models.json
- CLI shared options: https://github.com/openai/codex/blob/main/codex-rs/utils/cli/src/shared_options.rs
- Config overrides: https://github.com/openai/codex/blob/main/codex-rs/utils/cli/src/config_override.rs
- Config schema: https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json
- Reviewed source commit: `9e552e9d15ba52bed7077d5357f3e18e330f8f38`

利用した仕様:

- model slug `gpt-5.6-sol`
- supported reasoning level `high`
- minimum client version `0.144.0` in the reviewed bundled catalog
- `--model`
- `-c key=value`
- `model_reasoning_effort`
- `--sandbox workspace-write`
- `--add-dir`

## AGMSG

- Repository: https://github.com/fujibee/agmsg
- README: https://github.com/fujibee/agmsg/blob/main/README.md
- Building on AGMSG: https://github.com/fujibee/agmsg/blob/main/docs/building-on-agmsg.md
- `actas` mechanics and Codex caveat: https://github.com/fujibee/agmsg/blob/main/docs/actas.md
- Agent type / delivery manifests: https://github.com/fujibee/agmsg/blob/main/docs/agent-types.md
- Read-only API: https://github.com/fujibee/agmsg/blob/main/scripts/api.sh
- Reviewed source commit: `af10ad080081284012349973cd4e1167a7735813`

利用した仕様:

- Claude `/agmsg` and Codex `$agmsg`
- `actas` identity
- Claude Code の exclusive `actas` と、Codex の send-side-only `actas` の差
- Codex 宛て durable message の identity-targeted direct delivery
- official `api.sh`, `send.sh`, `join.sh`, `delivery.sh`
- JSONL output
- opaque string message IDs
- summary + artifact reference handoff pattern
- protocol-level stop conditions
- short delay between PTY text and Enter

Gateway は AGMSG の SQLite schema を直接利用しません。

## Tailscale

- Serve: https://tailscale.com/kb/1242/tailscale-serve
- Funnel: https://tailscale.com/kb/1223/funnel
- Access controls: https://tailscale.com/kb/1018/acls

利用した方針:

- loopback service を `tailscale serve --bg` で tailnet 内へ公開
- public internet exposure になる Funnel は不使用

## Mosh

- Repository: https://github.com/mobile-shell/mosh
- Mosh server manual: https://github.com/mobile-shell/mosh/blob/master/man/mosh-server.1
- Blink iOS fork: https://github.com/blinksh/mosh
- Apple XCFramework builder: https://github.com/blinksh/mosh-apple
- Pinned binary release: `1.4.0+blink-18.4.5`
- Reviewed Blink Mosh source commit: `3640d36678dc415ba24f03d7f6fb20a0dac1fa6b`
- Reviewed mosh-apple commit: `eefe690651d68aab15df9960a143b7951f3c4121`

利用した仕様:

- `mosh-server new -p PORT[:PORT2] -- command...`
- `MOSH CONNECT <port> <key>` bootstrap line
- UDP roaming / prediction
- iOS `mosh_main` C bridge
- encoded-state callback
- `TERM=xterm-256color` と UTF-8 locale
- GPLv3-or-later licensing

`Vendor/MoshBinaryPackage/Package.swift` は upstream release URL と SHA-256 checksum を pin しています。

## SwiftTerm

- Repository: https://github.com/migueldeicaza/SwiftTerm
- Pinned revision: `f02e34bb7d564408a0f48d5c73d382ddb7d04dc0` (2026-07-15)
- License: MIT

利用した機能:

- iOS `TerminalView`
- VT100 / Xterm state machine
- ANSI / 256 color / True Color
- Unicode、grapheme cluster、emoji、box drawing
- mouse reporting、OSC 8 / implicit links、clipboard、resize

## Apple platform

- SwiftUI: https://developer.apple.com/documentation/swiftui
- Keychain Services: https://developer.apple.com/documentation/security/keychain-services
- LocalAuthentication: https://developer.apple.com/documentation/localauthentication
- URLSession: https://developer.apple.com/documentation/foundation/urlsession
- Privacy manifest: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files

利用した方針:

- native SwiftUI app lifecycle
- bearer token の ThisDeviceOnly Keychain 保存
- Face ID / device passcode gate
- URLSession HTTPS / SSE client
- Network.framework `NWPathMonitor`
- privacy manifest 同梱
