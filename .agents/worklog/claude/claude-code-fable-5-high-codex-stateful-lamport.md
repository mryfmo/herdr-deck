# agmsg orchestration setup: Claude Code (fable-5 high) orchestrator + Codex (gpt-5.6-sol high) worker

## Context

HerdDeck-0.2.0 で、Claude Code (fable-5 high) をオーケストレータ、Codex (gpt-5.6-sol high) を自律ワーカーとして agmsg で連携させ、実タスクで動作確認する。

環境調査の結果、セットアップは半分完了している:

- 配送フックは両方設定済み: claude-code は `mode: both`(`.claude/settings.local.json` に SessionStart/SessionEnd/Stop)、codex は `mode: turn`(`.codex/hooks.json` に Stop → `check-inbox.sh`、`~/.codex/config.toml` で trusted 済み)。配送モードの変更は不要(watcher を殺すリスクを避ける)。
- Codex CLI 0.144.5、`model = "gpt-5.6-sol"`, `model_reasoning_effort = "high"` — 要求どおり設定済み。
- **未完了**: HerdDeck 用の agmsg チーム/identity が未登録(`whoami.sh` が suggest のみ返す)。`.orchestration/` も未作成。actas claim・watch monitor も未起動。
- herdr w12:p3 に idle の `codex-worker-w12`(cwd = HerdDeck-0.2.0)が存在。
- ライブ store: `~/.agents/skills/agmsg/db/messages.db`(ワーカー 1 体なのでデフォルト store を共用。`AGMSG_STORAGE_PATH` 分離は複数ワーカー時のみ)。
- HerdDeck は git repo ではなく `require-crit-review` target も無い → crit ガードは対象外(受入判断は adversarial review で担保)。

ユーザー回答: 検証は実タスクで(make check 実行+証跡)。herdr 実作業前にまず動作できる環境の構築を優先。

## 命名(既存 8 チームの全 identity と衝突なしを確認済み)

- チーム: `herddeck-project`
- オーケストレータ: `claude-fable5high-herddeck` (type=claude-code)
- ワーカー: `codex-gpt56solhigh-herddeck` (type=codex)
- project は必ず実パス `/Users/mryfmo/Workspace/HerdDeck-0.2.0`($HOME 登録は禁止)
- session_id: `087e586f-2801-4656-addb-a9cbc0caa9d7`

スクリプトはすべて `~/.agents/skills/agmsg/scripts/` 配下を使用。

## Phase A — 環境構築(オーケストレータ側 control-plane)

1. `.orchestration/` ワークスペース作成: `tasks/ reports/ validation/ acceptance/ sandboxes/ learning/ agmsg/`(skill 規定レイアウト。autoskill/skills 系は今回のタスクでは不要なので作らない — 必要になった時に作る)
2. identity 登録:
   - `join.sh herddeck-project claude-fable5high-herddeck claude-code /Users/mryfmo/Workspace/HerdDeck-0.2.0`
   - `join.sh herddeck-project codex-gpt56solhigh-herddeck codex /Users/mryfmo/Workspace/HerdDeck-0.2.0`
   - `whoami.sh /Users/mryfmo/Workspace/HerdDeck-0.2.0` で両 type が解決されることを確認
3. 配送確認: `delivery.sh status claude-code <repo>`(both のはず)/ `delivery.sh status codex <repo>`(turn のはず)。both/turn 未満なら該当のみ `delivery.sh set` で補正(現状は不要見込み)
4. 排他 claim: `actas-claim.sh /Users/mryfmo/Workspace/HerdDeck-0.2.0 claude-code claude-fable5high-herddeck 087e586f-...` → `status=ok` を確認
5. 常駐 monitor: Monitor ツールで `watch.sh 087e586f-... /Users/mryfmo/Workspace/HerdDeck-0.2.0 claude-code` を起動(ワーカーからの RESULT/PONG はこの monitor / turn 配送でのみ検知。pane 読み取りやポーリング sleep は使わない)

## Phase B — ワーカー起動(herdr pane)

6. `herdr agent list` で w12:p3 の `codex-worker-w12`(idle, cwd=HerdDeck)を再確認し、この既存 pane にワーカープロンプトを注入 + CR で submit(テキストだけでは未送信になる点に注意)。pane が消えていた場合のみ新規 pane を作成
7. ワーカープロンプト内容: 「あなたは agmsg ワーカー `codex-gpt56solhigh-herddeck`(team `herddeck-project`)。AGMSG-TASK v1 を受信したら task_file を読み、allowed_files 境界と forbidden_actions を厳守し、artifacts を指定パスに書き、AGMSG-RESULT v1 で報告。AGMSG-PING には AGMSG-PONG で応答」+ inbox 確認コマンド(`inbox.sh herddeck-project codex-gpt56solhigh-herddeck`)

## Phase C — 疎通確認(liveness)

8. `send.sh herddeck-project claude-fable5high-herddeck codex-gpt56solhigh-herddeck "AGMSG-PING v1 task_id=T000 reason=liveness-check"` を送信し、monitor / turn 配送経由で `AGMSG-PONG v1 ... status=alive` の受信を確認。応答が無ければ pane に generic wake(内容はバスのみ)を 1 回注入して再待機

## Phase D — 実タスクで E2E 検証

9. タスクファイル `.orchestration/tasks/T001.task.md` を作成:
   - objective: `make check` を実行し、リポジトリ健全性レポートを作成
   - allowed_files: `.orchestration/reports/T001.report.md`, `.orchestration/validation/T001.validation.txt`, `.orchestration/sandboxes/T001.sandbox.md`, `.orchestration/learning/T001.learning.md`, `.orchestration/autoskill/T001.autoskill.md` のみ(リポジトリ本体は読み取り専用)
   - forbidden_actions: 依存追加; リポジトリ本体ファイルの編集; git 操作; ネットワーク実行; スキル昇格
   - validation: `make check` の生出力を validation ファイルへ
   - max_turns=10, done_signal=AGMSG-RESULT
10. `AGMSG-TASK v1 task_id=T001 repo=... task_file=... expected_*=(上記パス) max_turns=10 note=act-as-worker-repo-check` を send.sh で送信
11. AGMSG-RESULT 受信後、**adversarial review**: task_file と全 artifact を読み、validation の `make check` 出力をオーケストレータ側でも独立に `make check` を再実行して照合(サンプリングでなく全 artifact を検分)。正しさ・報告漏れ・境界違反(allowed_files 外の変更が無いか)を確認
12. `AGMSG-ACCEPTANCE v1 task_id=T001 status=accepted reason=... next_action=none` を送信(不備があれば status=revise + 狭い reason/next_action)
13. 受入記録を `.orchestration/acceptance/T001.acceptance.md` に保存し、`history.sh herddeck-project` の関連ログを `.orchestration/agmsg/T001.history.txt` に書き出し

## 変更されるファイル

- 新規: `.orchestration/` 配下(tasks/reports/validation/acceptance/sandboxes/learning/agmsg の各ファイル)
- 変更: `~/.agents/skills/agmsg/teams/herddeck-project/config.json`(join.sh が作成)、agmsg run/lock ファイル(actas-claim/watch が管理)
- リポジトリ本体のコードは一切変更しない

## 検証方法(完了条件)

- `whoami.sh` が HerdDeck の両 type に対し登録済み identity を返す
- `actas-claim.sh` が `status=ok`
- PING→PONG がバス経由で往復(pane 読み取りに依らない)
- T001 の RESULT が monitor/turn 配送で届き、全 artifact が指定パスに存在
- `make check` の worker 出力とオーケストレータ再実行結果が一致
- ACCEPTANCE 送信済み、`history.sh` に TASK/PING/PONG/RESULT/ACCEPTANCE の一連が記録されている

## 注意点

- 配送モードは現状維持(both/turn 済み)。`delivery.sh set` の再実行は watcher を殺すため原則やらない
- ワーカー完了検知は AGMSG-RESULT のみ。pane/画面の読み取りや sleep ポーリングでの完了推定は禁止
- ワーカー待ちの間はアイドルにせず、受入レビュー準備(独立 `make check` 実行など)を進める
