# BP 正本ライン棚卸しパケット（2026-11-28、読み取り専用監査）

- **作成**: 2026-11-28（`neon-lab`、`~/bridge-protocol` は完全読み取り専用で精査・1 バイトも非変更）。
- **目的**: Lab 側 `discussion/bp-proposals.md`（BP1〜BP14）と `~/bridge-protocol` 正本（`HEAD = 669107b`, `origin/main` 同期済み）の差分を棚卸しし、次に BP 正本ラインで着手すべき作業の優先順を確定する。

---

## 1. `~/bridge-protocol` 現状（確認した事実）
- **最新コミット**: `669107b`（`Complete 91-claim audit category III items C-G1 through C-G7 (11-23-1..7)`）
- **`decision_gate.jl status`**: `pending_A = 0`, `warning = false`, `hard_stop = false`（安全弁グリーン）
- **ステージ済み（`A`・未コミット）の 5 ファイル**:
  - `11月23日のメモ.md`
  - `aue-bool-mapping-vulnerability.md`
  - `logs/category-pipeline/G1-impacted-bindings-16699393640396-36179-jl_iQG2V1.log`
  - `logs/category-pipeline/reports/category-impact-report-16699496759822-36179-jl_6I9cRC.md`
  - `明日の発表用.md`

---

## 2. BP9（2026-11-22 引き継ぎ 4 件）の反映確認結果 → **全 4 件 反映済み**
Lab 側 `discussion/bp-proposals.md` では「BP 側反映待ち」表記が残っていたが、`~/bridge-protocol` の履歴・正本ファイルを直接照合した結果、**全 4 件とも 2026-11-22〜23 に反映・push 完了済み**と確認した：

| BP9 項目 | BP 決定 ID | BP コミット | 確認した正本ファイル | 状態 |
|---|---|---|---|---|
| 1. G1-A（`RedundantRecovery` 降格・並記） | `11-22-1` | `6a6590f` | `specs/packets/AGENCY-001.md` §3.5、`tools/AgencySubstrate/src/criteria.jl` (`redundant_recovery` 主定義＋`self_repairing` 互換別名) | **完了済み** |
| 2. G2-A（`criteria.jl` `pc` 統一） | `11-22-2` | `6a6590f` | `tools/AgencySubstrate/src/criteria.jl:84-88`（両側 `pc` 統一・後方互換側条件明記） | **完了済み** |
| 3. BP7・BP8（関数決定除外・時間差分離） | `11-22-3` | `6a6590f` | `tools/verify/blanket_table.jl`（`exclude_functional_determination`, `blanket_determines_*`, `screen_limitations`） | **完了済み** |
| 4. U-NC1(c) 身体包含＋Stage 1 系譜スパン参照 | `11-22-6` | `1d02449` / `72bc2c4` | `specs/decision-principles.md:211`、`category/`・`START_HERE.md` | **完了済み** |

※あわせて 91 件監査の `P1`（`11-22-7`）および `C-G1`〜`C-G7`（`11-23-1..7`）も `669107b` まで完了済み。

---

## 3. 本当に残っている BP 正本ラインの未反映案件（BP10〜BP14）

| 優先度 | ID | Lab 側ユーザー状態 | BP 正本への想定作業（BP ラインで実施） | 備考 |
|---:|---|---|---|---|
| **1（最優先・承認済み未反映）** | **BP11**（`U-SP1b`） | **2026-11-23 承認済み** | `specs/decision-principles.md` へ案 (a) 3 原則を反映：(i) 具体実装の DC 証明書・監査出力への `mapping_spec_hash`・`perm` 帯同と動的介入 `α` 不一致時の判定保留、(ii) 多型 AUE 横断での AGENCY-001 述語・吸収死不変＋3 区分終了分離、(iii) 自己改変系の不可変床凍結原則。`formal/ERIEC/DC.lean` は抽象のまま非変更。 | `aue-bool-mapping-vulnerability.md` が既に `~/bridge-protocol` に staged のまま残っている。 |
| **2（束ね判断・時間/双模倣）** | **BP12・BP13・BP14** | 2026-11-26〜27 に方向・J2 併記案を承認（BP 反映要否は BP 側判断） | 3 件は共通テーマ（内生時間・忘却の分離・双模倣不変性 ≈sem）。BP 正本側で：(a) まず `decision-principles.md` / `docs/claudeの提示する時間概念.md` 上での位置づけ（保守案＝Lab 固有要件にとどめるか、BP14 (b)＝終余代数・双模倣への Lean statement を新規ファイルで置くか）を 3 者 D-round（`bp-d-round.sh`）で整理し、ユーザーに種類 C 判断票を提出。 | BP14 (b) の「全鍵等重み T と場の探り Q の併記、S2 は事前凍結被覆条件時のみ（J2）」も同時反映対象。 |
| **3（整合整理）** | **BP10**（TRM 位置づけ） | Lab は仮定 H7 で進行中（BP 側判断待ち） | `category/erie_c_axiom_categorical_memo.md` §12〜§14 の「TRM＝個体・時間生成者」と Lab 側の「TRM＝臓器（`OpenDyn` 内部計算器官）」の整合を案 (a) 抽象インターフェース許容 vs 案 (b) 呼称分離で BP 側決定。 | 既存 Lean 変更不要（文書整合のみ）。 |
| **4（ハウスキーピング）** | staged 5 ファイル | 未整理 | `~/bridge-protocol` の既存 staged 5 ファイル（個人メモ `11月23日のメモ.md`, `明日の発表用.md` と `aue-bool-mapping-vulnerability.md`, `logs/category-pipeline/`）を commit 対象と非対象（unstage）に仕分けするユーザー確認。 | ユーザー明示許可なしに unstage/commit/削除しない。 |

---

## 4. 推奨する次の BP 正本ライン着手手順（ユーザー承認後に実施）
1. **ステップ B-1（最速・承認済み反映）**: `bp-d-round.sh` で **BP11（案 (a) 3 原則）** の `specs/decision-principles.md` 追記文案を 3 者レビュー → `bp-claude-code-turn.sh` で反映＋`decision_gate.jl status` / 既存テスト確認 → `bp-codex-turn.sh` 独立 I-R。
2. **ステップ B-2（種類 C 判断票）**: **BP12〜BP14＋BP10** の 4 件を 1 本の BP 側 D-round（`bp-d-round.sh`）で整理し、「文書整合のみで閉じる案」対「BP14 (b) 終余代数・痕跡前順序の Lean statement を新設する案」の判断票をユーザーへ提示する。
3. **Lab 側記録の同期（任意）**: `discussion/bp-proposals.md` の BP9 の状態を「全 4 件 BP 反映済み（`6a6590f`〜`669107b`）」へ更新する。

（反証条件: `specs/decision-principles.md` への BP11 追記で `decision_gate.jl` や `test_checker_semantic_manifest.jl` の既存テストが 1 件でも壊れる場合、または既存の未コミット staged 5 ファイルと競合する場合は即停止して切り分ける。）
