# Agent Orchestration

## 1. 役割

### Orchestrator: Claude Code Fable 5 / high

責務:

- repository と目的の理解
- bounded plan の作成
- executor への task packet 送信
- ownership conflict の回避
- executor 成果物の検証
- test、review、integration
- 最終的な completion signal

デフォルト起動:

```bash
claude --model fable --effort high --name herddeck-orchestrator
```

### Executor: Codex GPT-5.6-Sol / high

責務:

- AGMSG で task を取得し ACK
- workspace-write sandbox 内で自律実装
- focused test と diff review
- BLOCKED / REVIEW / DONE の報告
- artifact path や commit SHA による引き継ぎ

デフォルト起動:

```bash
codex \
  --model gpt-5.6-sol \
  -c 'model_reasoning_effort="high"' \
  --sandbox workspace-write \
  --add-dir "$HOME/.agents/skills/agmsg"
```

## 2. Identity mapping

1 mission につき、次の identity を使います。

| Role | Herdr name | AGMSG name |
|---|---|---|
| orchestrator | `hd-<short-id>-orch` | `<profile agmsgName>-<short-id>`、例 `orchestrator-a1b2c3d4` |
| executor 1 | `hd-<short-id>-exec1` | `<profile agmsgName>-<short-id>-1`、例 `builder-a1b2c3d4-1` |
| control | Herdr pane なし | `herddeck-<short-id>` |

profile の `agmsgName` は再利用可能な基底名です。同じ基底名を複数 profile へ設定することは Gateway 起動時に拒否し、1 mission 内の executor profile 重複も拒否します。実際の AGMSG identity は Mission ごとに一意化されるため、同じ profile を複数の active Mission で同時利用できます。

Mission identity は team roster に残り、履歴の再生と監査に使えます。長期運用で roster を整理する場合は、AGMSG の `drop` 操作を Mac 側から明示的に実行してください。

## 3. 起動シーケンス

1. iOS が mission spec を Gateway へ送る
2. Gateway が `projectPath` を realpath 化し `projectRoots` と照合
3. orchestrator、executor、control recipient を AGMSG team へ join
4. 専用 Herdr workspace / tab を作る
5. Claude Code を起動し、orchestration prompt を初期入力として渡す
6. Codex executor を 1〜4 個起動
7. bootstrap shell pane を閉じる
8. delivery assist を開始
9. snapshot / AGMSG を監視

配送済み message ID は Mission store に identity ごとの cursor として保存します。Gateway 再起動後は `running` Mission の delivery assist を再開し、少なくとも一度の配送になるよう未記録 ID を再処理します。cursor 永続化直前に process が落ちた場合は同じ message が再注入される可能性があるため、executor の task packet は冪等性を意識してください。

## 4. Task packet protocol

Orchestrator には、各委譲に以下を含めるよう指示しています。

- task の目的
- acceptance criteria
- relevant paths
- writable scope
- constraints
- expected artifact、report path、commit SHA

Executor の応答語彙:

```text
ACK <task summary>
BLOCKED <smallest actionable reason/question>
REVIEW <artifact path or commit SHA>
DONE <summary; tests; paths/commit>
```

AGMSG は短い durable message transport として扱います。長い調査結果、diff、ログ、生成物をメッセージ本文へ埋めず、repository 内のファイルや commit を参照します。

## 5. Delivery assist

AGMSG 自体は durable log です。interactive TUI が受信を確認するには agent 側 skill を呼び出す必要がある場合があります。

Gateway は新しい inbound message ID を検出すると、対象 pane へ runtime 別の配送を行います。

```text
Claude Code: /agmsg を送って専用 inbox monitor / skill から取得
Codex:       Gateway が対象 identity の AGMSG message を読み、明示 envelope として対象 pane へ直接注入
```

現行 AGMSG では Codex の `actas` は send-side override で、receive-side identity は同じようには絞り込まれません。そのため複数の Mission identity が同じ project に存在しても誤配送しないよう、Gateway が公式 `api.sh` で宛先を限定して読み、最大 8 件・約 60 KiB の bounded batch にして Codex pane へ渡します。返信は Codex の active `actas` identity から `$agmsg` を介して送ります。

どちらも本文と Enter を分け、短い delay を置いてから `Enter` を送ります。PTY/TUI が入力を取りこぼす確率を下げるためです。

既定では agent の idle 判定に依存せず delivery します。working 中の入力 queue を避けたい環境では、`deliveryAssist.onlyWhenAgentNotWorking` を `true` にできますが、画面検出に依存するため配送遅延が起こり得ます。

## 6. Completion protocol

Mission ごとに `herddeck-<short-id>` という control recipient を AGMSG team へ登録します。

最終検証後、orchestrator は次の prefix で control recipient へ送信します。

```text
MISSION_DONE <full-mission-id> | <summary; tests; artifact/commit>
```

人間入力が必要な場合は次を送るよう prompt しています。

```text
NEEDS_INPUT <full-mission-id> | <smallest actionable question>
```

`MISSION_DONE` は Gateway が永続 AGMSG log から検出し、Mission を `completed` にします。`NEEDS_INPUT` の専用 UI surface は roadmap 項目で、現状は Messages / Console から確認します。

## 7. Multi-executor rules

Gateway は 1 mission あたり最大 4 executor を許可します。

推奨分割:

- executor A: implementation
- executor B: tests / static analysis
- executor C: independent review
- executor D: docs / migration / release checks

同じ writable path を同時に複数 executor へ割り当てないことが重要です。AGMSG は transport であり、分散 lock や task lease を提供しません。ownership は orchestrator prompt とチーム規約で管理します。

## 8. Profile customization

`gateway/config.json` の `profiles` に profile を追加します。

```json
{
  "id": "codex-sol-reviewer",
  "displayName": "Sol Reviewer",
  "runtime": "codex",
  "role": "executor",
  "agmsgName": "reviewer",
  "modelLabel": "GPT-5.6 Sol",
  "effortLabel": "High",
  "argv": [
    "codex",
    "--model",
    "gpt-5.6-sol",
    "-c",
    "model_reasoning_effort=\"high\"",
    "--sandbox",
    "workspace-write",
    "--add-dir",
    "${HOME}/.agents/skills/agmsg"
  ],
  "env": {},
  "accent": "mint"
}
```

`env` は iOS API へ返されません。secret を profile env に置くより、Claude/Codex の標準 credential store を使ってください。
