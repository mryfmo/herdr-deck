# Roadmap

## 0.2 — Implemented in this bundle

- cellular-aware terminal routing
- embedded Mosh transport with Gateway bootstrap
- Wi-Fi return hysteresis and manual route override
- SwiftTerm VT100/Xterm renderer
- Rich / Terminal / Raw presentation
- Markdown headings, lists, quotes, fenced code, tables
- Unicode / Japanese / emoji display path
- Mosh capability diagnostics and pinned XCFramework package
- full / lite build separation

## 0.3 — Operational lifecycle

- Mission pause / resume / cancel / force-stop
- `NEEDS_INPUT` attention inbox
- Gateway restart後のactive delivery-assist job復元
- Mission detail timeline
- profile health validation と model catalog mismatch warning
- agent rename / focus / zoom のGUI control
- stale mosh-server discovery / cleanup UI

## 0.4 — Structured artifacts

- syntax-highlighted code renderer
- unified / side-by-side Git diff
- test result / coverage cards
- JSON / YAML tree viewer
- safe image / PDF preview
- Mermaid rendered in isolated non-script surface
- artifact path allowlist と download audit

## 0.5 — Notifications and background recovery

- APNs relay またはself-hosted notification broker
- blocked / done / failedのbackground notification
- notification actionからapprove / open console
- foreground復帰時のdeterministic Mosh resume
- per-team quiet hours

APNsを追加しても、terminal input credentialやMosh keyをcloud relayへ預けない設計を維持します。

## 0.6 — Accessibility and iPad

- VoiceOver向けterminal line navigation
- Dynamic terminal font size / zoom
- hardware keyboard shortcut map
- iPad multi-column workspace / mission / terminal layout
- pointer / trackpad optimization
- reduced-motion tuning

## Release hardening

- macOS + iOS CI
- Xcode build / test matrix
- real Herdr / Mosh / Tailscale E2E fixture
- protocol contract tests against pinned Herdr releases
- AGMSG compatibility fixtures
- dependency / secret / license scanning
- TestFlight distribution for Lite build
- GPL distribution review for full Mosh-linked build
- privacy manifest / App Store review
- threat-model review and penetration test