# Changelog

## 0.2.0 — 2026-07-17

- split the product into an HTTPS/SSE control plane and an independent interactive terminal transport
- added automatic Wi-Fi / cellular path detection with configurable hysteresis
- added authenticated Mosh session brokering on the Mac Gateway for cellular terminal roaming
- added an optional embedded iOS Mosh engine using pinned XCFrameworks, plus a Mosh-free Lite build
- added revision-pinned SwiftTerm-backed VT100/Xterm rendering with ANSI color, Japanese, Unicode grapheme clusters, emoji, links, mouse input, and external keyboard support
- added Rich / Terminal / Raw presentation modes without coupling rendering to the selected transport
- added Markdown headings, lists, quotes, code blocks, tables, copy actions, and rich AGMSG message rendering
- kept Rich, Raw, Mission, agent state, and AGMSG traffic on the authenticated Tailscale HTTPS control plane
- added camelCase public HTTP request encoding while keeping Herdr snake_case isolated to the Unix-socket adapter
- added bounded Mosh bootstrap parsing, pane validation, no-store responses, key redaction, and Mosh diagnostics
- expanded automated Gateway coverage to 23 tests and added Unicode, emoji, transport, parser, and JSON-coding tests
- added Mosh, rendering, licensing, security, build, and verification documentation

## 0.1.0 — 2026-07-12

- SwiftUI iPhone / iPad client
- TUI/GUI hybrid agent console
- Herdr snapshot + event subscription adapter
- loopback-only Node.js Gateway
- reusable Claude Code / Codex profiles
- Claude Fable high orchestrator profile
- Codex GPT-5.6-Sol high executor profile
- AGMSG teams, members, messages, sending
- mission orchestration and delivery assist
- mission-scoped AGMSG identities for concurrent reuse of the same profiles
- targeted Codex delivery with restart-safe opaque message cursors
- durable AGMSG mission completion signal
- Tailscale Serve setup
- Keychain, biometric lock, token authentication, rate limits, RPC allowlist
- dedicated bounded terminal-input path; generic RPC cannot bypass write limits
- SSE reconnect backoff and internal mission-control recipient protection
- launchd installer, diagnostics, QR pairing, token rotation
- Gateway test suite and source validation
