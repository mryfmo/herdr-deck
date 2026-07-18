# Mosh Transport

## 目的

HerdDeck の Mosh 実装は、iPhone / iPad が Wi-Fi と携帯網を行き来する状況で、Herdr の interactive terminal を切断しにくくするためのものです。

Mosh は control plane ではありません。次の責務分離を維持します。

| Surface | Transport |
|---|---|
| Agent state / Mission / AGMSG / health | HTTPS + SSE |
| Rich output | HTTPS |
| Raw output | HTTPS |
| Terminal on Wi-Fi | HTTPS pane I/O |
| Terminal on cellular | Mosh UDP |

## 接続フロー

```text
HerdDeck Terminal
  │
  ├─ POST /v1/mosh/sessions
  │    Authorization: Bearer ...
  │    paneId / rows / columns / predictionMode
  │
  ▼
Gateway MoshSessionManager
  ├─ Herdr snapshot で pane の存在を確認
  ├─ allowlisted mosh-server / herdr executable
  ├─ mosh-server new -p <range> -c 256 --
  │    herdr agent attach <paneId> --takeover
  ├─ `MOSH CONNECT <port> <key>` をparse
  └─ no-store HTTPS responseでdescriptorを返す
       │
       ▼
Embedded iOS Mosh client
  └─ Tailscale host:UDP portへ接続
```

Gateway が Mac 上で `mosh-server` を直接起動するため、iOS app に SSH private key や Mac login password を保存しません。Mosh の初期 bootstrap authorization は既存の Gateway bearer token と Tailscale device access に集約されます。

## Network policy

`NetworkPathService` は `NWPathMonitor` を使って route を分類します。

1. `.cellular` が使われていれば cellular
2. `.wifi` が使われていれば Wi-Fi
3. Tailscale packet tunnel 等で `.other` に見える場合、`isExpensive` を cellular の保守的 fallback とする
4. Settings で `Gateway only` / `Prefer Mosh` を明示 override 可能

Automatic policy:

```text
cellularへ移行 → Moshへ即時切替
Wi-Fiへ復帰   → 0〜120秒のhysteresis後にGatewayへ戻す
offline       → Gateway routeへ即時再計算し、network復帰時に再接続
```

Wi-Fi 復帰 delay の初期値は 45 秒です。駅や電車内などで interface が短時間に揺れる場合の再 bootstrap を抑制します。

## Mosh session descriptor

Gateway response:

```json
{
  "session": {
    "id": "uuid",
    "paneId": "w1:p2",
    "host": "100.64.0.10",
    "port": 60001,
    "key": "one-time-mosh-key",
    "predictionMode": "adaptive",
    "createdAt": "2026-07-17T00:00:00.000Z",
    "networkTimeoutSeconds": 604800,
    "serverPid": 12345
  }
}
```

`key` は response 以外に保存しません。Gateway の session map と audit log は key を除去します。HTTP response は `Cache-Control: no-store` です。

## Mac configuration

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

### advertiseHost

iPhone / iPad から到達できる Mac の Tailscale IPv4 または MagicDNS name を指定します。UDP path の問題を切り分けやすいため、最初は Tailscale IPv4 を推奨します。

### bindAddress

Mac の Tailscale IPv4 を指定すると、mosh-server の UDP listener を tailnet interface に限定できます。空の場合は mosh-server に interface 選択を任せます。

### portRange

既定は `60000:61000` です。狭い範囲へ変更する場合は同時 session 数と stale server の残存時間を考慮してください。

`mosh-server` は `MOSH CONNECT` を出した後に detach するため、Gateway の bootstrap timeout で wrapper process を kill しても detached server へ届かない場合があります。その場合は Mosh 自身の no-client abort / network timeout が回収を担当します。

### takeover

`true` の場合、`herdr agent attach <pane> --takeover` を使います。同じ pane に既存 direct-attach client がある場合、その input ownership を引き継ぐため、複数端末で同時操作するときは `false` を検討してください。

## Tailnet ACL / firewall

公開 router の port forward は不要です。

許可する必要がある経路は次だけです。

```text
iPhone / iPad tailnet identity
  → Mac Tailscale IP
  → UDP configured Mosh range
```

Gateway HTTPS は Tailscale Serve が扱います。Mosh UDP は Serve を経由しないため、tailnet grants / ACL と macOS firewall の両方を確認してください。

## iOS embedded engine

`iOS/HerdDeckMosh/HerdMoshSession.mm` は pinned Mosh XCFramework の `mosh_main` C bridge を pipe ベースで包みます。

- SwiftTerm からの raw bytesを Mosh input pipeへ送る
- Mosh output pipeを SwiftTermへfeed
- terminal resizeを `winsize` へ反映
- Mosh state callbackを diskへ書かず memory上だけで受け取る
- stop時は Mosh escape sequenceで終了
- `TERM=xterm-256color`、`COLORTERM=truecolor`、UTF-8 localeを設定

依存物は `Vendor/MoshBinaryPackage/Package.swift` で version / checksum を pin しています。

## Failure handling

| Failure | Behavior |
|---|---|
| Mosh disabled | Gateway terminalへfallback |
| embedded clientなし | Gateway terminalへfallback |
| pane不存在 | bootstrapを404で拒否 |
| mosh-server起動失敗 | UIにerror、bounded backoffでretry |
| UDP blocked | Mosh connecting状態、retry / manual Gateway override |
| network interface change | route taskをcancelして再評価 |
| app background / process termination | Herdr paneはMac上で継続、foreground復帰後に再bootstrap |

Mosh の接続が失敗しても agent process や Herdr pane は終了しません。

## Build modes

Full:

```bash
./scripts/build-mosh-ios.sh
./scripts/generate-xcode-project.sh
```

Lite:

```bash
./scripts/generate-xcode-project.sh --lite
```

Lite build は Mosh binary / Objective-C++ wrapper を target に含めず、Terminal transport を Gateway に限定します。

## License

Mosh は GNU GPL v3 or later です。HerdDeck の full linked build を配布する場合は、combined binary の GPL obligations を満たす前提で扱ってください。個人 / 社内 sideload と第三者への App Store 配布では検討事項が異なるため、配布前にライセンス確認が必要です。
