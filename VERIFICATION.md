# Build Verification

Verification date: **2026-07-17**

## Automated checks completed

The source bundle was validated in the available Linux build environment with:

```bash
make validate
```

Results:

- Node.js Gateway syntax checks: passed
- Gateway tests: **23 passed, 0 failed**
- Swift source parse (`swiftc -frontend -parse`): passed for every app and XCTest source file
- Pure Swift model/parser/network-coding typecheck: passed
- Swift format lint: passed with no diagnostics
- shell script syntax (`bash -n`): passed
- JSON parse: passed
- privacy manifest plist parse: passed
- XcodeGen YAML parse: passed for full, compatibility, and Lite project specifications
- local Swift package manifest evaluation: passed for the pinned Mosh / Protobuf binary package
- generated runtime secret check: `gateway/config.json` is absent
- signing-secret check: no `.pem`, `.p12`, or `.mobileprovision` files are included

Validation environment:

```text
Node.js 22.16.0
Swift 6.2.1 frontend
Python 3.13.5
Linux x86_64
```

## What the automated tests cover

The Gateway suite covers:

- use of AGMSG's documented script surface instead of direct SQLite access
- bearer-token comparison and rate limiting
- Herdr snapshot, input, protocol-error, and event-subscription behavior
- Mosh port validation, capabilities, pane validation, bootstrap parsing, and audit-key redaction
- Mission prompt construction, scoped identities, Codex delivery assist, durable storage, and completion reconciliation

The Swift XCTest sources cover:

- Herdr status forward compatibility
- AGMSG wire-field mapping
- Japanese and emoji terminal input
- mixed UTF-8 and control-sequence mapping
- Rich Markdown block parsing with Japanese and emoji
- terminal preference persistence
- camelCase public Gateway request encoding

## Checks that require the target Mac

This environment does not provide macOS, Xcode, an iOS Simulator/runtime, Apple code signing, Tailscale, a live Herdr socket, `mosh-server`, Claude Code, Codex, or AGMSG. Therefore the following have **not** been claimed as completed here:

- final Objective-C++/XCFramework link of the embedded Mosh target
- iOS Simulator or physical-device build
- signed IPA or App Store archive creation
- Wi-Fi ↔ cellular handoff on a real iPhone
- live Mosh UDP connectivity over the user's tailnet
- live Claude/Codex/AGMSG Mission execution

Run on the target Mac:

```bash
cp gateway/config.example.json gateway/config.json
$EDITOR gateway/config.json

./scripts/bootstrap-mac.sh
./scripts/bootstrap-mosh-mac.sh
./scripts/doctor.sh
./scripts/build-mosh-ios.sh
./scripts/generate-xcode-project.sh

xcodebuild \
  -project HerdDeck.xcodeproj \
  -scheme HerdDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

For a build that does not link GPL Mosh:

```bash
./scripts/generate-xcode-project.sh --lite
xcodebuild \
  -project HerdDeckLite.xcodeproj \
  -scheme HerdDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

## Recommended physical-device acceptance test

1. Start Herdr and confirm the Claude and Codex integrations.
2. Start the Gateway locally and verify authenticated `/v1/health` and `/v1/mosh/capabilities`.
3. Publish only the HTTPS Gateway with Tailscale Serve; do not use Funnel.
4. Confirm the configured Mosh UDP range is reachable only from the intended tailnet identities.
5. Pair an iPhone and verify device authentication and Keychain persistence.
6. On Wi-Fi, confirm Terminal uses Gateway and Rich / Raw render Japanese, Markdown, links, tables, code, and emoji.
7. Move to cellular and confirm only Terminal switches to Mosh while Mission, state, Rich / Raw, and AGMSG remain on HTTPS.
8. Exercise Claude Code and Codex TUIs, alternate-screen apps, resize, external keyboard input, and composite emoji.
9. Start a disposable Mission and verify AGMSG delivery, Mission-scoped identities, restart recovery, and durable completion.
10. Review audit logs and rotate the pairing token after any recorded QR demonstration.

## Distribution status

This bundle is a **source-ready 0.2.0 implementation**. It does not contain a signed IPA, provisioning profiles, private keys, runtime bearer tokens, or production APNs infrastructure.
