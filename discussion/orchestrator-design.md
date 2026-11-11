# 進行役（オーケストレーター）fable-orch の設計案 r1

> **採らなかった（2026-11-10）。** ユーザーは Fable を進行役にせず「煮詰まった時に啓示を与える」のと「私が任意に確認する時用」に使うと決めた。
> 採った形は `agents/fable-lab.md`・`fable-turn.sh`・README §1.2。この r1 のうち、議決権を持たせない（§5 Q1 (a)）・1手ごとに新しい会話・前後比較の関門は引き継いだ。

- 状態（r1 の当時）: **提案（未採用）**。2026-11-10 ユーザー依頼「Fable 5.2 をオーケストレーターとして導入したい。設計を組んでみて」に応えた claude-lab の案。
  分担と決め方（discussion/README.md §1・§3）を変えるのでユーザーが決める。採用までは README・CLAUDE.md・AGENTS.md・各席の指針は変えない。
- 書き方: 【事実】= ファイル・CLI・API 資料で確かめたこと、【推論】、【提案】を分ける。

## 0. 何を解くのか（今の形の弱いところ）

【事実】
- 今の流れは claude-lab が「書く・決める・記録する・codex の手を起動する」をすべて持つ（agents/claude-lab.md「この席がすること」、README §4）。
  codex-lab は 1手ごとに新しい会話で起動されるレビュー席（codex-turn.sh）。
- STATE.md の「更新」の行（281行目）が一行で数千字に膨らみ、「次の候補（未依頼）」が複数箇所に重複して積まれている。
- 事後承認待ちの項目が溜まっている（STATE.md 285行目「#1〜#17 の承認は未記入」）。.codex-turns のログは 490 件。

【推論】
- claude-lab は実装の文脈（コード・関門の出力）と全体の進行（優先順位・記録の整合・ユーザーに上げる束）を一つの会話で抱えており、
  後者がコンパクションのたびに薄くなる。STATE の肥大と候補の重複はその症状。
- 欠けているのは「もう一人の作業者」ではなく、**作業の境目でだけ呼ばれ、全体を見渡して次の一手を割り当てる役**。

## 1. 役割の定義

**fable-orch = 議決権を持たない進行役（chair）。** 作業を割り当て、境目で記録の整合を点検し、ユーザーに上げる束を作る。
理論・読み・実装の中身は決めない。

| する | しない |
|---|---|
| 作業の切り出しと割り当て（`[O]` 指令: 誰が・何を・入力・終了条件・effort・往復の上限） | 仕様・コード・Lean を書く（claude-lab のまま） |
| backlog の優先順位付け（理由つき）、「次の候補（未依頼）」の一本化 | 差分レビュー・I-R（codex-lab のまま。§4 の独立性） |
| 境目の監査: STATE・README の経緯・decisions-log・凍結ファイルの sha の突き合わせ | §3(2)(3) の合意に票を投じる（案 B を採らない限り） |
| 往復が 3 回で進まないときの検出と、§3「割れたとき」の手続きの発動を促す | bridge-protocol・アプリの db・artifact・git・削除・外部送信 |
| ユーザー向けの束（承認待ち・判断待ち・BP）の要約を `discussion/orch/user-queue.md` に | `phenomenal_claim` に触れる、層をまたぐ判断 |
| 1手の消費の見張り（§4.1）、増えたら原因を一行 | 予測の凍結・書き換え（凍結は実行する席が行う） |

【提案】書いてよい場所は `discussion/orch/` だけ（`plan.md`・`dispatch-log.md`・`audit-<日付>.md`・`user-queue.md`）。
STATE.md は段階 1 では claude-lab のまま。段階 2 で fable-orch に移すかを決める（§6）。

## 2. 配置（トポロジー）

案 A（中心に置く）: fable-orch が claude-lab と codex-lab の両方を 1手ずつ起動する。claude-lab も `claude -p` の 1手ずつになる。
案 B（境目に置く）: 内側の輪（S ↔ S-R、I ↔ I-R）は今のまま claude-lab が回す。fable-orch は**境目**でだけ呼ばれる。

【提案】**案 B から始める。** 理由: (1) 今の輪は S36〜S46 で回っており、壊す理由がない。(2) 元に戻すのが容易（呼ばなければ今と同じ）。
(3) Fable は単価が Opus 5.5 の 2 倍（$8/$40 対 $4/$20 per MTok、claude-api スキルの表 2026-11-03 時点）で、1手が長くなりやすい。毎通の中継に使うと高い。

```
            [USER] (yamaguchi)
                 ▲ user-queue.md（束で上げる）
                 │
   境目で呼ぶ ─▶ fable-orch ──[O 指令]──▶ claude-lab ◀──S/I──▶ codex-lab
   (bash fable-turn.sh)        ▲                    （内側の輪は今のまま）
                               └──[O-R 完了報告]────┘
```

**呼ぶ境目**（これ以外では呼ばない）:
1. 作業項目が閉じたとき（Codex の APPROVE と README の項番追記のあと）→ 次の `[O]` を出す
2. backlog が空、または「次の候補（未依頼）」が 3 件以上溜まったとき → 優先順位を付けて一本化
3. 同じ論点で 3 往復しても進まないとき（claude-lab か codex-lab が `[O?]` で呼ぶ）
4. `[USER]` が届いたとき → 承認・差し戻しの影響範囲（どの項番・どの仮定を戻すか）を洗い出す
5. 定期の監査（例: 作業項目 5 件ごと）→ STATE と記録の整合

## 3. 1手の走らせ方（`discussion/fable-turn.sh` の骨組み）

codex-turn.sh と同じ形にする: 1手ごとに新しい会話、受信箱の読み書きはスクリプト、モデルに agmsg とスキルを触らせない。

```bash
# 骨組み（未作成。採用が決まってから claude-lab が書き、--dry で確かめる）
EFFORT="${1:-medium}"          # 指令だけ: medium、優先順位の付け直し・監査: high
MSG="$(bash "$AG/inbox.sh" agency-lab fable-orch)"
snap > before                  # deepseek-turn.sh と同じ前後比較
printf '%s' "$PROMPT" | claude -p --model claude-fable-5-2 --effort "$EFFORT" \
  --output-format json --no-session-persistence \
  --permission-mode acceptEdits \
  --allowedTools "Read,Grep,Glob,Bash(sed -n:*),Bash(grep:*),Bash(shasum:*),Write(discussion/orch/**),Edit(discussion/orch/**)" \
  --setting-sources project > "$OUT"
snap > after                   # discussion/orch/ 以外が変わっていたら不合格で止める
# 最後の答えを [O ...] として宛先（claude-lab、必要なら codex-lab）に send.sh で送る
```

【事実】`claude -p` に `--model`・`--effort`・`--output-format`・`--allowedTools`・`--permission-mode`・`--no-session-persistence`・
`--setting-sources` があることを `claude --help` で確認した（2026-11-10）。`Write(path)` の形の絞り込みが効くかは未確認 → `--dry` で確かめる。

【提案】Fable の扱いの注意（claude-api スキル、Fable 5.2 の節）:
- 思考は常にオン。深さは effort だけで決める。Fable は `high` から始め、指令だけの手は `medium`／`low` も試す。`max` は使わない。
- 1手が長くなりうる → 打ち切りを置く（例 15 分）。返答の長さは指示で決める（effort では短くならない）。
- 指示を細かく書きすぎると質が落ちる、とある → プロンプトは役目・禁止・出力の形だけにし、手順を細かく書かない。
- 30 日のデータ保持が要る（ZDR では使えない）。Claude Code の会員の経路なら今の claude-lab と同じ扱い。API キーで使うなら組織の保持の設定を確かめる。

**1手の文脈**: STATE.md、受信箱、`discussion/orch/plan.md`、それと境目に応じて指定された範囲だけ。
1M の文脈があっても README・decisions-log を毎手通読しない（§4.1）。**通読してよいのは 5 の定期監査の手だけ**（ここが Fable を入れる価値の中心）。

## 4. 指令 `[O]` の書式

```
[O O<番号>] <題>
担当: claude-lab（S/I）| codex-lab（D の相手・S-R・I-R）| user（判断待ちに積む）
目的: 一文 / 根拠: backlog.md:行・README 項番・decisions-log #
入力: ファイル:行（各 30 行以内の抜粋を付ける）
終了条件: 検証できる文（例「S47 r? が APPROVE、凍結文の sha が freeze-*.txt にある」）
effort: low|medium|high   往復の上限: 3
優先した理由 / 後回しにしたもの（1行ずつ）
```

- claude-lab は `[O]` を受けたら今の流れ（§2）どおり進め、閉じたら `[O-R O<番号>] 完了/中止（理由）` を fable-orch に送る。
- **claude-lab は `[O]` を断れる**（理由を一行）。指令は割り当ての案であって、§3 の決め方を上書きしない。
- `[USER]` は常に `[O]` より優先。

## 5. 決め方との関係（ユーザーに決めてほしい点）

| 点 | 案 | 推奨 |
|---|---|---|
| Q1 議決権 | (a) なし（進行役のみ） (b) §3(2)(3) で三者の多数決 (c) 二者が割れたときだけの裁定役 | **(a)**。fable-orch と claude-lab は同じ Claude の系統で、判断の誤りが相関しうる。(b)(c) は codex-lab の独立した反対を数で消せてしまう。割れたら保守案、の今の規則のほうが安全 |
| Q2 配置 | 案 A／案 B | **案 B**（§2） |
| Q3 STATE.md の持ち主 | claude-lab のまま／fable-orch へ | 段階 1 は claude-lab のまま。fable-orch は `orch/plan.md` に「全体の計画」を持ち、STATE は「いまの一手」だけに痩せさせる |
| Q4 コスト | 上限の置き方 | 1手の消費を記録し、1 日の上限をユーザーが決める（数字はこちらで決めない） |

【推論】Q1 で (a) を採るなら、CLAUDE.md の「両者の合意」の文言は変えなくてよい。変わるのは README §1 の表に席を一つ足すこと、§4 に `[O]`・`[O-R]`・`[O?]` のタグを足すこと、
agents/fable-orch.md を新しく置くこと。

## 6. 導入の段階と、効いたかどうかの測り方

ラボの規律に合わせ、**試す前に予測と反証条件を書いて凍結する**。

- **段階 0（下準備、採用の決定のあと）**: agents/fable-orch.md・fable-turn.sh を書く。`--dry` で (i) `discussion/orch/` 以外に書けないこと、
  (ii) 負の対照として `formal/` への書き込みを指示した手が前後比較で不合格になること、を確かめる。
- **段階 1（試行）**: 次の作業項目 3 件を案 B で回す。
- **段階 2（判断）**: 測った値でユーザーが続ける／やめる／案 A に進むを決める。

測るもの（比較の基準は直近の S41〜S46 の 6 件、`.codex-turns/` と README の項番から数える）:
- 作業項目あたりの往復数と、claude-lab が「次に何をするか」で費やした手（STATE の書き直しを含む）
- STATE.md の長さ、「次の候補（未依頼）」の重複の数
- 事後承認待ちのうち、ユーザーに束で上がった割合
- fable-orch の 1手あたりの消費と、作業項目あたりの総額

予測（凍結の候補）: P1 往復数は増えない（各項目で基準の中央値 +1 以内）。P2 STATE.md の「更新」行は 3 件後に今の半分以下。
P3 fable-orch の消費は作業項目あたりの総額の 25% 以下。
**反証条件**: P1 か P3 が 3 件中 2 件以上で外れたら、fable-orch を外して今の形に戻す（呼ばなければ戻る）。

## 7. 起こりうる失敗と手当て

- **同系統の相関**: 計画の偏りを claude-lab が追認するだけになる → `[O]` に「後回しにしたもの」を必ず書かせ、codex-lab が締めの監査で一度読む。
- **進行役が中身に踏み込む**: 指令に読みや数値の結論を書く → 前後比較と、`[O]` の書式から外れた手を claude-lab が断る（§4）。
- **呼びすぎ**: 境目以外で呼ぶとコストが倍になる → 呼ぶ条件を §2 の 5 つに限り、`dispatch-log.md` に呼んだ理由を一行。
- **拒否（refusal）**: Fable は安全の分類で応答を断ることがある（`stop_reason: refusal`）→ スクリプトが検出して claude-lab に「指令なし」と送り、今の形で続ける。
- **三者の同時編集**: 書ける場所を分けている（claude-lab: README・specs・formal・コード、codex-lab: reviews・notes、fable-orch: orch）ので衝突しない。

## 8. 元に戻す方法

fable-turn.sh を呼ばなければ今の形と同じ。`discussion/orch/` は記録として残す（削除はしない）。README・agents の追記は採用時に decisions-log に記録し、戻すときはその記録どおりに外す。
