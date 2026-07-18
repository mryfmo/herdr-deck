# HerdDeck Mosh Binary Package

This local Swift package is an integrity-pinned wrapper around the Blink-maintained binary artifacts used by Blink Shell's current Mosh stack.

Targets:

- `mosh` — Blink Mosh `1.4.0+blink-18.4.5`
- `Protobuf_C_` — Blink Protobuf framework release `v3.21.1`

`Package.swift` records the release URLs and SwiftPM SHA-256 checksums. The source ZIP does not contain the binaries; Xcode resolves them on the build Mac.

Resolve explicitly:

```bash
swift package resolve --package-path Vendor/MoshBinaryPackage
```

License notes:

- Mosh is GPLv3-or-later.
- Protocol Buffers is BSD-3-Clause upstream.
- See `../../THIRD_PARTY_NOTICES.md` before distributing a linked build.