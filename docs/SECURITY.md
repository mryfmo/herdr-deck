# Security Model

## 1. 重要な前提

HerdDeck は Herdr pane に文字列と制御キーを送れます。認証済みクライアントは、その Mac ユーザーが shell で実行できる操作を間接的に行えるため、通常のダッシュボードより高い権限を持ちます。

この設計は次を trust boundary とします。

- iPhone と Mac は同一ユーザーが管理
- tailnet と端末アカウントが侵害されていない
- Herdr、Claude Code、Codex、AGMSG のローカルインストールを信頼
- Mac ユーザー権限以上の privilege escalation は提供しない

## 2. 実装済みコントロール

### Network exposure

- Gateway は `127.0.0.1` または `::1` だけへ bind
- 非 loopback bind は config load 時に拒否
- tailnet 公開は `tailscale serve --bg http://127.0.0.1:<port>`
- HTTPS 以外の endpoint は iOS 側で拒否。loopback development のみ HTTP を許可
- Tailscale Funnel は使用しない
- Mosh UDP は `advertiseHost` / `bindAddress` を Mac の Tailscale address に限定可能
- Mosh UDP range は tailnet identity と対象 Mac の間だけ許可し、public router へ forward しない

Tailscale 管理画面で、Mac への到達元を本人の device / user に限定する ACL または grants を設定してください。

### Authentication

- 256-bit 相当のランダム bearer token
- token file mode `0600`
- constant-time comparison
- token fingerprint のみ health/log に表示
- iOS は `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` で Keychain 保存
- Face ID / Touch ID / device passcode による app unlock
- Mosh bootstrap は同じ bearer-authenticated HTTPS API を使用
- Mosh session key は no-store response にだけ含め、Gateway audit / mission store へ保存しない

token 漏えい時:

```bash
./scripts/rotate-token.sh
./scripts/pairing-qr.sh
```

rotation 後はすべての iOS device で再ペアリングが必要です。

### Authorization and command scope

- iOS は任意の executable / argv を送信できない
- agent launch は Mac 側の profile allowlist から選択
- `projectPath` は realpath 化後に `projectRoots` と照合
- raw Herdr RPC は allowlist 制
- server stop、plugin install、integration install、lifecycle authority report などを mobile RPC から除外
- terminal input は 64 KiB、AGMSG body は 32 KiB に制限
- request body limit と sliding-window rate limit

### Agent safety defaults

- Codex は `workspace-write`
- AGMSG skill path だけを追加 writable root として明示
- dangerous sandbox / approval bypass flag を含めない
- mission prompt は scope expansion、credential 操作、approval bypass を禁止
- 1 mission の executor 上限は 4
- max coordination rounds は 1〜30

### Audit

監査ログ:

```text
~/.local/state/herddeck/audit.jsonl
```

記録するもの:

- operation 名
- timestamp
- mission / pane / profile ID
- text byte count
- special key 名
- success / failure metadata

記録しないもの:

- bearer token
- terminal input 本文
- AGMSG message 本文
- model credential
- Mosh session key

ただし error message や file path は含まれる可能性があります。ログもユーザー private data として扱ってください。

## 3. 推奨運用

- Mac の FileVault と強いログイン password を有効化
- iPhone の passcode、Find My、Stolen Device Protection を有効化
- tailnet へ第三者を安易に追加しない
- Tailscale device approval / key expiry policy を適切に設定
- `projectRoots` を `$HOME` 全体や `/` にしない
- Mac の管理者アカウントではなく開発用標準ユーザーで運用を検討
- repository の backup と clean working tree を保つ
- production secret を agent が読める working tree に置かない
- Gateway token の QR を保存・共有しない
- Gateway / Herdr / CLI を更新した後は `./scripts/doctor.sh` と test を実行

## 4. 残存リスク

### Tailnet member compromise

Bearer token と HTTPS があっても、token を取得した tailnet member は Gateway を操作できます。ネットワーク identity と app token の両方を保護する必要があります。

### Prompt injection and agent autonomy

repository、issue、Web、dependency の内容が agent prompt へ混入し、意図しない操作を誘発する可能性があります。sandbox、approval、review、test、scope 分割を defense-in-depth として維持してください。

### Terminal rendering

Terminal mode は SwiftTerm で ANSI / OSC / terminal state を解釈します。そのため plain-text 表示より terminal escape surface が広がります。以下で境界を設けています。

- terminal output は WebView / JavaScript ではなく native terminal emulator で処理
- link activation は `http` / `https` scheme だけを許可
- clipboard copy は明示操作時のみ
- Rich mode は arbitrary HTML を実行しない
- Raw mode は ANSI を解釈しない
- trusted source はユーザー自身の Mac 上の Herdr pane という前提

untrusted repository content が agent terminal へ escape sequence を出力する可能性は残ります。疑わしい出力は Raw mode で確認してください。

### Mosh direct attach ownership

既定の `takeover: true` は、同じ Herdr agent pane へ既に direct attach している client から input ownership を引き継ぎます。複数人・複数端末で同時操作する環境では意図しない操作競合になり得るため、single-user tailnet を前提とし、必要なら `takeover: false` にします。

Mosh server は Mac user 権限で `herdr agent attach` を実行します。Gateway token を持つ client が任意 command を指定することはできず、pane ID は current snapshot 内の存在を検証します。

### AGMSG control identity

Mission completion は orchestrator から mission 固有 control recipient への明示メッセージを信頼します。Gateway は orchestrator identity も Mission 固有名へ展開しますが、team 内の別 process がその identity を不正に取得できる運用では誤完了の可能性があります。AGMSG role exclusivity、Mac のユーザー境界、Gateway token を維持してください。

### Background notification gap

APNs relay がないため、iOS が suspend された状態での即時通知は保証しません。agent 自体の実行には影響しません。

### Third-party licensing / distribution

Full build は GPLv3-or-later の Mosh と link します。これは runtime security ではありませんが、配布経路に影響する operational risk です。第三者配布時は corresponding source と notice を用意し、App Store 条件との整合性を法務確認してください。Mosh を link しない Lite build を選択できます。

## 5. インシデント時の手順

1. `tailscale serve reset` または Serve 設定を解除
2. `launchctl bootout gui/$UID/com.herddeck.gateway`
3. `./scripts/rotate-token.sh`
4. audit log と Gateway error log を確認
5. tailnet device / user を revoke
6. Claude / Codex / Git credential を必要に応じて revoke
7. repository diff と実行履歴を確認
8. clean environment で再構築
