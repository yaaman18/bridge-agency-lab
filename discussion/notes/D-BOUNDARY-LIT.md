# D-BOUNDARY-LIT: 2026-11-19 更新（境界同定・判断ガバナンス）の論点整理と参照論文（〔暫定〕Fable 見直し待ち）

- 作成: 2026-11-20（`neon-lab`、Neon オーケストレーター体制 §1.4）
- 状態: 〔暫定〕（Fable の見直しまで、理論の結論を仕様・コードの根拠にしない。`discussion/README.md` §1.3）
- 位置づけ: 2026-11-19 に `~/bridge-protocol` および `~/bridge-agency-lab` に入った更新一式について、3者（`neon-lab`, `claude-lab`, `codex-lab`）で理論的・方法論的な論点と参照すべき論文を吟味・選定する D 段ノート。

---

## §0 問い（単独で読める問題設定・制約・事実）

### 背景と対象（確認した事実）
2026-11-19 に以下の未コミット更新が入った（`~/bridge-protocol` の `main` HEAD `d1cae17` からの差分と新規ファイル、およびラボの設計メモ 1 件）。Lean 本体・台帳・`AgencySubstrate` は変更されていない。

1. **境界同定の審査草案と有限表検査器（`~/bridge-protocol`）**
   - `specs/drafts/markov-blanket-boundary.md`: 外世界 `η`・感覚側 `s`・行為側 `a`・内部 `μ`、境界 `b = (s, a)` への分解を宣言し、指定時点の有限同時分布 `P` における条件付き独立 `P(μ, η, b) P(b) = P(μ, b) P(η, b)` を初回審査命題とする（引用は Parr, Da Costa & Friston 2020 [PMC6939234] のみ）。内向き・外向き経路の反証手順は状態固定を「探索的診断」にとどめ、正式測定の介入は現行 P-04（発信停止のみ・副作用込み）とする。既存契約（`VP-BDY-002/003`, `VP-ADJ-001`, `VP-WLD-001`）との切り分けを置き、M2・Wld・DC は保証外と明記。
   - `tools/verify/blanket_table.jl`: TOML プロファイルの SHA-256 と必須欄（`partition`, `observation_time`, `distribution_origin` 等）を照合し、正整数重み（`BigInt`）で `conditional_independence`、`marginal_dependence`、`blanket_copies_mu`/`eta`（正の台上での一対一複写除外）、`passes_statistical_screen` を厳密計算。`certified_predicate_scope = "finite_table_statistical_shielding_only"`、`not_certified = ["causal_mediation","action_contribution","autonomy","M2","Wld","DC"]` を出力。
   - 断絶例（周辺独立）と共通原因の自明複写例（`μ = η = s`）を反例として収録（ただしこれらを通るノイジーな共通原因モデルも存在しうることを草案自体が認める）。

2. **判断原則の台帳 v1.1 とローカル判定ゲート（`~/bridge-protocol`）**
   - `specs/decision-principles.md` v1.1（§3.2 拡張、§4.1 新設）・`START_HERE.md` 更新・`specs/drafts/decision-governance-review.md`・`tools/verify/decision_gate.jl`:
     - 判断要求書式に `版・依存` と `証拠の範囲` を追加。
     - §4.1 で決定 ID ごとに `確認 (approved/pending)`・`意味の変更 (clear/uncertain/changed)`・`依存 ([]/?/ID列)` を追記記録。
     - **安全弁**: 確認待ち A が **3 件以上で警告、5 件以上で依存の有無を問わず `implementation`/`freeze`/`evaluation`/`baseline_comparison`/`advance_A` を停止**（`exploration` と `audit` のみ継続可）。5 件未満でも不明 `?`・未確認・循環・`uncertain`/`changed` に依存する作業は保留。
     - 現行 §4 には確認待ち A がちょうど 5 件あり（`10-09-5/6/8`, `10-24-3/4`）、新基準ではハードストップ状態。
   - `test/test_blanket_decision_gate.jl`（12+26 件）および G1〜G4 ログ（`logs/gates/quiet/G*-blanket-20261119.log`）はすべて通過。

3. **AUE と外世界の境界 要件定義初稿（`~/bridge-agency-lab`）**
   - `discussion/notes/AUE-外世界との境界.md`: 内側＝回路・内部乱数・二つのプール・占有セルの代謝状態、外側＝周囲電波源・無線環境・資源ポート・非占有領域の物質場、と置く境界候補。
   - 接点は (1) 電波と受信機（2.4 GHz / 5 GHz 帯域切替の最小案）、(2) プールと資源ポート（現行）、(3) 占有域と物質場（現行、セルの所属は歩頭で決め消失・分裂は歩末で記録）。
   - 「一歩内の受け渡し経路候補」と「同時点の有限表 `b`」は別物であり、異なる時点の入出力を集めただけでは条件付き独立を主張できないと明記。

### 解くべき問い
- **Q1（論点・盲点の特定）**: 上記 1〜3 の更新内容について、`bridge-protocol`（M1〜M4, DC, P-04, 層分離）および `bridge-agency-lab`（AUE の S12 軛・D4 状態依存 α・S52 電波・切り出しの約束）に照らしたとき、理論的・方法論的な弱点・未解決の緊張・反証すべき箇所はどこにあるか。
- **Q2（参照すべき論文の選定）**: Q1 の各論点を吟味・反証・精緻化するために、(a) 既存リスト `papers/index.tsv` の中から再読・取得すべき論文、(b) リスト外から新規に参照・取得すべき論文は何か。各論文について「どの論点にどう効くか（支持／批判・反例／設計の手がかり）」と「本文の有無」を明示する。

### 制約
- `~/bridge-protocol` のファイルは変更しない。
- `phenomenal_claim` に触れる主張をしない。
- 記憶だけで論文の中身を事実として書かない。本文未読の論文は「要約／Web 確認のみ（本文未読）」と明記する。
- 理論の持ち主はユーザー。結論を勝手に確定せず、合意・割れた点・ユーザー判断待ちの問いを切り出す。

---

## §1 手元の論文リスト（`papers/index.tsv`）からの候補

| 番号 | 書誌（抜粋） | 本文 | 2026-11-19 更新との接点（仮説） |
|---|---|---|---|
| P082 | Kirchhoff, Parr, Palacios, Friston & Kiverstein (2018) *The Markov blankets of life* | **あり** (`text/082.txt`) | 草案の直接の背景（入れ子ブランケット・自律性）。過大主張の比較対象 |
| P101 | Krakauer et al. (2020) *The information theory of individuality* | **あり** (`text/101.txt`) | 個体性を環境との情報的分離・自己予測で定義（AUE の動的境界・分解 D との対比） |
| P104 | Biehl, Ikegami & Polani (2016) *Towards information based spatiotemporal patterns...* | **あり** (`text/104.txt`) | 力学系におけるエージェント・境界同定の困難（空間・時空パターンの扱い） |
| P078 | Kolchinsky & Wolpert (2018) *Semantic information, autonomous agency...* | **あり** (`text/078.txt`) | 介入（相関を切る）による生存・維持への因果的寄与（草案の反証表3行目・S12 軛との接続） |
| P114 / P134 | Myers (2021) / Vagner, Spivak & Lerman (2015) Open Dynamical Systems | **あり** (`text/114.txt`, `134.txt`) | 開放力学系の境界・インターフェースの圏論的構成（物質場・資源ポートの結合） |
| P147 | Mayo & Hand (2022) *Statistical Significance and Its Critics* | **あり** (`text/147.txt`) | Severe testing（厳格テスト）の観点からの事前固定・探索と評価の分離 |
| P031 | Buhrmann, Di Paolo & Barandiaran (2013) *A dynamical systems account of sensorimotor contingencies* | **あり** (`text/031.txt`) | 感覚運動随伴・身体固有の翻訳（`AUE-外世界との境界.md` の「身体固有の翻訳」） |
| P018 / P021 | Agmon et al. (2016) / Virgo, Egbert & Froese (2011) | なし | 代謝–境界の共構成と空間境界の役割（物質場の占有域・歩末の所属変更） |
| P100 | Bertschinger et al. (2008) *Autonomy: An information theoretic perspective* | なし (`oa_failed`) | 情報論的自律（内部の自己決定と環境からの独立・依存の両立） |
| P108 | Nosek et al. (2018) *The preregistration revolution* | なし (`oa_failed`) | 事前登録の標準的枠組み（§4.1・`blanket_table.jl` のプロファイル凍結） |
| P136 / P137 | Goguen & Meseguer (1982) / Sabelfeld & Myers (2003) | なし | 非干渉・情報流制御（境界の内向き・外向き経路漏れ検査の形式基盤） |
| P142 / P143 | Gotel & Finkelstein (1994) / Ramesh & Jarke (2001) | なし | 要件トレーサビリティと変更影響追跡（§4.1 の決定 ID・依存グラフ） |

---

## §2 新規に探索した外部論文候補（すべて本文未読・Web 書誌確認のみ）

### 群 I: マルコフブランケット批判・因果的/力学的境界同定
- **N01** Bruineberg, J., Dołęga, K., Dewhurst, J., & Baltieri, M. (2022). *The Emperor's New Markov Blankets*. Behavioral and Brain Sciences, 45, e215. DOI: `10.1017/S0140525X21002351`.
  - 論点: **Pearl blanket**（グラフ上の認識的・統計的道具）と **Friston blanket**（物理的・存在論的境界）の混同批判。`markov-blanket-boundary.md` のスコープ限定（`finite_table_statistical_shielding_only`）の理論的根拠・反証の軸。
- **N02** Biehl, M., Pollock, F. A., & Kanai, R. (2021). *A Technical Critique of Some Parts of the Free Energy Principle*. Entropy, 23(3), 293 (arXiv:2001.06408).
  - 論点: マルコフブランケット定義の非等価性と、定常分布の条件付き独立から力学・推論を導く飛躍の技術的反例。
- **N03** Aguilera, M., Millidge, B., Tschantz, A., & Buckley, C. L. (2022). *How particular is the physics of the Free Energy Principle?* Physics of Life Reviews, 42, 24–47 (arXiv:2105.11203). DOI: `10.1016/j.plrev.2022.04.002`.
  - 論点: 線形確率力学系ですら FEP のマルコフブランケット条件が極めて狭い領域でしか成立しないことの検証。
- **N04** Rosas, F. E., Mediano, P. A. M., Biehl, M., Chandaria, S., & Polani, D. (2020). *Causal Blankets: Theory and Algorithmic Framework*. IWAI 2020 (arXiv:2008.12568).
  - 論点: 静的分布の条件付き独立ではなく、計算力学に基づく**知覚行為ループ（PALO）と動的十分統計量としての「因果的ブランケット」**。非定常・非マルコフ過程にも対応し、AUE の「一歩内経路」と「同時点表」のギャップに直結する候補。
- **N05** Di Paolo, E. A., Thompson, E., & Beer, R. D. (2022). *Laying down a forking path: Tensions between enaction and the free energy principle*. Philosophy and the Mind Sciences, 3, 2. DOI: `10.33735/phimisci.2022.9187`.
  - 論点: エナクティビズム／オートポイエーシス側からの FEP・マルコフブランケット批判（定常性・境界の自己生成・不安定性 precariousness との緊張）。`bridge-protocol` の M1/M4 との相性を測る要石。
- **N06** Sakthivadivel, D. A. R. (2022). *Weak Markov Blankets in High-Dimensional, Sparsely-Coupled Random Dynamical Systems*. arXiv:2207.07620.
  - 論点: 批判への応答側。高次元・疎結合な力学系で近似的（弱）マルコフブランケットが成立する条件の厳密化（Parr et al. 2020 の後続）。
- **N07** Biehl, M., & Virgo, N. (2022/2023). *Interpreting systems as solving POMDPs: A step towards a formal understanding of agency*. IWAI 2022 / Springer (arXiv:2209.01619). DOI: `10.1007/978-3-031-28719-0_2`.
  - 論点: 物理系をエージェント・信念・行為として解釈する形式写像（解釈写像の恣意性と非一意性。AUE の「作者のラベル vs 身体固有の区別」と直結）。
- **N08** Pearl, J. (2009). *Causality* (2nd ed.) / Spirtes, Glymour & Scheines (2000). *Causation, Prediction, and Search*.
  - 論点: d-分離・忠実性（faithfulness）・マルコフ同値類・共通原因・do-介入。`blanket_table.jl` が弾けない「ノイジー共通原因」や、観測的条件付き独立と介入的媒介の分離の基礎。

### 群 II: ガバナンス・事前凍結・適応的データ解析・依存追跡
- **N09** Gelman, A., & Loken, E. (2013/2014). *The garden of forking paths* / *The statistical crisis in science* (American Scientist 102(6)).
  - 論点: データを見た後の分岐（意図せぬ適応的選択）が検証保証を壊す機構。
- **N10** Dwork, C., Feldman, V., Hardt, M., Pitassi, T., Reingold, O., & Roth, A. (2015). *The reusable holdout: Preserving validity in adaptive data analysis*. Science, 349(6248), 636–638.
  - 論点: 結果を見た後の反復による検証データの汚染（`decision-governance-review.md` の「既知例と独立評価の区別」の理論的裏づけ）。
- **N11** Mayo, D. G. (2018). *Statistical Inference as Severe Testing*. Cambridge University Press（P147 の親本） / Lakens, D. (2019). *The value of preregistration for psychological science: A conceptual analysis*. Japanese Psychological Review, 62(3), 221–230. DOI: `10.24602/sjpr.62.3_221`.
  - 論点: 事前登録の本質は「禁止」ではなく「厳格テストの度合い（severity）を評価可能にする仕様変更の可視化」。`uncertain/changed` による保留の哲学的位置づけ。
- **N12** Steegen, S., Tuerlinckx, F., Gelman, A., & Vanpaemel, W. (2016). *Increasing Transparency Through a Multiverse Analysis*. Perspectives on Psychological Science, 11(5), 702–712.
  - 論点: 分解や前処理の選択依存性を単一解に隠さず並べて報告する枠組み（`bridge-protocol` P-07・`dc` vs `dc_T` や境界候補の並記と親和）。
- **N13** de Kleer, J. (1986). *An assumption-based TMS*. Artificial Intelligence, 28(2), 127–162. DOI: `10.1016/0004-3702(86)90080-9`.
  - 論点: 前提（assumption）の集合と導出結果の依存グラフ（justification）を管理し、前提の撤回・未確定・矛盾から失効範囲を自動追跡する計算機科学的原典（`decision_gate.jl` §4.1 の構造的モデル）。

### 1 往復目で追加された候補（Web 書誌確認済み・本文未読）
- **N14** Ay, N., & Polani, D. (2008). *Information flows in causal networks*. Advances in Complex Systems, 11(1), 17–41. DOI: `10.1142/S0219525908001465`（UHRA 等に公開版あり）。提案: `claude-lab`（介入による内向き情報流の量）。
- **N15** Janzing, D., Balduzzi, D., Grosse-Wentrup, M., & Schölkopf, B. (2013). *Quantifying causal influences*. The Annals of Statistics, 41(5), 2324–2358. DOI: `10.1214/13-AOS1145` / arXiv:1203.6502。提案: `claude-lab`。
- **N16** Friston, K. (2013). *Life as we know it*. Journal of the Royal Society Interface, 10(86), 20130475. DOI: `10.1098/rsif.2013.0475` / PMC3730701。提案: `claude-lab`（過大主張の原典比較）。
- **N17** Dawid, A. P. (1979). *Conditional Independence in Statistical Theory*. Journal of the Royal Statistical Society: Series B, 41(1), 1–31. DOI: `10.1111/j.2517-6161.1979.tb01052.x`。提案: `codex-lab`（条件づけで変数が確定する反例の定義点検）。

---

## §3 3者議論のたたき台（P1〜P5）

- **P1（有限表の統計的遮断の限界と反証文献）**: `blanket_table.jl` は同時点の条件付き独立＋周辺依存＋支持集合の全単射除外を厳密検査するが、ノイジーな共通原因・動的フィードバック・非定常性を区別できない。どの論文（N01〜N08、P082 等）を必須の批判・設計基準として採用すべきか。
- **P2（AUE 境界初稿と既存ラボ・BP 規則の接点）**: `AUE-外世界との境界.md` の (a) 同時点表と一歩内経路のギャップ、(b) 状態固定診断 vs P-04 発信停止、(c) 電波帯域切替のソフトウェア経路 vs 実機適用、(d) 物質場の歩末の所属変更、に対して最も効く論文と不足している観点は何か。
- **P3（`decision-principles.md` v1.1 §4.1 と `decision_gate.jl` の評価）**: 3/5 安全弁と依存別保留（`uncertain/changed/?`）の弱点（例：自己申告依存の見落とし、独立作業の過停止、探索→評価の汚染検出）に対し、N09〜N13・P108/P142/P147 のどれが最も実践的な改善指針を与えるか。
- **P4（見落とし論文の追加）**: 上記のリストから漏れている重要な論文（特に OA で本文取得可能なもの、力学系・因果推論・情報流・オートポイエーシス・形式検証のガバナンス）は何か。
- **P5（優先順位）**: まず本文を読む（既存 OA）／新規に取得して読むべき最優先 5〜8 本をどう絞るか。

---

## §4 議論ログ（追記）

### 1 往復目（2026-11-20）
- **`claude-lab` 要点**:
  - P1: 観測表ではマルコフ同値類（鎖 `η→b→μ` vs 分岐 `η←b→μ`）を区別不能。P-04（発信停止）は外向きのみで、内向き経路は表でも正式介入でも見えない。反証条件：分岐表を `blanket_table.jl` に入れて落ちれば外れ（落ちないと予測）。文献：N08, N01, N02/N03 の片方。
  - P2: 一歩内の時間差 `(η_t, b_t, μ_{t+1})` は同時点 CI とは別命題（`bp-proposals` 対象、ラボでは仮定 H）。内向き介入には S12 軛が P-04 より適合し P078 と照合。物質場の歩末所属変更は状態依存分割 → P016/P017/P018。
  - P3: 自己申告依存の抜けは ATMS (N13) では捕まらない → 凍結 SHA・参照ファイルから機械抽出を提案。5 件全停止は ATMS と逆で過停止。Dwork (N10) はラボの種子使い捨て規則の正当化、P147/N11 は保留の位置づけ。ユーザーへの問い：**v1.1 の停止はラボの評価にも及ぶか**。
  - P4 追加: Ay & Polani 2008 (N14), Janzing et al. 2013 (N15), Friston 2013 (N16), 既存未取得 P011。
  - P5 優先 7 本: N08, N01, N14, N04, P078, P082, P016/P017（N02/N03・N09〜N12 は後回し）。
- **`codex-lab` 要点**:
  - P1 challenge: 複写除外の有限反例を提示（独立公平ビット `μ, z` と独立誤りビット `e` [P=1/4] で `b=(μ,z), η=μ⊕e`）。周辺依存・CI 成立かつ `b` は全単射でないため `blanket_table.jl` を通るが、`b` から `μ` が完全復元できる（全射的決定）。N02 の力学的反例とは区別すべき。
  - P2 clarify: 物質場で歩頭に外側だったセルが歩末に占有されると、場の値が一定でも歩末再集計で内部総量が増えうる → 歩頭所属固定の同一セル記録で増分が消えれば受け渡し証拠から外す。セル対応に P104、軛と P-04 の比較に P078。
  - P3 challenge: 安全弁の両方向の失敗例（4件以下で実依存を `[]` 誤記すると通過／5件で独立凍結も停止）。N13（依存伝播）・N10（再利用評価）のどちらも件数閾値（3/5）の根拠にはならない。
  - P4 追加: Dawid 1979 (N17)。
  - P5 優先 6 本: N02, N04, P104, P078, N13, N10（本文未読のため採用判断は保留）。

### 2 往復目・収束（2026-11-20）
- **`claude-lab` 応答**:
  - Q2-1 賛成。3 層を「直すのに何が要るか」の順で並べる：(a) 有限表の中で直せる（関数従属 `H(μ|b)=0`・`H(η|b)=0` の除外）、(b) 介入が要る（マルコフ同値類：鎖 vs 分岐）、(c) 力学・追加仮定が要る（静的遮断→力学）。N01（概念根拠）と N02（技術反例）は両方残し、重なる N03 は第 2 群へ。
  - Q2-2 合意。補足：S12 の軛は「`η→s` の源を切る内向き介入」、P-04 は「外向き経路を切る介入」であり、どちらも `b` の状態固定とは別と明記する。歩頭所属固定での再集計は既存の記録を読むだけで検証可能（予測凍結後に実施）。
  - Q2-3 機械抽出（凍結 SHA・参照ファイル）の限界4点（意味・概念前提は参照に出ない／文脈参照による偽陽性／`core/` 共有コード経由／会話・`user-decisions.md` のみの決定）を列挙し、「機械抽出を下限、自己申告との和、機械検出あり＋申告 `[]` で警告」を提案。反証条件：過去の取り下げ事例（項番161→164 等）で人が辿った影響範囲を機械抽出が 1 件でも取りこぼせば単独では不十分。
  - Q2-4 入れ替え：N10（Dwork）と N05（Di Paolo 2022）を第 2 群寄りへ。
- **`codex-lab` 応答**:
  - Q2-1 accept。3 層に同意。除外を決定関数まで広げる案の反証条件：意図した正例（ノイジーな鎖）まで落とせば棄却。N01・N02 を残し N05 は第 2 群。
  - Q2-2 accept。時間差の組は仮定 H として BP 提案候補へ。物質場は予測凍結後に歩頭所属固定の同一セル増分を比較（増分が残れば所属入替だけでは説明できない）。P104・N04 を P016/P017 に先行させる。
  - Q2-3 challenge/defer。SHA・参照から拾えるのは「依存候補」にとどまる（参照に出ない前提変更で結論が変わる例が 1 件あれば完全性は崩れる）。過停止は独立照合できたのに停止した件数で実測（現状の 5 件全停止だけでは過停止件数は未確定）。N10・N13 から件数閾値は導かない。v1.1 の停止がラボに及ぶかはユーザー判断。
  - Q2-4 challenge。即読 4 本は賛成。新規取得は N08（Pearl、鎖と分岐の識別）を N15 の枠に上げ、N14・N15 は介入検討の第 2 群へ。N10・N13 は別論文なので「6 枠」と明記。
- **`claude-lab` 締め確認**: `codex-lab` と食い違いなし。P3（機械抽出は下限・候補、自己申告と併用）で合意。P5 は即読 4 本＋新規取得 6 枠（N01, N02, N04, N08+N17, N13, 残り 1 枠は N10 か空き）で 3 者合意。

---

## §5 3者合意と〔判断点〕・ユーザーへの問い（〔暫定〕Fable 見直し待ち）

### 合意した整理
1. **P1 の 3 層分解（`blanket_table.jl`・`markov-blanket-boundary.md`）**:
   - **(a) 有限表内の穴**: `b=(μ,z), η=μ⊕e`（`e~Bern(1/4)`）は `μ⊥η|b`・周辺依存を満たしつつ全単射でないため現行 `blanket_table.jl` を通る（`neon-lab` 手計算でも確認：`length(mu)=2, length(blanket)=4, length(mb)=4, length(eb)=8` で `copy_mu=false, copy_eta=false, passes_statistical_screen=true`）が、`H(μ|b)=0` で内部を完全復元できる。→ **N17 (Dawid 1979)**。
   - **(b) 介入を要する限界**: 観測表ではマルコフ同値類（鎖 `η→b→μ` vs 分岐 `η←b→μ`）を識別できず、P-04（発信停止）は外向きのみ。→ **N08 (Pearl 2009)**、次点で **N14/N15**。
   - **(c) 力学・追加仮定を要する限界**: 静的遮断から力学・自律・推論は導けない。→ **N01 (Bruineberg et al. 2022)**、**N02 (Biehl et al. 2021)**、**P082 (Kirchhoff et al. 2018)**。
2. **P2 の AUE 境界要件（`AUE-外世界との境界.md`）**:
   - 時間差 `(η_t, b_t, μ_{t+1})` は BP の同時点命題と別物（BP 提案候補、ラボでは仮定 H）。→ **N04 (Rosas et al. 2020)**。
   - 物質場の歩末所属変更による見かけの流入は、予測凍結後に歩頭所属固定の同一セル記録と比較して分離する。→ **P104 (Biehl et al. 2016)**。
   - 内向き介入は S12 軛（`η→s` の源を切る）、外向き介入は P-04（発信停止）とし、どちらも `b` の状態固定とは別と明記して **P078 (Kolchinsky & Wolpert 2018)** と照合する。
3. **P3 のガバナンス v1.1（`decision-principles.md` §4.1・`decision_gate.jl`）**:
   - 自己申告の抜け（4件以下で `[]` 誤記）と過停止（5件で独立作業も停止）の両面を点検対象とする。
   - SHA・参照ファイルからの抽出は依存候補（下限）にとどめ、自己申告と併用する。**N13 (de Kleer 1986)** も **N10 (Dwork et al. 2015)** も件数閾値（3/5）の根拠には使わない。
4. **P5 参照論文の優先順位（すべて未読の N 系は本文取得・閲読後に採用判断）**:
   - **即読（手元本文あり 4 本）**: **P078**（Kolchinsky & Wolpert 2018）、**P104**（Biehl et al. 2016）、**P082**（Kirchhoff et al. 2018）、**P147**（Mayo & Hand 2022）。（補足: 手元本文あり **P101** Krakauer et al. 2020）
   - **新規取得・最優先（6 枠）**:
     1. **N01** Bruineberg et al. (2022) *The Emperor's New Markov Blankets*
     2. **N02** Biehl, Pollock & Kanai (2021) *A Technical Critique of Some Parts of the Free Energy Principle*（OA / arXiv:2001.06408）
     3. **N04** Rosas et al. (2020) *Causal Blankets*（OA / arXiv:2008.12568）
     4. **N08** Pearl (2009) *Causality*（マルコフ同値類・do-介入）＋ **N17** Dawid (1979) *Conditional Independence in Statistical Theory*
     5. **N13** de Kleer (1986) *An assumption-based TMS*
     6. **N10** Dwork et al. (2015) *The reusable holdout*（BP 側の再利用汚染吟味枠。ラボでは種子使い捨てで代替済みのため第 2 群寄り）
   - **第 2 群**: N14 (Ay & Polani 2008), N15 (Janzing et al. 2013, arXiv), N05 (Di Paolo, Thompson & Beer 2022, OA), N03 (Aguilera et al. 2022, arXiv), N06 (Sakthivadivel 2022, arXiv), N07 (Biehl & Virgo 2022, arXiv), N16 (Friston 2013, PMC), N09 (Gelman & Loken 2014), N11 (Lakens 2019, OA), N12 (Steegen et al. 2016), P016/P017 (Beer 2004/2015), P018 (Agmon et al. 2016), P021 (Virgo et al. 2011)。

### 〔判断点〕
- `〔判断点 O12〕` P1 の課題を 3 層（有限表の関数決定除外漏れ／観測表と P-04 のマルコフ同値類不可識別性／静的遮断から力学・自律への飛躍）に分離／単一の「マルコフブランケット批判」にまとめる案を棄却（修正手段が全く異なるため）／確信度：高／codex の立場：合意
- `〔判断点 O13〕` 新規取得の最優先 6 枠で N08+N17 を介入的情報流 N14/N15 より先行させ、N05 (Di Paolo 2022) と N03 (Aguilera 2022) を第 2 群に置く／介入定量やエナクティビズム対比を第 1 群に入れる案を棄却（まず現行有限表の 2 反例と動的境界 N04・ATMS N13 を優先）／確信度：中／codex の立場：合意（N10 の第 1 群/第 2 群の位置づけのみ軽微な温度差あり、6 枠目で両論明記）

### ユーザーに決めてほしい問い
1. **U-BL1**: `~/bridge-protocol/specs/decision-principles.md` v1.1 の確認待ち A による停止（現行 5 件でハードストップ）は、`bridge-agency-lab` 側の評価・凍結作業にも及ぶのか、`bridge-protocol` 側に限るのか。
2. **U-BL2**: 上記の新規参照候補（特に OA / arXiv の N02, N04 等）の取得を進めるか。まず手元本文あり 4 本（P078, P104, P082, P147）の精読・照合から着手するか。
3. **U-BL3**: P1 の 2 反例（全単射除外の関数決定すり抜け・マルコフ同値類＋P-04 外向き限定）および P2 の時間差境界 `(η_t, b_t, μ_{t+1})` を、`discussion/bp-proposals.md` に新提案として起票するか。

---

## §6 ユーザー決定の反映と OA 論文取得結果（2026-11-20）
- **U-BL1 決定**: `bridge-protocol` v1.1 の停止は **`bridge-agency-lab` 側の評価・凍結作業にも及ぶ**（`user-decisions.md`・`STATE.md` に記録済み）。確認待ち A 5 件が解消されるまで、ラボ側も `exploration` と `audit` に限定。
- **U-BL3 決定**: `discussion/bp-proposals.md` に **BP7**（関数従属すり抜け＋マルコフ同値類・P-04 外向き限定）および **BP8**（時間差境界 `(η_t, b_t, μ_{t+1})`、仮定 H6）を起票済み。
- **U-BL2 実施（合法 OA 取得・テキスト化）**: `papers/index.tsv` に P154〜P169 を追加。PDF ダウンロード＋PDFKit テキスト抽出を **11 本** 完了（P155 Biehl2021, P156 Rosas2020, P157 Dwork2015 arXiv:1506.02629, P160 DiPaolo2022, P161 Janzing2013, P162 AyPolani2008, P163 Aguilera2022, P164 Sakthivadivel2022, P165 BiehlVirgo2022, P166 Lakens2019, P168 Dwork2015 arXiv:1411.2664）。
  - 自動取得できなかった 5 件: P154 Bruineberg2022（PhilSci-Archive 18315 が直接 PDF を返さず `oa_failed`）、P167 Friston2013（Europe PMC タイムアウト、`oa_failed`）、P158 Dawid1979・P159 de Kleer 1986・P169 Pearl 2009 書籍（有料、`no_oa_found`）。

---

## §7 `[FMT:SYM]` ハイブリッド記号記法パイロット計測（2026-11-20、`d-round.sh low`）
- 題材: 取得した P155（Biehl 2021 Obs.1）と P156（Rosas 2020 p.3・Def 1–2）の一次抜粋を BP7・BP8 と照合（`audit` 範囲）。
- `codex-lab` 実測: コマンド 0 回、入力 20,147（キャッシュ外 6,707）、**出力 295**（日本語 r1: 776 / r2: 622 から **−62% / −53%**）、送信〜`codex-turn` 完了 **+22 秒**。
- 論理の質（取り違え 0 件、2 件の鋭い `CHG` を検出）:
  - P1[CHG]: P155 Obs.1 は連続ベクトル場とエルゴード分布の独立性であり、BP の離散更新則と有限表での双方向証人（pass/fail 両組合せ）は別途構成が要る。
  - P2[CHG] + 反例: `E_t` が iid 公平ビット・`b_t` 定数・`M_t = sg = E_{t-1}` では `I(sg; E_{t-1}|b_t) = 1 bit` かつ `I(sg; E_t|b_t) = 0`。静的 MB が `sg` を弾くのは、過去環境が現在環境 `E_t` とも相関を残す場合に限られる。
  - P3[ACC]: Prop.1 の普遍存在と部分観測の Granger 限界により、P-04 / S12 軛は独自の役割を保つ。
- `claude-lab` 側: 30 分無通信により `agmsg` 監視ストリームが 21:42 で自動終了していたため未回収（`claude-lab` ペインで `/agmsg` を再開すれば応答可能）。
