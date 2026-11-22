# D-AGENCY-GATES: 残る 2 つの理論門番（`10-24-5` 冗長性 vs DC2、`10-09-6` Julia/Lean L3 非比較性）の決着案

- 作成: 2026-11-22（`neon-lab` 起草、`claude-lab`・`codex-lab` 査読反映。3 系統体制 §1.3 改訂［案 A］準拠、`audit` 作業。`~/bridge-protocol` は一切変更していない）
- 対象:
  - **論点 G1**: `~/bridge-protocol/specs/decision-principles.md` §4 `10-24-5`（種類 B 未決: P-03 vs P-07）および `specs/packets/AGENCY-001.md` §6 反証条件
  - **論点 G2**: `10-09-6` 監査（`notes/BP-PENDING-A-AUDIT.md` 〔判断点 O18〕）で判明した Julia `self_producing` と Lean `SelfProducing` の論理的非比較性

---

## §0 問い（単独で読める問題設定・一次事実）

### 論点 G1：`10-24-5`（自己修復 L3R の核冗長性要件 vs DC2 の非冗長決定）
- **確認した一次事実**:
  1. `~/bridge-protocol/specs/packets/DC2-HUNIT-N3.md` §6（2026-10-02〜04 ユーザー決定 2・3・6）および `DC2-GROUND-TRUTH-002.md`:
     - 決定 2：**「冗長に支えられた閉路は組織とみなさない。閉路の辺を除いたとき、閉路の全員が持続を失う場合だけを組織の閉路とする（厳しい読み）」**。
     - 決定 3・6：冗長性は部分（ユニット）の水準で読み（P-03）、対の両端だけで見る（中継ユニットの冗長は許容）。介入は発信停止のみ（P-04）・反証可能性を残す側（P-06）。
  2. `~/bridge-protocol/logs/gates/AGENCY-001/README.md:149-152` および `self-loop-pair.out`:
     - 改訂 2 の自己修復 `self_repairing`（L3R）は、各核ユニットを順に発信停止して回復を測る定義上、「核のどのユニットの発信を失っても残りが活動を保つ」**核の冗長性**を要求する。
     - 自己ループのない裸の 2 ユニット対（`bare pair`）は `L3=true, L3R=false` だが、各ユニットが自己ループを持つ対（`self-looped pair`）は、相互の辺を切っても各端点が自己ループで生き残るため DC2 決定 2 の意味では組織でないにもかかわらず `L3=true, L3R=true` となる（`self-loop-pair.out`）。
     - 7 ユニット無作為回路 20,000 個で、`L2=74, L3=3513, L3R=17, (L2∧L3R)=0`（手設計 `repairing-agent` のみ両立）。
  3. `~/bridge-protocol/specs/packets/AGENCY-001.md` §6（L98–99）の反証条件：
     - **「自己修復を満たす系が、核の冗長性（どのユニットを失っても残りが活動を保つ）以外の性質で区別できない → 自己修復は冗長性の言い換えであり、L3 の深化とは呼ばない。」**

### 論点 G2：`10-09-6` の Julia `self_producing` と Lean `SelfProducing` の論理的非比較性
- **確認した一次事実**:
  1. `~/bridge-protocol/formal-experiments/Agency.lean:64-65`:
     `def SelfProducing (t : StructureTrial Q) := (∀ q, ¬ t.structurePersists q .ablated) ∧ (∃ q, t.structurePersists q .intact)`（停止側 `.ablated` と残す側 `.intact` を**同一条件族 $Q$** で比較）。
  2. `~/bridge-protocol/tools/AgencySubstrate/src/criteria.jl:75-79`:
     `!any(x -> structure_persists(s, p, x; silenced=everything), schedules) && any(x -> structure_persists(s, pc, x; silenced=sensor_units(s)), schedules)`（停止側は**通常資源 `p`**、残す側は**潤沢資源 `pc` かつ感覚停止**で比較）。
  3. **`~/bridge-protocol/tools/AgencySubstrate/src/substrate.jl:65-125` の直接コード検証（重要発見）**:
     - `silenced = everything` でも、停止ユニットは内部状態を更新して `count(new)` 分の資源を消費し、感覚ユニットも発火する（L81–93）。ただし全辺について `used[k] == false` となるため強化は起きない（L102）。
     - **死の歩での減衰スキップ（L94–99）**: `resource < 0` で死ぬ歩は `_decay_unused!`（L111）を呼ばずに早期 `return` する。そのため通常資源 `p` が減衰周期の歩で餓死すると、餓死しない潤沢資源 `pc` に比べて**最大 1 回だけ減衰ティックを失う**。
     - 現行フィクスチャ設定（`horizon=60, decay_period=8` → 7 ティック、`strength0=4`）では `7 - 1 = 6 ≥ 4` のため `p` と `pc` は停止側で一致しているが、`⌊horizon / decay_period⌋ == strength0` となる境界設定では **`p` と `pc` が停止側で食い違う**。

---

## §1 論点 G1（`10-24-5`）の 2 択整理案 〔判断点 O23〕

### 案 G1-A（層分離＋現行 L3R の名称降格、推奨）
- **命題**:
  1. **DC2 の規則は一切変えない（P-03・P-06・P-07 保全）**: DC2 の「非冗長性（決定 2・両端検査・中継許容・発信停止意味論）」は**最小の組織単位の定義**としてそのまま守る。
  2. **現行基体の L3R は「冗長回復（`RedundantRecovery`）」へ名称・主張を降格して別層に切り分ける**: 現行の固定辺基体では、`self-looped pair` のように DC2 決定 2 で組織とみなされない系でも `self_repairing = true` になるため、現行 `self_repairing` を「L3 の深化（組織の自己修復）」とは呼ばず、**独立の回復ラベル（`RedundantRecovery`：既知辺の再強化能力）**として並記する（P-07・P-11）。
  3. **将来の「真の L3R（組織の自己修復）」へ進める条件（別課題）**: 新規構成素生成を持つ基体（Track B 等）へ移すか、少なくとも「核が DC2 組織閉路を少なくとも 1 つ含む（`L3R ⇒ ∃ DC2-org sub-cycle`）」等の追加要件を置いて自己ループ対のすり抜けを塞ぐ。
- **反証条件**:
  - (1) 現行基体において `self_repairing = true` かつ核に DC2 組織閉路を含む非自明な系と含まない系を現行判定だけで区別できるなら、「名称降格が必須」という前提を見直す。
  - (2) 現行 L3 領域上で「核の冗長性 ⇔ L3R」の同値性が破れる（核の冗長性＋減衰可能性を満たすのに L3R 偽となる）具体反例があれば、「単なる冗長性の言い換え」という §6 診断を弱める（ただし `self-looped pair` の DC2 衝突自体は残る）。

### 案 G1-B（DC2 非冗長原則を上位に置き、現行 L3R を撤回）
- **命題**: DC2 決定 2（冗長閉路は組織でない）を AGENCY-001 の核にも貫き、核の冗長性を要求する現行 `self_repairing` を §6 反証条件により撤回する（`RedundantRecovery` としても残さない）。
- **最強の反論**: 生物の損傷回復は一般に多経路の冗長性を伴うため、回復能力の記録ラベル自体を消すと、将来の構成素生成・増殖モデルとの比較基準も失われる。

---

## §2 論点 G2（`10-09-6` Julia/Lean L3 非比較性）の 2 択整理案 〔判断点 O24〕

### 案 G2-A（停止側を `pc` に揃えて同一条件族 $Q_{\mathrm{endo}}$ 上で Lean `SelfProducing` の厳密インスタンスにする、推奨）
- **命題**: `criteria.jl:77` の停止側を `p` から `pc` へ揃え、**`Q_endo := { (pc, sch) | sch ∈ 試験日程 }` という同一条件族**の上で `.ablated`（全ユニット停止）と `.intact`（感覚のみ停止）を比較する。これにより、Julia の `self_producing` は Lean `SelfProducing`（`Agency.lean:64-65`）の**厳密なインスタンス**になる（ただし Lean 側の変数名・注記で「条件族は潤沢資源・感覚遮断の内発条件 $Q_{\mathrm{endo}}$」であることを明示する）。
- **後方互換性の成立条件（仮定 H）**: `substrate.jl:94-99` の死の歩スキップ減衰は、**死が吸収状態（復活なし）であるため 1 生涯あたり最大 1 回**に限られる（反例：復活可能な変種ではスキップが複数回起き下界が崩れる）。よって `p` と `pc` が停止側で一致するのは **`⌊horizon / decay_period⌋ - 1 ≥ strength0`（または `maintain == false`）** の範囲に限られる（現行フィクスチャは `⌊60/8⌋ - 1 = 6 ≥ 4` で成立）。
- **反証条件**: 現行日程および任意の試験日程 $q$ で `structure_persists(s, p, q; silenced=everything) ≠ structure_persists(s, pc, q; silenced=everything)` となる例（例：`⌊h/d⌋ == strength0` で `p` がティック歩に餓死する設定）が存在すれば後方互換性は破れる（この場合は「新旧判定の差分」として明記が必要）。

### 案 G2-B（コード不変・別操作述語として正式分離）
- **命題**: `criteria.jl` を一切変更せず（既存ログとの完全同一性を維持）、`AGENCY-001` と `bp-proposals.md` で「Julia `self_producing` は Lean `SelfProducing` の実装ではなく、非比較な別操作述語である」と明記して切り離す。
- **弱点**: Lean の型定義と Julia の監査実装が断絶したまま残る。

---

## §3 ユーザーへの 2 択まとめ（3 者合意確定後に提出）
- **U-G1（`10-24-5`）**: **案 G1-A（推奨：DC2 非冗長を保全したまま、現行 L3R を別ラベル `RedundantRecovery` に降格し、真の自己修復は将来課題へ分離）** か、**案 G1-B（現行 L3R を撤回）** か？
- **U-G2（`10-09-6` Julia/Lean）**: **案 G2-A（推奨：停止側も `pc` に揃え、`⌊h/d⌋ - 1 ≥ strength0` の条件明記つきで同一条件族 $Q_{\mathrm{endo}}$ 上の Lean `SelfProducing` インスタンスに接続）** か、**案 G2-B（コード不変・別述語として正式分離）** か？

---

## §4 議論ログ（2026-11-22 査読）
- **1 往復目（`d-round.sh medium`, 並列 89 秒）**:
  - `claude-lab`・`codex-lab` が **(1) G1-A の旧反証条件が定義上発火不能である点と DC2/P-03/P-06 保全条件**、**(2) `substrate.jl:94-99` の死の歩スキップ減衰（`p` が最大 1 ティック失う）と `⌊h/d⌋ - 1 ≥ strength0` の正確な側条件**を指摘・検証。全指摘を §0〜§2 に反映済み。
- **2 往復目（`d-round.sh low`, 並列 16 秒、3 系統合意）**:
  - `claude-lab`・`codex-lab` ともに `[ACC]`。「死が吸収状態 ⇒ スキップ最大 1 回」の明記と、`RedundantRecovery` 事例を DC2 組織閉路の証拠に混入させない反証条件を加えて確定。

---

## §5 ユーザー決定（2026-11-22 10:05）
- **U-G1（`10-24-5`）**: **案 G1-A 採用**（DC2 非冗長規則 P-03・P-06・P-07 を保全し、現行固定辺基体の `self_repairing` を別ラベル `RedundantRecovery` へ降格・並記。真の自己修復は新規構成素生成または DC2 組織閉路包含を要する別枠へ分離）。`notes/BP-PENDING-A-AUDIT.md` §5 の BP 側反映ブロックへ追記済み。
- **U-G2（`10-09-6` Julia/Lean L3 非比較性）**: **案 G2-A 採用**（2026-11-22 10:18 ユーザー決定「じゃあそれらもやっといて」）。停止側も `pc` に揃え、死は吸収状態⇒スキップ最大 1 回のもとで側条件 `⌊horizon / decay_period⌋ - 1 ≥ strength0 ∨ ¬maintain` を明記して同一条件族 $Q_{\mathrm{endo}}$ 上の Lean `SelfProducing` 厳密インスタンスに接続する。`notes/BP-PENDING-A-AUDIT.md` §5 の BP 側反映ブロックへ統合済み。
