# Third-Party Notices

HerdDeck itself is licensed under the MIT License in [LICENSE](LICENSE).

This source bundle can produce two build variants:

- **Full build:** links SwiftTerm, Mosh, and Protobuf C++ binary targets
- **Lite build:** links SwiftTerm only; no Mosh / Protobuf binary target

## SwiftTerm

- Project: `migueldeicaza/SwiftTerm`
- Pinned revision: `f02e34bb7d564408a0f48d5c73d382ddb7d04dc0`
- License: MIT
- Source: https://github.com/migueldeicaza/SwiftTerm

The SwiftTerm license text is included at [LICENSES/SwiftTerm-MIT.txt](LICENSES/SwiftTerm-MIT.txt). The upstream package remains the authoritative source.

## Mosh

- Project: Mosh, the mobile shell
- iOS source fork: `blinksh/mosh`
- Binary builder: `blinksh/mosh-apple`
- Pinned binary release: `1.4.0+blink-18.4.5`
- License: GNU General Public License version 3 or later, with the upstream OpenSSL linking exception where applicable
- Source: https://github.com/mobile-shell/mosh
- iOS source: https://github.com/blinksh/mosh
- Binary builder: https://github.com/blinksh/mosh-apple

A copy of GPL version 3 is included at [LICENSES/GPL-3.0.txt](LICENSES/GPL-3.0.txt).

The full HerdDeck target links Mosh into the application. Treat distribution of that linked application as a GPLv3-or-later distribution and provide complete corresponding source, build instructions, notices, and any other required materials. App Store distribution can raise additional license compatibility questions and should be reviewed before publication. This notice is not legal advice.

## Protocol Buffers C++

- Upstream project: Protocol Buffers
- Binary builder: `blinksh/protobuf-apple`
- Pinned framework release: `v3.21.1` package URL used by Blink
- Builder input: CocoaPods `Protobuf-C++`
- Upstream license: BSD-3-Clause
- Source: https://github.com/protocolbuffers/protobuf
- Binary builder: https://github.com/blinksh/protobuf-apple

A reference BSD license text is included at [LICENSES/BSD-3-Clause.txt](LICENSES/BSD-3-Clause.txt). Preserve the exact copyright and license notices shipped with the resolved upstream artifact when redistributing a binary.

## Apple frameworks

HerdDeck uses Apple platform frameworks including SwiftUI, UIKit, Foundation, Network, Security, LocalAuthentication, and UserNotifications under the terms applicable to the Apple SDK and platform.

## Downloaded binary artifacts

No third-party XCFramework binary is embedded in this source ZIP. Xcode / Swift Package Manager downloads the pinned artifacts declared in `Vendor/MoshBinaryPackage/Package.swift` during a full build. Before redistributing an archive, inspect the resolved artifact notices and retain all required license files.