# bridge-protocol 論文収集：統合版リストと収集論文

統合の土台は ClaudeCode 推奨リスト（A〜K章、項目1〜51、項目番号・検索語・起点・★最優先指定・「効く所」を保持）。これに Muse リスト由来の上層を L章（項目52〜62）として追加した全62項目。

収集規則： ★項目は最優先で原則2件以上、その他は最低1件。報酬最大化の強化学習・最適化論文は対照として明記できるものだけ。意識・現象性を主張する論文は除外し、機能と構造の議論だけ。各論文には書誌情報・DOI（web検索で検証したもののみ。検証できない場合はその旨を明記）・中心の主張（日本語1〜2行）・形式モデル／計算機実験の有無・対応項目番号を付けた。

収集結果の概要： **全62項目をカバー（62/62）、収集論文153件、★10項目すべてで2件以上を確保、未収集項目なし。** 詳細は文末「未収集・注意メモ」参照。

---

# 統合版リスト

## A. 自己維持の理論（M1・DC の土台）
- **項目1 オートポイエーシスと作動閉包** — 検索語: autopoiesis, operational closure, organizational closure — なぜ必要か: M1・DC の原点。自己維持を外部目標ではなく作動の閉包として定義する土台。
- **項目2 制約の閉包（closure of constraints）** — 検索語: closure of constraints, biological autonomy, organisation — なぜ必要か: L3（自己産出）と、物質の層・組織の層の分け方を与える。
- **項目3 Rosen の (M,R) 系とその形式化** — 検索語: (M,R) systems, metabolism-repair, closure to efficient causation, relational biology — なぜ必要か: 効率因への閉包という、閉包概念の別系統の形式化との比較。
- **項目4 自己触媒集合** — 検索語: RAF sets, autocatalytic sets, collectively autocatalytic — なぜ必要か: 核 κ の構成素どうしが互いを保つ構造の数理モデル。
- **項目5 precariousness・adaptivity・規範の内生** — 検索語: adaptivity, precariousness, intrinsic normativity, sense-making — なぜ必要か: 維持が危ういからこそ規範が内生する、という M1 の解釈の支柱。
- **項目6 生存可能性の理論（viable と DC の区別）** — 検索語: viability theory, viability kernel, essential variables — なぜ必要か: 開放系の viable と自己維持証明書 DC を同一視しないための区別の根拠。

## B. 自己維持の最小モデル（基体の比較対象）
- **項目7 計算機上の最小オートポイエーシス** — 検索語: computational autopoiesis, SCL model, Game of Life glider autopoiesis — なぜ必要か: 基体が「本当に自己維持か」を判定する比較対象の最小事例。
- **項目8 代謝に基づく行動** — 検索語: metabolism-based behavior, minimal model of metabolism-based chemotaxis — なぜ必要か: 維持費（KC）と行為が結びつく最小モデル。
- **項目9 原始細胞と chemoton** — 検索語: chemoton, protocell autonomy, minimal life — なぜ必要か: 代謝・境界・情報の三つが揃う最小生命モデルの古典的参照点。
- **項目10 人工化学** — 検索語: artificial chemistry, AlChemy, organization theory (chemical organization) — なぜ必要か: 組織（organization）を形式的に数える方法の供給源。
- **項目11 自己修復・再生と、冗長性・縮退** — 検索語: degeneracy vs redundancy, self-repair, neural cellular automata regeneration — なぜ必要か: L3R が「核の冗長性」を測っているだけという指摘への対処。

## C. 感覚運動の結合（M2・hSMC・α/σ）
- **項目12 感覚運動随伴性** — 検索語: sensorimotor contingencies, dynamical SMC — なぜ必要か: M2 の随伴 α ⊣ σ の経験的・理論的対応物。
- **項目13 ★自己維持する感覚運動の型としての習慣** — 検索語: habits as self-sustaining patterns, IDSM, habit-based regulation — なぜ必要か: 沈殿の記憶、固定化、使わなければ消える結線の理論化。★最優先。
- **項目14 ホメオスタットと超安定性** — 検索語: homeostat, ultrastability, homeostatic adaptation, homeodynamic self — なぜ必要か: 摂動下で本質変数を保つ適応の古典モデル。
- **項目15 感覚の構造を内側から見つける** — 検索語: sensorimotor structure discovery, unsupervised sensorimotor learning — なぜ必要か: 段18 の感覚の獲得、受容器を増やすかどうかの判断材料。

## D. 結線の可塑性と記憶（core/circuit.jl の規則）
- **項目16 使われると保たれ、使われないと消える結線** — 検索語: activity-dependent synaptic pruning, structural plasticity, synapse elimination — なぜ必要か: 基体の結線維持・消去規則の生物学的裏づけ。
- **項目17 ★確かさ0の結びつき（silent synapse に当たる）** — 検索語: silent synapses, synaptic tagging and capture, latent connections — なぜ必要か: 確かさ0の沈殿だけの結びつきの扱い（項番83〜84、sed_fade）。★最優先。
- **項目18 ★能動的な忘却** — 検索語: active forgetting, biology of forgetting, memory decay — なぜ必要か: sed_fade、FORGET の周期を「受動的崩壊でなく能動過程」と見る根拠。★最優先。
- **項目19 恒常性の可塑性** — 検索語: homeostatic plasticity, synaptic scaling, BCM, metaplasticity — なぜ必要か: 可塑性自体を安定化する仕組みの参照。
- **項目20 ★手がかりの競合** — 検索語: Rescorla–Wagner, blocking, overshadowing, latent inhibition — なぜ必要か: 常時点いている受容器が確かさを奪う件（項番78〜79）の古典理論。★最優先。
- **項目21 ★組み合わせの学習** — 検索語: configural learning, XOR / negative patterning, linear separability — なぜ必要か: 未決「組み合わせを表せない基体」（閾値・c3）の位置づけ。★最優先。
- **項目22 馴化と定位反応** — 検索語: habituation, dishabituation, orienting reflex — なぜ必要か: orient.js の定位・馴化の古典的定義と判定基準。
- **項目23 二値の答えでの手柄の割り当て** — 検索語: credit assignment with binary feedback, eligibility traces, contrast learning — なぜ必要か: bin3 と対比の規則（項番71・74）の対照枠組み（強化学習は対照としてのみ）。

## E. 行為の選択・固定化・探索
- **項目24 ★固定化と経路依存** — 検索語: behavioral lock-in, perseveration, path dependence, generative entrenchment — なぜ必要か: 先に勝った運動が固定化する件、idle_first の理論的裏づけ。★最優先。
- **項目25 報酬を最大化しない探索** — 検索語: operant variability, behavioral variability, novelty-seeking, intrinsic motivation — なぜ必要か: 「最大化しない」を守る範囲での探索・変動性の議論。
- **項目26 行為の選択** — 検索語: action selection, winner-take-all, basal ganglia action selection — なぜ必要か: 段16 の「1歩に運動は一つ」、核の関門（core_gate）の設計根拠。
- **項目27 時間の計測と待つこと** — 検索語: interval timing, delayed response, response inhibition — なぜ必要か: turn.js の「待つこと」の時間計測モデル。

## F. 価値・維持費・資源（L2・ValueNeeded・KC）
- **項目28 ★構造を保つ費用** — 検索語: energy budget of neural signaling, metabolic cost of neural tissue, energy-efficient coding, expensive tissue — なぜ必要か: 「価値も自己産出も自分を保つ費用に支えられる」（項番85〜86）の定量的根拠。★最優先。
- **項目29 ★自給する機械** — 検索語: self-sufficient robots, basic cycles, energetic autonomy, microbial fuel cell robot — なぜ必要か: エネルギー自給を組み込んだ機械の先行事例。★最優先。
- **項目30 ★区画の採餌と枯渇** — 検索語: patch foraging, marginal value theorem, giving-up time — なぜ必要か: 区画の収量と、自分で減らした溜まりを読む交絡（項番81〜82）の分析枠組み。★最優先。
- **項目31 自分の行為による環境の改変** — 検索語: niche construction, agent-induced confounding, interventional vs observational learning — なぜ必要か: 行為が環境を作り変えることによる観測交絡の理論。
- **項目32 価値と生存可能性** — 検索語: viability-based semantic information, value from viability, interactivism — なぜ必要か: 価値を外部報酬でなく生存可能性から内生させる議論。
- **項目33 対照として読む枠組み（set point を外から入れる型）** — 検索語: homeostatic reinforcement learning, allostasis, free energy principle / active inference — なぜ必要か: M4（内生性）と比べるための対照材料。採る型ではない。

## G. 快・不快の上の層（後の段階、層の分離の設計）
- **項目34 機能としての快・不快と動機づけ** — 検索語: artificial emotion, hedonic quality, motivated autonomous robot — なぜ必要か: 快・不快を現象でなく機能として上層に置く設計の先行研究。
- **項目35 内受容と恒常性の感じ** — 検索語: interoception, homeostatic feelings, interoceptive inference — なぜ必要か: 内受容の機能と構造だけを扱い、phenomenal_claim には触れないための線引きの材料。
- **項目36 層に分けた制御** — 検索語: subsumption architecture, layered control, loose coupling between control layers — なぜ必要か: 下層と上層を密結合させない方針の古典的実装原則。

## H. 相手と世界（v2 以降のアプリ）
- **項目37 ★生と流し直しを区別する** — 検索語: perceptual crossing, double video paradigm, live vs replay interaction, contingency detection — なぜ必要か: 未決「生と流し直しが区別されない件」の実験パラダイム。★最優先。
- **項目38 参加的な意味づけ** — 検索語: participatory sense-making, interaction dynamics — なぜ必要か: 相手との相互作用で意味が立ち上がる過程の理論。
- **項目39 足場かけと発達の時期** — 検索語: scaffolding, developmental robotics, critical periods, curriculum — なぜ必要か: 保育期・学校期で来歴が決まる件の発達ロボティクス的裏づけ。
- **項目40 変わる世界への汎化** — 検索語: robustness to nonstationary environments, held-out environments, seasonal variability — なぜ必要か: 凍結・未知・無作為の世界での寿命を考える材料。

## I. 測り方と判定（監査・AGENCY-001）
- **項目41 自律と個体性の情報理論的な測り方** — 検索語: autonomy information theoretic, information theory of individuality, empowerment — なぜ必要か: 自律・個体性を操作的に測る情報理論的尺度。
- **項目42 主体性の操作的な定義と形式化** — 検索語: formal account of agency, minimal agency criteria, operationalizing agency — なぜ必要か: AGENCY-001 の監査対象を操作的に定義する先行形式化。
- **項目43 損傷と介入による因果の分析** — 検索語: lesion analysis dynamical neural networks, multi-perturbation Shapley value, knockout — なぜ必要か: 発信停止だけの介入で因果を読む方法論。
- **項目44 計算機実験の事前登録と再現性** — 検索語: preregistration computational modeling, ODD protocol, seed robustness, hypothesis freezing — なぜ必要か: freeze-*.txt の規律の裏づけ。

## J. 形式化と実装
- **項目45 最大不動点と余帰納法** — 検索語: Knaster–Tarski, greatest fixed point, coinduction, universal coalgebra, bisimulation — なぜ必要か: M1 の νΦ を扱う数理的道具立て。
- **項目46 ガロア接続・随伴と開いた系の圏論** — 検索語: Galois connections in systems, categorical systems theory, open dynamical systems — なぜ必要か: M2 と開放系の合成を扱う圏論的基盤。
- **項目47 定理証明器での検証** — 検索語: mechanized verification of dynamical systems, Lean formalization, verified simulation — なぜ必要か: Lean 形式化と検証済みシミュレーションの先行事例。
- **項目48 言語をまたいだビット単位の再現** — 検索語: correctly rounded libm, CORE-MATH, deterministic floating point, cross-platform bit reproducibility — なぜ必要か: openlibm・fdlibm で Julia・JS・Rust を一致させている件の裏づけ。
- **項目49 小型計算機・マイコンでの局所学習** — 検索語: on-device learning microcontroller, TinyML, neuromorphic local plasticity — なぜ必要か: Rust no_std の先にあるマイコン実装の見通し。
- **項目50 最小の身体を持つ主体** — 検索語: Braitenberg vehicles, minimally cognitive behavior, evolutionary robotics, enactive AI — なぜ必要か: 最小身体での認知・行為の古典的モデル群。

## K. 優先度低（参考）
- **項目51 LLM の役割** — 検索語: faithfulness of LLM explanations, Clever Hans, LLM as teacher — なぜ必要か: 段2 の盲検の通訳と、段17〜18 で LLM を感覚の入口や教育係に使った件の注意材料。

## L. 上層の追加分野（Muse リスト由来）
- **項目52 Φ_rich の重みづけ** — 検索語: Pareto frontier multi-objective optimization, diversity measures, structural complexity measures — なぜ必要か: (Φ_depth, Φ_div, Φ_level) の Pareto／合成という未決の決定に直結。
- **項目53 増殖の射の正確な定義** — 検索語: multilevel selection Price equation, reproduction vs generation, heredity and lineage — なぜ必要か: 発生／生殖の形式と世代間の豊かさ継承、多水準選択の形式化。
- **項目54 入れ子の圏論的足場** — 検索語: Grothendieck fibration, operads open systems wiring diagrams, hierarchical individuality — なぜ必要か: fibration へ拡張するか operad まで要るかという未確定の研究判断。
- **項目55 Σ-purity = 情報流非干渉** — 検索語: Goguen Meseguer noninterference, information flow security, taint analysis, metamorphic testing — なぜ必要か: メタ層の選択が個体に漏れないことの静的・動的検査の出典分野。
- **項目56 賭け W1–W6 と構成的独立性** — 検索語: independence proofs model construction, constructive independence, independence in formal systems — なぜ必要か: 賭けの文が対象層の公理から導けないことを示す方法論。
- **項目57 台帳と checker の意味論** — 検索語: soundness completeness decision procedure, witness validator, requirements traceability, specification coverage — なぜ必要か: checker が何を決定しているかの分類と、散文被覆監査の方法論。
- **項目58 検証の検証** — 検索語: mutation testing, adversarial validation, self-verification bias — なぜ必要か: 検査自体の空洞化を検出する仕組み（変異試験・敵対的検証）の根拠。
- **項目59 反証条件の方法論** — 検索語: Popper falsification, falsifiability criterion, severity testing — なぜ必要か: 反証条件 0/91 という負債をどう返すかの科学哲学的基準。
- **項目60 個体性 = ⟨系 S, 分解 D⟩** — 検索語: biological individuality Godfrey-Smith Pradeu, holobiont individuality, physiological vs evolutionary individuality — なぜ必要か: 分解依存の個体性（同じ基体が個体にもコロニーにもなる）の生物学哲学。
- **項目61 内生時間と機能終了** — 検索語: endogenous time, intrinsic time dynamical systems, organizational death autopoiesis — なぜ必要か: TemporalDC と、構造から導かれる機能終了の不可避性の理論的近接分野。
- **項目62 理論翻訳と二軸原則** — 検索語: theory translation interpretation between theories, functorial semantics, formal vs informal specification gap — なぜ必要か: 理論間翻訳の証書と、「certified は散文被覆を含意しない」区別の形式化／哲学。

---

# 収集論文


# bridge-protocol 論文収集 — グループ1（A章・B章、項目1〜11）

- 収集日: 2026-11-04
- 収集方針: 各論文の書誌情報と DOI は browser.search / browser.open で実際に確認したもののみ記載した。検証できなかった DOI は推測で作らず、その旨を明記した。報酬最大化の強化学習／最適化論文は収録していない。意識・現象性を主張する論文は除外し、機能と構造に関する論文のみを収録した（項目1の Thompson 2007 は起点として指定された書籍であり、オートポイエーシスと自律性の構造論の部分を対象とする）。

## A. 自己維持の理論

### 項目1 オートポイエーシスと作動閉包

- **Autopoiesis: The Organization of Living Systems, its Characterization and a Model**
  - 書誌情報: Varela, Francisco G.; Maturana, Humberto R.; Uribe, Ricardo (1974). *BioSystems*, 5(4), 187–196.
  - DOI: 10.1016/0303-2647(74)90031-8
  - 中心の主張: 生きている系を、その構成要素を産出し続ける過程のネットワークとして定義し、オートポイエーシスを作動的に閉じた組織として特徴づけた。あわせて最小の計算モデル（基質・触媒・リンクによる膜形成）を提示した。
  - 形式モデル／計算機実験: 有（セル・オートマトン型の最小シミュレーションを含む）
  - 対応項目: 項目1

- **Autopoiesis and Cognition: The Realization of the Living**
  - 書誌情報: Maturana, Humberto R.; Varela, Francisco J. (1980). 書籍、D. Reidel Publishing Company / Springer、Boston Studies in the Philosophy and History of Science, Vol. 42.
  - DOI: 10.1007/978-94-009-8947-4
  - 中心の主張: オートポイエーシスを生命の組織の必要十分な特徴づけとして体系化し、作動閉包と構造的カップリングの概念を定式化した古典的起点。
  - 形式モデル／計算機実験: 無（理論的定式化が中心）
  - 対応項目: 項目1

- **Mind in Life: Biology, Phenomenology, and the Sciences of Mind**
  - 書誌情報: Thompson, Evan (2007). 書籍、Harvard University Press。ISBN 978-0-674-02511-0。
  - DOI: DOIなし（書籍、本収集で DOI を確認できなかったため記載しない）
  - 中心の主張: オートポイエーシスと自律性（autonomy）を生命の組織原理として再構成し、自己産出する系が自らの生存条件に関して規範を内生させるという構造論を展開した。本収集では現象論ではなく自律性・自己維持の構造に関する議論を対象とする。
  - 形式モデル／計算機実験: 無（理論的統合が中心）
  - 対応項目: 項目1

### 項目2 制約の閉包

- **Biological Organisation as Closure of Constraints**
  - 書誌情報: Montévil, Maël; Mossio, Matteo (2015). *Journal of Theoretical Biology*, 372, 179–191.
  - DOI: 10.1016/j.jtbi.2015.02.029
  - 中心の主張: 生物学的組織を「制約の閉包」として定式化した。過程に作用しつつ当該時間スケールでは保存される制約同士が、互いに依存し合い維持し合うことで組織的閉包が成立し、熱力学的開放性と両立するとした。L3における自己産出を物質層ではなく組織層（制約の相互維持）で捉える根拠となる。
  - 形式モデル／計算機実験: 有（概念的・形式的な定式化あり。計算機実験は無）
  - 対応項目: 項目2

- **Biological Autonomy: A Philosophical and Theoretical Enquiry**
  - 書誌情報: Moreno, Alvaro; Mossio, Matteo (2015). 書籍、Springer、History, Philosophy and Theory of the Life Sciences, Vol. 12。
  - DOI: 10.1007/978-94-017-9837-2
  - 中心の主張: 生物学的自律性を、自己産出・自己維持する組織が自らの目標と規範を立て、自己の存続条件を促進する性質として体系化した。制約の閉包に基づく機能とエージェンシーの組織論的説明を与える。
  - 形式モデル／計算機実験: 無（理論書）
  - 対応項目: 項目2

### 項目3 Rosen の (M,R) 系と形式化

- **Organizational Invariance and Metabolic Closure: Analysis in Terms of (M,R) Systems**
  - 書誌情報: Letelier, Juan-Carlos; Soto-Andrade, Jorge; Guíñez Abarzúa, Flavio; Cornish-Bowden, Athel; Cárdenas, María Luz (2006). *Journal of Theoretical Biology*, 238(4), 949–961.
  - DOI: 10.1016/j.jtbi.2005.07.007
  - 中心の主張: Rosen の (M,R) 系における代謝的閉包を、代謝写像が不動点型の関数方程式の解として現れる形で明確化し、組織的不変性を持つ (M,R) 系の数学的実例と最小の自己触媒集合による分析を初めて与えた。
  - 形式モデル／計算機実験: 有（形式モデル。計算機実験は無）
  - 対応項目: 項目3

- **Closure to Efficient Causation, Computability and Artificial Life**
  - 書誌情報: Cárdenas, María Luz; Letelier, Juan-Carlos; Gutiérrez, Claudio; Cornish-Bowden, Athel; Soto-Andrade, Jorge (2010). *Journal of Theoretical Biology*, 263(1), 79–88.
  - DOI: 10.1016/j.jtbi.2009.11.010
  - 中心の主張: 生物は「効率因に対する閉包」を持ち、作動に必要な触媒が系内部で生成されなければならないことを論じ、その帰結として計算可能性（チューリング機械によるシミュレーション可能性）の問題を検討した。
  - 形式モデル／計算機実験: 有（形式モデル。計算機実験は無）
  - 対応項目: 項目3

- **A Biochemically-Realisable Relational Model of the Self-Manufacturing Cell**
  - 書誌情報: Hofmeyr, Jan-Hendrik S. (2021). *BioSystems*, 207, 104463.
  - DOI: 10.1016/j.biosystems.2021.104463
  - 中心の主張: 細胞内の効率因を触媒・細胞内環境・膜輸送体の3クラスに分け、それらが互いを産出して効率因への閉包をなすことを関係生物学の図式で定式化した。Rosen の (M,R) 系の生化学的実現困難を回避する (F,A) 系（fabrication–assembly system）を提示した。
  - 形式モデル／計算機実験: 有（関係図式による形式モデル。計算機実験は無）
  - 対応項目: 項目3

### 項目4 自己触媒集合

- **Detecting Autocatalytic, Self-Sustaining Sets in Chemical Reaction Systems**
  - 書誌情報: Hordijk, Wim; Steel, Mike (2004). *Journal of Theoretical Biology*, 227(4), 451–461.
  - DOI: 10.1016/j.jtbi.2003.11.020
  - 中心の主張: 反応系の中に自己触媒的で食物集合から持続可能な部分系（後の RAF 集合）が存在するかを判定する多項式時間アルゴリズムを与え、RAF 理論の標準的定式化の基礎を築いた。核となる反応集合の相互維持を計算可能にした点が重要である。
  - 形式モデル／計算機実験: 有（形式モデルと検出アルゴリズム）
  - 対応項目: 項目4

- **The Structure of Autocatalytic Sets: Evolvability, Enablement, and Emergence**
  - 書誌情報: Hordijk, Wim; Steel, Mike; Kauffman, Stuart (2012). *Acta Biotheoretica*, 60, 379–392.
  - DOI: 10.1007/s10441-012-9165-1
  - 中心の主張: Kauffman の集合的自己触媒の着想を RAF 集合として再構成し、その構造・進化可能性・新規反応の enablement を分析した。自己触媒集合が自己維持の単位として階層的に組み合わさりうることを示した。
  - 形式モデル／計算機実験: 有（形式モデルとシミュレーション）
  - 対応項目: 項目4

### 項目5 precariousness・adaptivity・規範の内生

- **Autopoiesis, Adaptivity, Teleology, Agency**
  - 書誌情報: Di Paolo, Ezequiel A. (2005). *Phenomenology and the Cognitive Sciences*, 4(4), 429–452.
  - DOI: 10.1007/s11097-005-9002-y
  - 中心の主張: オートポイエーシスだけでは sense-making を説明できないとし、自らの生存可能性（viability）の境界に関して自己を調節する能力として adaptivity を導入した。これにより系は precarious（放置すれば崩壊する）であることを前提に、内生的な規範と目的論が成立するとした。
  - 形式モデル／計算機実験: 無（概念的定式化が中心）
  - 対応項目: 項目5

- **Defining Agency: Individuality, Normativity, Asymmetry, and Spatio-temporality in Action**
  - 書誌情報: Barandiaran, Xabier E.; Di Paolo, Ezequiel A.; Rohde, Marieke (2009). *Adaptive Behavior*, 17(5), 367–386.
  - DOI: 10.1177/1059712309343819
  - 中心の主張: エージェンシーを、(a) 系自らが個体性を定義すること、(b) 環境との相互作用の能動的源泉であること（interactional asymmetry）、(c) 規範に関してその活動を調節すること、の3条件で定義した。規範が外部の報酬ではなく自己維持から内生することを明確化した（AGENCY-001 への直接の理論的根拠）。
  - 形式モデル／計算機実験: 無（概念的定義が中心）
  - 対応項目: 項目5

### 項目6 生存可能性の理論（viable と DC の区別）

- **Viability Theory**
  - 書誌情報: Aubin, Jean-Pierre (1991). 書籍、Birkhäuser Boston、Systems & Control: Foundations & Applications。2009年再刊（Modern Birkhäuser Classics）の DOI を確認した。
  - DOI: 10.1007/978-0-8176-4910-4（2009年再刊版の DOI。初版1991年）
  - 中心の主張: 制約集合（viability kernel）の内部に状態を保ち続ける発展（evolution）が存在する条件を、集合値解析と微分包含によって定式化した生存可能性理論の原典。「生き延びる軌道が存在すること」と「特定の目的関数を最適化すること」を峻別する形式枠組みを与える。
  - 形式モデル／計算機実験: 有（形式モデル。数値例を含む）
  - 対応項目: 項目6

- **Design for a Brain: The Origin of Adaptive Behaviour**
  - 書誌情報: Ashby, W. Ross (1960). 書籍、Chapman & Hall（第2版。初版1952年）。Springer 電子版の DOI を確認した。
  - DOI: 10.1007/978-94-015-1320-3（Springer 電子版）
  - 中心の主張: 生存に不可欠な変数（essential variables）を生理的限界内に保つことを適応と定義し、それが破れたときにパラメータ自体を変更する超安定性（ultrastability）を提唱した。viability を「本質変数が限界内にある状態の集合」として捉える先駆けである。
  - 形式モデル／計算機実験: 有（形式モデルとホームオスタットの実験装置の記述）
  - 対応項目: 項目6

## B. 自己維持の最小モデル

### 項目7 計算機上の最小オートポイエーシス

- **Thirty Years of Computational Autopoiesis: A Review**
  - 書誌情報: McMullin, Barry (2004). *Artificial Life*, 10(3), 277–295.
  - DOI: 10.1162/1064546041255548
  - 中心の主張: Varela, Maturana & Uribe の原モデルから SCL（Substrate-Catalyst-Link）モデルを含む計算論的オートポイエーシスの30年を総覧し、原モデルの再発見過程で明らかになった鎖状結合阻害などの実装上の要点と、計算媒体で自己産出を実現する際の課題を整理した。
  - 形式モデル／計算機実験: 有（レビュー対象として計算機実験を扱う）
  - 対応項目: 項目7

- **Autopoiesis and Cognition in the Game of Life**
  - 書誌情報: Beer, Randall D. (2004). *Artificial Life*, 10(3), 309–326.
  - DOI: 10.1162/1064546041255539
  - 中心の主張: Conway の Game of Life のグライダーをオートポイエーシスの観点から分析するプロジェクトを開始し、最小の時空間パターンに対して自己産出と自己区別をどう判定するかを論じた。
  - 形式モデル／計算機実験: 有（セル・オートマトンの計算機実験）
  - 対応項目: 項目7

- **Characterizing Autopoiesis in the Game of Life**
  - 書誌情報: Beer, Randall D. (2015). *Artificial Life*, 21(1), 1–19.
  - DOI: 10.1162/ARTL_a_00143
  - 中心の主張: Game of Life のコンパクトで再帰的な時空間パターンについて、オートポイエーシスの基準を精密化して適用し、どのパターンが自己維持する統一体とみなせるかを特徴づけた。
  - 形式モデル／計算機実験: 有（セル・オートマトンの計算機実験）
  - 対応項目: 項目7

- **Exploring the Space of Viable Configurations in a Model of Metabolism–Boundary Co-construction**
  - 書誌情報: Agmon, Eran; Gates, Alexander J.; Churavy, Valentin; Beer, Randall D. (2016). *Artificial Life*, 22(2), 153–171.
  - DOI: 10.1162/ARTL_a_00196
  - 中心の主張: 代謝と境界が共構成される濃度ダイナミクスの空間モデルを導入し、自己修復する配置と崩壊する配置を区別した上で、viable な配置の空間とその遷移を地図化した。頑健性を「摂動後に元の配置へ戻る傾向」、可塑性を「別の viable な配置へ移る傾向」として定量化した。
  - 形式モデル／計算機実験: 有（計算機実験）
  - 対応項目: 項目7

### 項目8 代謝に基づく行動

- **A Minimal Model of Metabolism-Based Chemotaxis**
  - 書誌情報: Egbert, Matthew D.; Barandiaran, Xabier E.; Di Paolo, Ezequiel A. (2010). *PLoS Computational Biology*, 6(12), e1001004.
  - DOI: 10.1371/journal.pcbi.1001004
  - 中心の主張: 受容体やシグナル伝達を仮定せず、自己触媒代謝の産物濃度がべん毛回転を直接調節するだけで、資源への走化性や阻害剤からの回避など細菌の代謝依存的走化性の諸パターンが再現できることを最小モデルで示した。維持費を払う代謝そのものが行為を駆動する例である。
  - 形式モデル／計算機実験: 有（計算機実験）
  - 対応項目: 項目8

- **Behavioral Metabolution: The Adaptive and Evolutionary Potential of Metabolism-Based Chemotaxis**
  - 書誌情報: Egbert, Matthew D.; Barandiaran, Xabier E.; Di Paolo, Ezequiel A. (2012). *Artificial Life*, 18(1), 1–25.
  - DOI: 10.1162/artl_a_00047
  - 中心の主張: 代謝に基づく走化性の最小モデルを用い、行動が化学的環境を選択し、その環境が代謝ネットワークの進化を方向づける正のフィードバック（behavioral metabolution）が生じることを示した。代謝と行為の結合が適応と進化の新しい形態を可能にするとした。
  - 形式モデル／計算機実験: 有（計算機実験）
  - 対応項目: 項目8

- **The Role of the Spatial Boundary in Autopoiesis**
  - 書誌情報: Virgo, Nathaniel; Egbert, Matthew D.; Froese, Tom (2011). In Kampis, G.; Karsai, I.; Szathmáry, E. (eds.), *Advances in Artificial Life. Darwin Meets von Neumann*（ECAL 2009 Proceedings）、Lecture Notes in Computer Science, Vol. 5777, Springer, 240–247.
  - DOI: 10.1007/978-3-642-21283-3_30
  - 中心の主張: オートポイエーシスにおける空間的境界の意義は過大評価されており、境界は系を空間的統一体として区別する役割を持つが、系を構成する過程の範囲まで画定するわけではないと論じた。物理的境界と作動上の限界を区別すべきだとした。
  - 形式モデル／計算機実験: 無（概念的分析が中心）
  - 対応項目: 項目8

### 項目9 原始細胞と chemoton

- **The Principles of Life**
  - 書誌情報: Gánti, Tibor (2003). 書籍、Oxford University Press（James Griesemer と Eörs Szathmáry による解説付き）。ISBN 978-0-19-850726-0。
  - DOI: DOIなし（書籍、本収集で DOI を確認できなかったため記載しない）
  - 中心の主張: 最小の生命モデル chemoton を、自己触媒的代謝・遺伝分子・膜という化学量論的に結合した3つの部分系からなる流体オートマトンとして提示し、生命の基準を循環的組織の観点から定式化した。
  - 形式モデル／計算機実験: 有（化学量論による形式モデル。計算機実験は限定的）
  - 対応項目: 項目9

- **A Universal Definition of Life: Autonomy and Open-ended Evolution**
  - 書誌情報: Ruiz-Mirazo, Kepa; Peretó, Juli; Moreno, Alvaro (2004). *Origins of Life and Evolution of Biospheres*, 34(3), 323–346.
  - DOI: 10.1023/B:ORIG.0000016440.53346.dc
  - 中心の主張: 生命を、個体レベルでは自律性（区画化された代謝による自己維持）、集合レベルでは開放的進化の能力を持つ系として定義し、原始細胞研究が満たすべき条件を提示した。オートポイエーシスの抽象性を批判し、進化能力を定義に組み込んだ。
  - 形式モデル／計算機実験: 無（理論的定義が中心）
  - 対応項目: 項目9

- **Protocells: Bridging Nonliving and Living Matter**
  - 書誌情報: Rasmussen, Steen; Bedau, Mark A.; Chen, Liaohai; Deamer, David; Packard, Norman H.; Stadler, Peter F. (eds.) (2008). 編著書、MIT Press。
  - DOI: 10.7551/mitpress/9780262182683.001.0001
  - 中心の主張: 容器（膜）・代謝・情報分子の3要素を組み合わせて非生物から最小細胞をボトムアップに組み立てる原始細胞研究の到達点と課題を集大成した。自己維持する区画の実験的・理論的モデルを横断的に収録する。
  - 形式モデル／計算機実験: 有（収録論文に形式モデルと実験を含む）
  - 対応項目: 項目9

### 項目10 人工化学

- **“The Arrival of the Fittest”: Toward a Theory of Biological Organization**
  - 書誌情報: Fontana, Walter; Buss, Leo W. (1994). *Bulletin of Mathematical Biology*, 56(1), 1–64.
  - DOI: 10.1007/BF02458289
  - 中心の主張: ラムダ計算に基づく人工化学 AlChemy を構築し、分子の衝突を関数適用として表すことで、自己複製する対象の水準（Level 0）、自己維持する組織の水準（Level 1）、その組織同士が結合したメタ組織（Level 2）が汎用的に出現することを示した。組織を「自己維持を保証する機能的関係の閉包」として定式化した。
  - 形式モデル／計算機実験: 有（形式モデルと計算機実験）
  - 対応項目: 項目10

- **What Would Be Conserved if “the Tape Were Played Twice”?**
  - 書誌情報: Fontana, Walter; Buss, Leo W. (1994). *Proceedings of the National Academy of Sciences of the United States of America*, 91, 757–761.
  - DOI: DOI未確認（掲載誌・巻・ページは複数資料で確認したが、DOI は本収集で検証できなかったため推測で記載しない）
  - 中心の主張: 同じ人工化学を用い、(i) 自己複製対象のハイパーサイクル、(ii) 自己複製が阻害された場合の自己維持組織、(iii) 自己維持組織同士の結合による高次組織、が抽象化の汎用的帰結として再現すると論じた。
  - 形式モデル／計算機実験: 有（形式モデルと計算機実験）
  - 対応項目: 項目10

- **Chemical Organisation Theory**
  - 書誌情報: Dittrich, Peter; Speroni di Fenizio, Pietro (2007). *Bulletin of Mathematical Biology*, 69(4), 1199–1231.
  - DOI: 10.1007/s11538-006-9130-8
  - 中心の主張: 化学組織（chemical organisation）を、閉じていて（反応の生成物が集合内に留まり）かつ自己維持的（消費される種が集合内で再生される）な種の集合として定義し、組織が格子構造をなすことを示した。反応ネットワークの自己維持構造を集合論的に抽出する形式枠組みである。
  - 形式モデル／計算機実験: 有（形式モデル）
  - 対応項目: 項目10

### 項目11 自己修復・再生と冗長性・縮退

- **Degeneracy and Complexity in Biological Systems**
  - 書誌情報: Edelman, Gerald M.; Gally, Joseph A. (2001). *Proceedings of the National Academy of Sciences of the United States of America*, 98(24), 13763–13768.
  - DOI: 10.1073/pnas.231499798
  - 中心の主張: 縮退（degeneracy）を「構造的に異なる要素が同じ機能・出力を果たしうる性質」と定義し、同一要素の複製である冗長性（redundancy）と区別した。縮退は遺伝暗号から免疫系・神経系まで遍在し、複雑性と頑健性の源泉であり、自然選択の必然的帰結だと論じた。自己維持の頑健性を測る際に冗長性と縮退を混同してはならない根拠となる。
  - 形式モデル／計算機実験: 無（概念的整理と事例分析が中心）
  - 対応項目: 項目11

- **Growing Neural Cellular Automata**
  - 書誌情報: Mordvintsev, Alexander; Randazzo, Ettore; Niklasson, Eyvind; Levin, Michael (2020). *Distill*, 5(2), e23.
  - DOI: 10.23915/distill.00023
  - 中心の主張: セル・オートマトンの更新規則を小規模なニューラルネットで置き換え、単一細胞から目標パターンへ成長し、損傷されてもパターンを再生（自己修復）するモデルを学習で得た。局所規則のみから全体形態の維持と再生が成立する計算例である。なお本モデルは外部の目標パターンへの損失で訓練されており、規範は内生ではなく外部から与えられる点で、内生的自己維持とは対照として位置づける。
  - 形式モデル／計算機実験: 有（計算機実験）
  - 対応項目: 項目11

## 収集状況のまとめ

- 収集論文総数: 29件
- 未収集項目: なし（項目1〜11のすべてについて最低1件の代表論文を、書誌情報と DOI（または DOI が無いことの明記）付きで収集した）
- DOI に関する注記: Thompson (2007) と Gánti (2003) は書籍で DOI を確認できなかったため「DOIなし（書籍）」と明記した。Fontana & Buss (1994, PNAS) は書誌を確認したが DOI を検証できなかったため「DOI未確認」と明記し、推測の DOI は記載していない。Aubin (1991) と Ashby (1960) は再刊・電子版の DOI を確認し、その旨を併記した。


# bridge-protocol 論文収集 — Group 2（C章・D章／項目12〜23）

- 担当： C章「感覚運動の結合」・D章「結線の可塑性と記憶」
- 収集方針： 機能と構造のみを扱う論文を採用し、意識・現象性を中心的主張とする論文は除外した。ただし項目12で指定された O'Regan & Noë (2001) は感覚運動随伴性（SMC）理論の原点として、現象性への言及を切り離し、運動に依存する感覚変化の法則という機能的・構造的側面のみを要約した。
- 検証方法： 全ての DOI と書誌情報を browser.search / browser.open で実在確認した。DOI が存在しない書籍・古典的書籍章については推測で作らず、その旨を明記した。
- 凡例： 各論文に「書誌情報／DOI／中心の主張／形式モデル・計算機実験の有無／対応項目番号」を付した。項目23は指示どおり強化学習を「対照」としてのみ採用し、その旨を明記した。

## C. 感覚運動の結合

### 項目12 感覚運動随伴性

- **O'Regan, J. K., & Noë, A. (2001). A sensorimotor account of vision and visual consciousness. *Behavioral and Brain Sciences*, 24(5), 939–973.**
  - DOI: 10.1017/S0140525X01000115
  - 中心の主張： 知覚は内部表象の生成ではなく、自己の運動によって感覚入力がどう変わるかという感覚運動随伴性（SMC）の法則を身体的に掌握する活動である。機能的には「運動→感覚変化」の依存構造そのものが知覚の単位になる。
  - 形式モデル／計算機実験： 無（理論的枠組みの提示。数理モデルやシミュレーションは含まない）
  - 対応項目： 12

- **Buhrmann, T., Di Paolo, E. A., & Barandiaran, X. E. (2013). A dynamical systems account of sensorimotor contingencies. *Frontiers in Psychology*, 4, 285.**
  - DOI: 10.3389/fpsyg.2013.00285
  - 中心の主張： SMCを力学系として操作的に再定義し、sensorimotor environment（開ループの運動誘発感覚変化）、habitat（閉ループ軌道）、coordination（機能的役割を持つ安定パターン）、strategy（その規範的組織）の4水準に分けた。これによりSMCを軌道・アトラクタとして観測可能な概念にした。
  - 形式モデル／計算機実験： 有（力学系による形式化。概念モデルと数理的定義が中心）
  - 対応項目： 12

- **Di Paolo, E. A., Buhrmann, T., & Barandiaran, X. E. (2017). *Sensorimotor Life: An Enactive Proposal*. Oxford University Press.**
  - DOI: 10.1093/acprof:oso/9780198786849.001.0001
  - 中心の主張： SMC、習慣、自律性を一つの枠組みに統合し、感覚運動の関与（engagement）が自己維持的な組織として安定化する過程として行為主体（agency）を説明する。項目12の総括的出典であり、項目13の習慣論の土台でもある。
  - 形式モデル／計算機実験： 有（力学系モデルと既存シミュレーション研究の統合的検討を含む。書籍自体は理論書）
  - 対応項目： 12

### 項目13 ★自己維持する感覚運動の型としての習慣

- **Egbert, M. D., & Barandiaran, X. E. (2014). Modeling habits as self-sustaining patterns of sensorimotor behavior. *Frontiers in Human Neuroscience*, 8, 590. ★**
  - DOI: 10.3389/fnhum.2014.00590
  - 中心の主張： 習慣を刺激—反応の固定ではなく、代謝過程と同様に自己を維持する感覚運動パターンとして捉える。反復で沈殿したパターンは、それが実行されることで自らを再生産し、実行されなければ崩壊する「感覚運動の生命形態」である。
  - 形式モデル／計算機実験： 有（Iterant Deformable Sensorimotor Medium: IDSM による計算モデルとシミュレーション。ノードの変形可能な媒体上で習慣が形成・競合・消滅する様子を示す）
  - 対応項目： 13

- **Egbert, M. D., & Cañamero, L. (2014). Habit-Based Regulation of Essential Variables. In *Proceedings of ALIFE 14: The Fourteenth International Conference on the Synthesis and Simulation of Living Systems* (pp. 168–175). MIT Press. ★**
  - DOI: 10.1162/978-0-262-32621-6-ch029
  - 中心の主張： 本質的変数（essential variables）が生存範囲を逸脱したときにのみ可塑性が働くホメオスタシス的制御とIDSM型の習慣形成を結合し、習慣が内状態の調節そのものを担うことを示した。使われる結線が保たれ、使われない習慣が消えるという沈殿／消去の力学を、調節の失敗と結びつけてモデル化している。
  - 形式モデル／計算機実験： 有（可塑的コントローラを持つエージェントの計算機シミュレーション）
  - 対応項目： 13

### 項目14 ホメオスタットと超安定性

- **Ashby, W. R. (1952). *Design for a Brain: The Origin of Adaptive Behaviour*. Chapman & Hall.（第2版 1960）**
  - DOI: DOIなし（書籍）
  - 中心の主張： 本質的変数が限界を超えたときだけステップ機構がパラメータをランダムに切り替え、安定な組み合わせが見つかるまで探索を続ける「超安定性（ultrastability）」を提案し、ホメオスタットで実装した。適応とは、逸脱を契機とする再配線の選択過程であるという原型を与える。
  - 形式モデル／計算機実験： 有（数理的定式化とホメオスタットという実機による検証）
  - 対応項目： 14

- **Di Paolo, E. A. (2000). Homeostatic adaptation to inversion of the visual field and other sensorimotor disruptions. In *From Animals to Animats 6: Proceedings of the 6th International Conference on Simulation of Adaptive Behavior* (pp. 440–449). MIT Press.**
  - DOI: 10.7551/mitpress/3120.003.0047
  - 中心の主張： Ashbyの超安定性を連続時間リカレント神経回路に移植し、ニューロンの発火率が目標範囲を外れたときにのみシナプス可塑性が働くホメオスタティック適応で、視野反転等の感覚運動攪乱に再適応できることを示した。
  - 形式モデル／計算機実験： 有（進化させた神経コントローラを持つ自律エージェントの計算機シミュレーション）
  - 対応項目： 14

- **Iizuka, H., & Di Paolo, E. A. (2008). Extended homeostatic adaptation: Improving the link between internal and behavioural stability. In *From Animals to Animats 10* (Lecture Notes in Computer Science, pp. 1–11). Springer.**
  - DOI: 10.1007/978-3-540-69134-1_1
  - 中心の主張： 感覚入力がない状態でも内部ダイナミクスが枯渇しないよう拡張したホメオスタティック適応を提案し、「望ましい行動のとき内部が安定し、望ましくない行動のとき不安定になる」という正負両方向の連関で選択することで、未経験の形態的攪乱への適応力と進化可能性が大幅に上がることを示した。
  - 形式モデル／計算機実験： 有（シミュレーション車両エージェントによる比較実験）
  - 対応項目： 14

- **Ikegami, T., & Suzuki, K. (2008). From a homeostatic to a homeodynamic self. *BioSystems*, 91(2), 388–400.**
  - DOI: 10.1016/j.biosystems.2007.05.014
  - 中心の主張： ホメオスタシスは静的な平衡維持ではなく、自ら動き続けることで維持される状態（homeodynamic self）へ移行しうる。Ashby型の超安定性（生存制約を破ったときのランダム探索）を組み込んだ2つの細胞モデルで、恒常性から自律的な自己運動への転移を検討した。
  - 形式モデル／計算機実験： 有（2種類の計算細胞モデルによるシミュレーション）
  - 対応項目： 14

### 項目15 感覚の構造を内側から見つける

- **Philipona, D., O'Regan, J. K., & Nadal, J.-P. (2003). Is there something out there? Inferring space from sensorimotor dependencies. *Neural Computation*, 15(9), 2029–2049.**
  - DOI: 10.1162/089976603322297278
  - 中心の主張： 感覚器や身体の構造を一切知らないエージェントでも、自己の運動で相殺できる感覚変化と相殺できない変化（環境由来）を数えることで、空間の次元と外部世界の存在を感覚運動依存性だけから推論できる。感覚の意味づけなしに構造を内側から発見する原型アルゴリズムである（段18の感覚獲得に対応）。
  - 形式モデル／計算機実験： 有（数理的定式化とアルゴリズムの提示。行列の階数による次元推定）
  - 対応項目： 15

- **Laflaquière, A., O'Regan, J. K., Argentieri, S., Gas, B., & Terekhov, A. V. (2015). Learning agent's spatial configuration from sensorimotor invariants. *Robotics and Autonomous Systems*, 71, 49–59.**
  - DOI: 10.1016/j.robot.2015.01.003
  - 中心の主張： 解釈されていないセンサとモータしか持たないロボットが、感覚運動流の中の不変量（invariants）を教師なしで抽出することで、自己の空間的配置を学習できることを示した。Philiponaらの理論を実ロボット寄りの学習問題へ展開した研究である。
  - 形式モデル／計算機実験： 有（感覚運動不変量に基づく学習手法の定式化とロボットシミュレーションによる検証）
  - 対応項目： 15

## D. 結線の可塑性と記憶

### 項目16 使われると保たれ使われないと消える結線

- **Faust, T. E., Gunner, G., & Schafer, D. P. (2021). Mechanisms governing activity-dependent synaptic pruning in the developing mammalian CNS. *Nature Reviews Neuroscience*, 22(11), 657–673.**
- DOI: 10.1038/s41583-021-00507-y
- 中心の主張： 発達期の哺乳類中枢神経系では、活動の多いシナプスが維持・強化され、活動の少ないシナプスが補体等の「eat-me」信号とグリアによる貪食で物理的に除去される。活動依存的な競合こそが残る結線と消える結線を決めるという総説である。
- 形式モデル／計算機実験： 無（実験知見の総説。形式モデルは含まない）
- 対応項目： 16

- **Fu, M., & Zuo, Y. (2011). Experience-dependent structural plasticity in the cortex. *Trends in Neurosciences*, 34(4), 177–187.**
- DOI: 10.1016/j.tins.2011.02.001
- 中心の主張： 経験は皮質のスパインの新生・拡大・縮小・消失を通じて回路を物理的に組み替える。使われるスパインは安定化して長期に残り、使われないスパインは退縮・除去されるという構造的可塑性が、機能的可塑性に先行・随伴することを示した総説である。
- 形式モデル／計算機実験： 無（in vivo イメージング知見の総説。形式モデルは含まない）
- 対応項目： 16

### 項目17 ★確かさ0の結びつき（silent synapse）

- **Kerchner, G. A., & Nicoll, R. A. (2008). Silent synapses and the emergence of a postsynaptic mechanism for LTP. *Nature Reviews Neuroscience*, 9(11), 813–825. ★**
- DOI: 10.1038/nrn2501
- 中心の主張： NMDA受容体のみを持ちAMPA受容体を持たないサイレントシナプスは、通常の伝達では「確かさ0」として沈黙しているが、構造的には存在し、LTPによってAMPA受容体が挿入されると機能的な結線として顕在化する。bridge-protocolにおける「確かさ0の沈殿だけの結びつき」（項番83〜84、sed_fade）の生物学的対応物である。
- 形式モデル／計算機実験： 無（電気生理学知見の総説。形式モデルは含まない）
- 対応項目： 17

- **Frey, U., & Morris, R. G. M. (1997). Synaptic tagging and long-term potentiation. *Nature*, 385(6616), 533–536. ★**
- DOI: 10.1038/385533a0
- 中心の主張： 弱い刺激で生じたシナプスには蛋白合成に依存しない短命の「タグ」だけが残り（3時間以内に消衰）、その間に強い刺激で作られた可塑性関連蛋白を捕捉（capture）できた場合にのみ後期LTPとして固定される。痕跡だけが残り、捕捉がなければ消えるという潜在的結びつきの機構を示した（synaptic tagging and capture仮説の原論文）。
- 形式モデル／計算機実験： 無（海馬スライスの電気生理実験に基づく仮説提示。計算モデルは含まない）
- 対応項目： 17

### 項目18 ★能動的な忘却

- **Davis, R. L., & Zhong, Y. (2017). The Biology of Forgetting — A Perspective. *Neuron*, 95(3), 490–503. ★**
- DOI: 10.1016/j.neuron.2017.05.039
- 中心の主張： 忘却は痕跡の受動的な崩壊ではなく、脳が能動的に実行する管理過程である。特にドーパミン性の「忘却細胞」からエングラム細胞への信号がRac1/Cofilin経路を介してアクチン骨格を組み替え、記憶痕跡を恒常的に侵食する内因性忘却（intrinsic forgetting）がデフォルト状態だと論じる。bridge-protocolの sed_fade と FORGET 周期の直接の根拠になる。
- 形式モデル／計算機実験： 無（ショウジョウバエ等での分子・細胞実験知見の総説／展望。形式モデルは含まない）
- 対応項目： 18

- **Hardt, O., Nader, K., & Nadel, L. (2013). Decay happens: The role of active forgetting in memory. *Trends in Cognitive Sciences*, 17(3), 111–120. ★**
- DOI: 10.1016/j.tics.2013.01.001
- 中心の主張： 減衰（decay）は物質の不安定さによる偶然ではなく、AMPA受容体のエンドサイトーシス等によって能動的かつ調節的に実行される過程であり、記憶が保たれるのは忘却過程に抗して維持機構が働く場合に限ると論じる。Davis & Zhong (2017) と独立に「能動的忘却」を理論化した論文である。
- 形式モデル／計算機実験： 無（理論的総説。形式モデル・計算機実験は含まない）
- 対応項目： 18

### 項目19 恒常性の可塑性

- **Turrigiano, G. G., & Nelson, S. B. (2004). Homeostatic plasticity in the developing nervous system. *Nature Reviews Neuroscience*, 5(2), 97–107.**
- DOI: 10.1038/nrn1327
- 中心の主張： Hebb型可塑性の正のフィードバックによる暴走を防ぐため、ニューロンは発火率を目標範囲に保つ恒常的可塑性（シナプス・スケーリング、内因性興奮性の調節等）を備える。全シナプスを一様に上下させるスケーリングにより、相対的な重み比（学習内容）を保ったまま全体の利得だけを調節できる。
- 形式モデル／計算機実験： 無（実験知見の総説。形式モデルは含まない）
- 対応項目： 19

- **Bienenstock, E. L., Cooper, L. N., & Munro, P. W. (1982). Theory for the development of neuron selectivity: Orientation specificity and binocular interaction in visual cortex. *Journal of Neuroscience*, 2(1), 32–48.**
- DOI: 10.1523/JNEUROSCI.02-01-00032.1982
- 中心の主張： シナプス後活動が低いときはLTD、高いときはLTPが起こり、その閾値（modification threshold）自体が過去の平均活動に応じて滑動するBCM規則を提案した。メタ可塑性（可塑性の可塑性）の原点であり、恒常性の可塑性を形式モデルとして与える。
- 形式モデル／計算機実験： 有（数理モデルと視覚皮質の選択性発達に関する計算機シミュレーション）
- 対応項目： 19

### 項目20 ★手がかりの競合

- **Rescorla, R. A., & Wagner, A. R. (1972). A theory of Pavlovian conditioning: Variations in the effectiveness of reinforcement and nonreinforcement. In A. H. Black & W. F. Prokasy (Eds.), *Classical Conditioning II: Current Research and Theory* (pp. 64–99). Appleton-Century-Crofts. ★**
- DOI: DOIなし（書籍章）
- 中心の主張： 学習量は予測誤差（λ − ΣV）に比例するという誤差修正規則を定式化した。既に結果を予測する手がかりがあると誤差が0になり、新しい手がかりは学習されない（blocking）。複合刺激では全手がかりが誤差を奪い合うため overshadowing が生じる。bridge-protocolにおける「常時点いている受容器が確かさを奪う件」（項番78〜79）の古典的モデルである。
- 形式モデル／計算機実験： 有（数理モデル。ΔV = αβ(λ − ΣV) という試行ごとの更新式を提示）
- 対応項目： 20

- **Kamin, L. J. (1969). Predictability, surprise, attention, and conditioning. In B. A. Campbell & R. M. Church (Eds.), *Punishment and Aversive Behavior* (pp. 279–296). Appleton-Century-Crofts. ★**
- DOI: DOIなし（書籍章）
- 中心の主張： 先行して条件づけられた刺激と複合で提示された新しい刺激は、対提示回数にかかわらずほとんど条件づけられない（blocking効果の発見）。学習には単なる近接性ではなく「驚き（予測の裏切り）」が必要であることを示し、Rescorla–Wagnerモデルの実験的起点となった。
- 形式モデル／計算機実験： 無（ラットの条件性情動反応による行動実験。形式モデルは含まない。モデル化は Rescorla & Wagner 1972 が担当）
- 対応項目： 20

- **Lubow, R. E., & Moore, A. U. (1959). Latent inhibition: The effect of nonreinforced pre-exposure to the conditional stimulus. *Journal of Comparative and Physiological Psychology*, 52(4), 415–419. ★**
- DOI: 10.1037/h0046700
- 中心の主張： 結果を伴わずに事前曝露された刺激は、その後の条件づけが遅れる（潜在抑制 latent inhibition の発見）。常時提示されて結果と結びつかなかった手がかりは「無関連」として処理され、新しい結びつきの確かさを奪う。常時点灯する受容器の問題と同型の現象である。
- 形式モデル／計算機実験： 無（動物の条件づけ実験。形式モデルは含まない）
- 対応項目： 20

### 項目21 ★組み合わせの学習

- **Pearce, J. M. (1994). Similarity and discrimination: A selective review and a connectionist model. *Psychological Review*, 101(4), 587–607. ★**
- DOI: 10.1037/0033-295X.101.4.587
- 中心の主張： 要素還元的な Rescorla–Wagner 型理論では説明できない弁別を、刺激複合全体を1つの形態（configuration）として符号化する形態的（configural）コネクショニストモデルで説明した。negative patterning（A+、B+、AB−）のような非線形分離可能な課題は、複合専用の表象があって初めて解ける。
- 形式モデル／計算機実験： 有（コネクショニスト・ネットワークによる形式モデルとシミュレーション）
- 対応項目： 21

- **Minsky, M., & Papert, S. (1969). *Perceptrons: An Introduction to Computational Geometry*. MIT Press. ★**
- DOI: DOIなし（書籍）
- 中心の主張： 単層パーセプトロン（線形閾値素子）は線形分離可能な関数しか計算できず、XOR（parity）や連結性（connectedness）の述語は原理的に表せないことを証明した。bridge-protocolにおける「組み合わせを表せない基体（閾値・c3）」の限界を定める古典である。中間表象なしに組み合わせ課題は解けないことの根拠になる。
- 形式モデル／計算機実験： 有（数学的証明。線形分離可能性と order の概念による計算可能性の解析）
- 対応項目： 21

### 項目22 馴化と定位反応

- **Thompson, R. F., & Spencer, W. A. (1966). Habituation: A model phenomenon for the study of neuronal substrates of behavior. *Psychological Review*, 73(1), 16–43.**
- DOI: 10.1037/h0022681
- 中心の主張： 反復提示による反応減弱（馴化）が感覚適応や筋疲労ではなく中枢過程であることを示し、そのパラメトリック特性（刺激特異性、脱馴化、頻度・強度依存性等9項目）を定式化した。馴化研究の基礎文献であり、orient.js の「繰り返しへの応答低下」の根拠になる。
- 形式モデル／計算機実験： 無（脊髄ネコの屈曲反射等の神経生理実験の総説的検討。計算モデルは含まない）
- 対応項目： 22

- **Rankin, C. H., Abrams, T., Barry, R. J., Bhatnagar, S., Clayton, D. F., Colombo, J., Coppola, G., Geyer, M. A., Glanzman, D. L., Marsland, S., McSweeney, F. K., Wilson, D. A., Wu, C.-F., & Thompson, R. F. (2009). Habituation revisited: An updated and revised description of the behavioral characteristics of habituation. *Neurobiology of Learning and Memory*, 92(2), 135–138.**
- DOI: 10.1016/j.nlm.2008.09.012
- 中心の主張： Thompson & Spencer (1966) の特性一覧を40年後の知見で改訂し、長期馴化、刺激特異性、脱馴化、馴化の馴化等を含む10特性として再提示した。種や系を越えて馴化と呼べる条件の現行の標準定義である。
- 形式モデル／計算機実験： 無（専門家合意に基づく特性の総説。形式モデルは含まない）
- 対応項目： 22

- **Sokolov, E. N. (1963). Higher nervous functions: The orienting reflex. *Annual Review of Physiology*, 25, 545–580.（単著書版： *Perception and the Conditioned Reflex*, Pergamon Press, 1963）**
- DOI: 10.1146/annurev.ph.25.030163.002553
- 中心の主張： 新奇な刺激は定位反射（orienting reflex）を引き起こし、脳内に形成された刺激の神経モデル（neuronal model）と入力が一致すれば反応は馴化し、不一致が生じれば定位反応が回復する（comparator説）。馴化を「予測モデルとの一致による応答抑制」として説明する枠組みを与え、orient.js の新奇性検出に対応する。
- 形式モデル／計算機実験： 無（神経生理実験に基づく理論。計算機モデルは含まないが、比較器という機能モデルを提示）
- 対応項目： 22

### 項目23 二値の答えでの手柄の割り当て

> 注記： 本項目の2件はいずれも強化学習の文献であり、指示どおり bridge-protocol の学習規則そのものとしてではなく、bin3 と対比の規則（項番71・74）を読むための「対照」として採用した。採用理由は、二値的な成否信号だけで過去のどの結線に手柄（credit）を配分するかという問題設定と、その解法（適格性トレース eligibility trace）の構造が対比可能だからである。

- **Barto, A. G., Sutton, R. S., & Anderson, C. W. (1983). Neuronlike adaptive elements that can solve difficult learning control problems. *IEEE Transactions on Systems, Man, and Cybernetics*, SMC-13(5), 834–846.**
- DOI: 10.1109/TSMC.1983.6313077
- 中心の主張： 報酬／罰というスカラー信号のみから学習する actor–critic 型の適応素子（ASE/ACE）を提案し、遅れて届く二値的評価でも、直前の活動に残る適格性トレースを通じて手柄を過去の素子へ配分できることを倒立振子課題で示した。対照として：大域的な成否信号＋トレースという配分方式が、局所的な対比で学ぶ方式とどう違うかを際立たせる。
- 形式モデル／計算機実験： 有（数理モデルと倒立振子バランス課題の計算機シミュレーション）
- 対応項目： 23

- **Izhikevich, E. M. (2007). Solving the distal reward problem through linkage of STDP and dopamine signaling. *Cerebral Cortex*, 17(10), 2443–2452.**
- DOI: 10.1093/cercor/bhl152
- 中心の主張： STDPで各シナプスに書き込まれる適格性トレース（数秒で減衰）が、遅れて到着したドーパミン信号と出会ったときにのみ重み変化へ変換されることで、遠隔報酬問題（distal reward problem）＝時間的に離れた手柄の割り当てがシナプス局所の機構で解けることを示した。対照として：トレースの減衰時定数と大域信号への依存が、bridge-protocol 側の局所対比規則との差異を明確にする。
- 形式モデル／計算機実験： 有（皮質スパイキング・ネットワークの計算機シミュレーション）
- 対応項目： 23

---

## 収集サマリー

- 収集論文総数： 29件
- 内訳： 項目12：3件／項目13：2件／項目14：4件／項目15：2件／項目16：2件／項目17：2件／項目18：2件／項目19：2件／項目20：3件／項目21：2件／項目22：3件／項目23：2件
- ★項目（13・17・18・20・21）： 全て2件以上を確保した（20は3件）。
- 未収集項目： なし。全項目（12〜23）で最低1件以上を収集した。
- DOIなしと明記したもの： Ashby (1952)・Rescorla & Wagner (1972)・Kamin (1969)・Minsky & Papert (1969) の4件。いずれも DOI 制度以前の書籍／書籍章であり、推測 DOI は記載していない。


# bridge-protocol 論文収集 — E章・F章（項目24〜33）

担当：E章・F章。書誌情報とDOIは browser.search / browser.open で検証したもののみ記載し、検証できないものはDOIを推測せず「DOIなし」と明記した。意識・現象性を中心に主張する論文は除外し、機能と構造に関する論文のみを採用した。

## E. 行為の選択・固定化・探索

### 項目24 固定化と経路依存（★最優先）
キーワード：behavioral lock-in, perseveration, path dependence, generative entrenchment。先に成立した構造・運動が後の選択肢を拘束し、固定化する問題に対応する。idle_first の読み替え材料。

- **Wimsatt, W. C. (1986). Developmental constraints, generative entrenchment, and the innate-acquired distinction. In W. Bechtel (Ed.), *Integrating Scientific Disciplines* (pp. 185–208). Martinus Nijhoff.**
- DOI: 10.1007/978-94-010-9435-1_11
- 中心の主張：ある特徴が生成的固定化（generative entrenchment）している程度は、それに依存する下流の特徴の多さで決まる。早く現れ多くが依存する構造ほど変更コストが高く、進化・発生の両面で保守的になる。
- 形式モデルや計算機実験の有無：無（理論的論考）
- 対応する項目番号：24

- **Schank, J. C., & Wimsatt, W. C. (1986). Generative entrenchment and evolution. *PSA: Proceedings of the Biennial Meeting of the Philosophy of Science Association*, 1986(2), 33–60.**
- DOI: 10.1086/psaprocbienmeetp.1986.2.192789
- 中心の主張：生成的固定化の度合いは、複雑系の生成構造のうちどれだけがその要素の存在・活動に依存するかで測られる。固定化の高い要素ほど進化的変更に対して保守的であり、初期構造が後続構造をロックインする経路依存が生じる。
- 形式モデルや計算機実験の有無：有（固定化の効果を組み込んだ複雑構造のモデル群を提示）
- 対応する項目番号：24

### 項目25 報酬を最大化しない探索
キーワード：operant variability, behavioral variability, novelty-seeking, intrinsic motivation。注意：外部報酬の最大化として読めるものは採用せず、「最大化しない」探索として読める範囲に限る。

- **Neuringer, A. (2002). Operant variability: Evidence, functions, and theory. *Psychonomic Bulletin & Review*, 9(4), 672–705.**
- DOI: 10.3758/BF03196324
- 中心の主張：行動の変動性（variability）自体がオペラントとして強化されうる次元であり、繰り返しではなく「変えること」が選択される。変動性は新規行動の生成と適応的探索の基盤になる。
- 形式モデルや計算機実験の有無：無（動物・ヒト実験の総説・理論論文）
- 対応する項目番号：25

- **Oudeyer, P.-Y., Kaplan, F., & Hafner, V. V. (2007). Intrinsic Motivation Systems for Autonomous Mental Development. *IEEE Transactions on Evolutionary Computation*, 11(2), 265–286.**
- DOI: 10.1109/TEVC.2006.890271
- 中心の主張：学習進展（learning progress）が大きい状況へ向かう内発的動機づけ（Intelligent Adaptive Curiosity）により、ロボットは外部報酬なしに、予測しやすすぎず難しすぎない課題を自律的に選び発達的軌道を生成する。本項目では外部報酬最大化ではなく、学習進展に基づく探索として読む範囲に限って採用する。
- 形式モデルや計算機実験の有無：有（計算モデルとロボット実験）
- 対応する項目番号：25

### 項目26 行為の選択
キーワード：action selection, winner-take-all, basal ganglia action selection。段16「1歩に運動は一つ」、核の関門 core_gate に対応する。

- **Tyrrell, T. (1993). The use of hierarchies for action selection. *Adaptive Behavior*, 1(4), 387–420.**
- DOI: 10.1177/105971239300100401
- 中心の主張：階層型の行為選択では各階層で決定するのではなく、最終的な行動経路（behavioral final path）の水準でのみ決定する free-flow hierarchy の方が、動物の観察とシミュレーションの双方に合う。各時点で実行される行動は一つに収束する構造を扱う基礎文献。
- 形式モデルや計算機実験の有無：有（計算機シミュレーション）
- 対応する項目番号：26

- **Maes, P. (1989). How to do the right thing. *Connection Science*, 1(3), 291–323.**
- DOI: 10.1080/09540098908915643
- 中心の主張：行為ネットワークにおける活性拡散（spreading activation）により、中央の計画者なしにボトムアップに一つの行為が選択される。競合する行為モジュール間の相互作用から winner-take-all 的な選択が創発する古典的機構。
- 形式モデルや計算機実験の有無：有（計算モデル／行為ネットワークのシミュレーション）
- 対応する項目番号：26

- **Redgrave, P., Prescott, T. J., & Gurney, K. (1999). The basal ganglia: A vertebrate solution to the selection problem? *Neuroscience*, 89(4), 1009–1023.**
- DOI: 10.1016/S0306-4522(98)00319-4
- 中心の主張：大脳基底核は、限られた運動・認知資源へのアクセスをめぐる競合を解消する集中型の選択装置（centralized selection device）として進化したとする。複数の行為系が同時に資源を求める「選択問題」に対する脊椎動物の解であり、core_gate の神経的対応物として読める。
- 形式モデルや計算機実験の有無：無（理論・解剖学的レビュー、概念モデル）
- 対応する項目番号：26

- **Prescott, T. J., Montes González, F. M., Gurney, K., Humphries, M. D., & Redgrave, P. (2006). A robot model of the basal ganglia: Behavior and intrinsic processing. *Neural Networks*, 19(1), 31–61.**
- DOI: 10.1016/j.neunet.2005.06.049
- 中心の主張：大脳基底核の計算モデルをロボット制御アーキテクチャに埋め込むことで、感覚・動機づけ条件の広い範囲で有効な行為選択とクリーンな切り替えが実現できることを実証した。基底核＝選択機構仮説の強い検証例。
- 形式モデルや計算機実験の有無：有（計算モデルとロボット実験）
- 対応する項目番号：26

### 項目27 時間の計測と待つこと
キーワード：interval timing, delayed response, response inhibition。turn.js の「待つこと」に対応する。

- **Gibbon, J. (1977). Scalar expectancy theory and Weber's law in animal timing. *Psychological Review*, 84(3), 279–325.**
- DOI: 10.1037/0033-295X.84.3.279
- 中心の主張：動物は内部時計・作業記憶・参照記憶と比較・決定過程からなるスカラー計時（scalar timing）で強化までの時間を推定し、期待の比によって反応する。計時のばらつきが区間長に比例する（スカラー性）ため、「待つ」長さの不確実性自体が構造的に決まる。
- 形式モデルや計算機実験の有無：有（形式モデル：Scalar Expectancy Theory）
- 対応する項目番号：27

- **Buhusi, C. V., & Meck, W. H. (2005). What makes us tick? Functional and neural mechanisms of interval timing. *Nature Reviews Neuroscience*, 6(10), 755–765.**
- DOI: 10.1038/nrn1764
- 中心の主張：秒から分単位の区間計時（interval timing）は線条体拍頻度モデルなど皮質‐線条体回路で担われ、ドーパミン系が時計速度を調節する。待機や反応抑制のタイミングはこの計時機構の精度と注意配分に依存する。
- 形式モデルや計算機実験の有無：有（形式モデルを含む総説：striatal beat-frequency model 等）
- 対応する項目番号：27

## F. 価値・維持費・資源

### 項目28 構造を保つ費用（★最優先）
キーワード：energy budget of neural signaling, metabolic cost of neural tissue, energy-efficient coding, expensive tissue。価値も自己産出も自分を保つ費用に支えられるという論点（項番85〜86）に対応する。

- **Attwell, D., & Laughlin, S. B. (2001). An energy budget for signaling in the grey matter of the brain. *Journal of Cerebral Blood Flow & Metabolism*, 21(10), 1133–1145.**
- DOI: 10.1097/00004647-200110000-00001
- 中心の主張：齧歯類灰白質の信号伝達のエネルギー収支を定量化すると、活動電位が約47%、グルタミン酸のシナプス後作用が約34%、静止電位の維持が約13%を占める。神経活動という構造の維持・運用には常時大きな代謝費用がかかることを示す基礎文献。
- 形式モデルや計算機実験の有無：有（解剖・生理データに基づく定量的エネルギーバジェットモデル）
- 対応する項目番号：28

- **Niven, J. E., & Laughlin, S. B. (2008). Energy limitation as a selective pressure on the evolution of sensory systems. *Journal of Experimental Biology*, 211(11), 1792–1804.**
- DOI: 10.1242/jeb.017574
- 中心の主張：神経系は適応的行動を生む利益とエネルギー消費という費用のトレードオフにさらされており、エネルギー制限が感覚系の進化に対する選択圧になる。過剰な処理能力は維持費を増やすため、構造は費用によって切り詰められる。
- 形式モデルや計算機実験の有無：無（レビュー）
- 対応する項目番号：28

### 項目29 自給する機械（★最優先）
キーワード：self-sufficient robots, basic cycles, energetic autonomy, microbial fuel cell robot。

- **McFarland, D., & Spier, E. (1997). Basic cycles, utility and opportunism in self-sufficient robots. *Robotics and Autonomous Systems*, 20(2–4), 179–190.**
- DOI: 10.1016/S0921-8890(96)00069-3
- 中心の主張：自給的（self-sufficient）ロボットは「働く‐燃料を探す‐補給する」という基本サイクル（basic cycle）を回し続けなければならず、その遂行は所有者の効用で評価される。エネルギー収支と仕事のトレードオフ（two-resource problem）と機会主義的行動を cue-deficit モデルで扱う。
- 形式モデルや計算機実験の有無：有（形式モデル：cue-deficit model）
- 対応する項目番号：29

- **Melhuish, C., Ieropoulos, I., Greenman, J., & Horsfield, I. (2006). Energetically autonomous robots: Food for thought. *Autonomous Robots*, 21(3), 187–198.**
- DOI: 10.1007/s10514-006-6574-5
- 中心の主張：EcoBot-II は未精製の昆虫バイオマスを搭載微生物燃料電池で電気に変換し、外部電源なしで動作する初のロボットであり、12日間の走行・光走性・温度センシング・無線送信を自給エネルギーで実行した。自給は制御の問題である前に代謝の問題であることを実証する。
- 形式モデルや計算機実験の有無：有（実機実験）
- 対応する項目番号：29

- **Walter, W. G. (1950). An imitation of life. *Scientific American*, 42–45.**
- DOI: DOIなし（書籍・旧誌記事に準ずるものとして明記。1950年の Scientific American 記事で、検証可能なDOIは付与されていない）
- 中心の主張：光電管と接触センサと2本の真空管だけからなる亀型ロボット Machina speculatrix（Elmer / Elsie）が、探索・光への接近・障害物回避・充電場所への回帰といった一見目的的な行動を示す。最小の機械でも環境とのフィードバックで自律的に見える行動が生成される古典的起点。
- 形式モデルや計算機実験の有無：有（実機製作・実機実験）
- 対応する項目番号：29

### 項目30 区画の採餌と枯渇（★最優先）
キーワード：patch foraging, marginal value theorem, giving-up time。区画の収量と自分で減らした溜まりを読む交絡（項番81〜82）に対応する。

- **Charnov, E. L. (1976). Optimal foraging, the marginal value theorem. *Theoretical Population Biology*, 9(2), 129–136.**
- DOI: 10.1016/0040-5809(76)90040-X
- 中心の主張：限界価値定理（Marginal Value Theorem）は、パッチ内の瞬間的収量率が環境全体の平均収量率まで下がった時点でパッチを離れるのが最適だと予測する。採餌者自身がパッチを枯渇させるため、収量の低下は環境の性質と自分の行為の交絡として読まなければならない。
- 形式モデルや計算機実験の有無：有（形式モデル）
- 対応する項目番号：30

- **Charnov, E. L., & Parker, G. A. (1995). Dimensionless invariants from foraging theory's marginal value theorem. *Proceedings of the National Academy of Sciences of the United States of America*, 92(5), 1446–1450.**
- DOI: 10.1073/pnas.92.5.1446
- 中心の主張：限界価値定理から、移動時間とパッチ滞在時間の比などスケールに依存しない無次元不変量が導かれ、異なる環境・種でも共通する離脱規則の検証が可能になる。giving-up の判断を平均率との比較として定式化し直した展開文献。
- 形式モデルや計算機実験の有無：有（形式モデル）
- 対応する項目番号：30

### 項目31 自分の行為による環境の改変
キーワード：niche construction, agent-induced confounding, interventional vs observational learning。自分の行為が観測対象である環境自体を変えてしまう交絡に対応する。

- **Odling-Smee, F. J., Laland, K. N., & Feldman, M. W. (2003). *Niche Construction: The Neglected Process in Evolution*. Princeton University Press. (Monographs in Population Biology, 37)**
- DOI: 10.1515/9781400847266
- 中心の主張：生物は環境に適応するだけでなく、巣作りや土壌改変などによって自らの選択環境を能動的に改変し（niche construction）、その改変が生態的継承を通じて後世代の選択圧を変える。観測される環境は主体の行為の結果でもあるため、観察と介入の区別が進化でも本質的になる。
- 形式モデルや計算機実験の有無：有（形式モデルを含む単著：集団遺伝学的モデル等）
- 対応する項目番号：31

- **Odling-Smee, F. J., Laland, K. N., & Feldman, M. W. (1996). Niche construction. *The American Naturalist*, 147(4), 641–648.**
- DOI: 10.1086/285870
- 中心の主張：ニッチ構築を進化過程として初めて簡潔に定式化し、生物による環境改変が遺伝子頻度の変化とフィードバックする過程を示した短報。上記単著の先行論文として、行為→環境→選択の循環を最小形で読める。
- 形式モデルや計算機実験の有無：有（形式モデル）
- 対応する項目番号：31

### 項目32 価値と生存可能性
キーワード：viability-based semantic information, value from viability, interactivism。

- **Kolchinsky, A., & Wolpert, D. H. (2018). Semantic information, autonomous agency and non-equilibrium statistical physics. *Interface Focus*, 8(6), 20180041.**
- DOI: 10.1098/rsfs.2018.0041
- 中心の主張：意味的情報（semantic information）を、系が自らの存続（viability）を維持するために因果的に必要な、環境についての統語的情報と定義する。情報の価値は相関の大きさではなく、生存可能性への寄与によって測られる。
- 形式モデルや計算機実験の有無：有（形式モデル：非平衡統計物理に基づく定式化と viability の介入的測定）
- 対応する項目番号：32

- **Bickhard, M. H. (2009). The interactivist model. *Synthese*, 166(3), 547–591.**
- DOI: 10.1007/s11229-008-9375-x
- 中心の主張：表象と規範性は、自己維持的な相互作用系（interactivism）における機能の成否から創発する。系が自らの存続を保つ相互作用の anticipations が崩れることが「誤り」や価値の起源となり、価値は外部から与えられるのではなく生存維持の構造から生じる。注：現象性ではなく機能・規範性の創発として読む範囲で採用する。
- 形式モデルや計算機実験の有無：無（理論論文：プロセス形而上学に基づくモデル提示）
- 対応する項目番号：32

### 項目33 対照として読む枠組み（set point を外から入れる型）
キーワード：homeostatic reinforcement learning, allostasis, free energy principle / active inference。注意：以下はすべて、目標値（set point）や事前分布を外から与える型であり、M4の内生性と比べる「対照」としてのみ採用する。各論文に「対照」と明記する。

- **Keramati, M., & Gutkin, B. (2014). Homeostatic reinforcement learning for integrating reward collection and physiological stability. *eLife*, 3, e04811.**
- DOI: 10.7554/eLife.04811
- 中心の主張：報酬を、内部状態が外から設定された恒常的 set point からどれだけ離れたかの減少として定義し直すことで、報酬収集と生理的安定を単一の強化学習で統合する。対照としての要点：set point はモデル外部から与えられ、内生的に生成されない。
- 形式モデルや計算機実験の有無：有（数理モデルと計算機シミュレーション）
- 対応する項目番号：33（対照）

- **Sterling, P. (2012). Allostasis: A model of predictive regulation. *Physiology & Behavior*, 106(1), 5–15.**
- DOI: 10.1016/j.physbeh.2011.06.004
- 中心の主張：アロスタシスは、需要を予測して事前に備えることで効率的な調節を行う枠組みであり、固定した set point への反応的回復としての恒常性を批判する。対照としての要点：予測の基準となる需要・範囲は調節系にあらかじめ組み込まれたものとして扱われ、その起源自体は問われない。
- 形式モデルや計算機実験の有無：無（理論的レビュー）
- 対応する項目番号：33（対照）

- **Kirchhoff, M., Parr, T., Palacios, E., Friston, K., & Kiverstein, J. (2018). The Markov blankets of life: Autonomy, active inference and the free energy principle. *Journal of the Royal Society Interface*, 15(138), 20170792.**
- DOI: 10.1098/rsif.2017.0792
- 中心の主張：自律系の境界を Markov blanket として統計的に定義し、内部状態が自由エネルギーを最小化する能動的推論（active inference）によって自律性が自己組織化すると論じる。対照としての要点：存続すべき状態の事前選好（prior preferences）は枠組みの前提として与えられ、M4の内生性と対比できる。
- 形式モデルや計算機実験の有無：有（形式モデル：Markov blanket と自由エネルギー原理の定式化）
- 対応する項目番号：33（対照）


# bridge-protocol 論文収集 G章・H章（項目34〜40）

- 担当範囲: 項目34〜40
- 検証方法: 各論文の書誌情報とDOIは browser.search / browser.open 相当の検索結果で実際に確認したもののみ記載した。検証できなかったものは推測でDOIを作らず「DOIなし」と明記した。
- 除外方針: 意識や現象性（phenomenal_claim）を中心主張とする論文は収集対象から外し、機能と構造に関する主張のみを要約した。特に項目35ではこの方針を厳格に適用した。

## G. 快・不快の上の層

### 項目34 機能としての快・不快と動機づけ

- Cañamero, D. (1997). "Modeling motivations and emotions as a basis for intelligent behavior." *Proceedings of the First International Conference on Autonomous Agents (AGENTS '97)*, ACM, pp. 148–155.
  - DOI: 10.1145/267658.267688
  - 中心の主張: 動機づけと情動を、生存に関わる内部状態の評価と行動選択を結ぶ機能としてアーキテクチャに組み込むことで、自律エージェントの適応的な行動選択が可能になるとした初期の提案。
  - 形式モデルや計算機実験の有無: 有（動機・情動アーキテクチャの計算モデルと自律エージェントによる検討）
  - 対応項目: 34

- Lewis, M., & Cañamero, L. (2016). "Hedonic quality or reward? A study of basic pleasure in homeostasis and decision making of a motivated autonomous robot." *Adaptive Behavior*, 24(5), 267–291.
  - DOI: 10.1177/1059712316666331
  - 中心の主張: 欲求充足に直結しない快（hedonic quality）も、ホルモン調節を介した知覚の変調として実装すると、恒常性維持と意思決定の生存可能性（viability）を報酬だけの場合より改善しうることをロボット実験で示した。
  - 形式モデルや計算機実験の有無: 有（生物学に着想を得たロボットアーキテクチャと実ロボット実験）
  - 対応項目: 34

- Man, K., & Damasio, A. (2019). "Homeostasis and soft robotics in the design of feeling machines." *Nature Machine Intelligence*, 1(10), 446–452.
  - DOI: 10.1038/s42256-019-0103-7
  - 中心の主張: 生命維持（homeostasis）の原理に従い、内部状態の逸脱を評価して自己を守るよう設計された脆弱なソフトロボットは、多様な環境での機能改善につながる評価過程を持ちうると提案する。本収集では現象性に関する主張は採用せず、恒常性評価を動機づけ機能として使う設計論の部分のみを対象とする。
  - 形式モデルや計算機実験の有無: 無（Perspective論文。設計原理の提案であり、新規の計算機実験は含まない）
  - 対応項目: 34

### 項目35 内受容と恒常性の感じ

> 本項目では phenomenal_claim に触れる主張は集めていない。以下はいずれも、内受容の経路・構造・予測処理という機能と構造の記述に限って要約したものである。自覚や主観的経験そのものを根拠づける論文としては扱わない。

- Craig, A. D. (2002). "How do you feel? Interoception: the sense of the physiological condition of the body." *Nature Reviews Neuroscience*, 3(8), 655–666.
  - DOI: 10.1038/nrn894
  - 中心の主張: 身体の生理状態は、脊髄 lamina I 経路と迷走神経求心路を介して島皮質へ段階的に再表象されるという神経解剖学的な構造を整理し、内受容を恒常性状態の求心性表象として位置づけた。本収集ではこの経路と表象構造の部分のみを用いる。
  - 形式モデルや計算機実験の有無: 無（神経解剖学レビュー。新規の形式モデル・計算機実験は含まない）
  - 対応項目: 35

- Barrett, L. F., & Simmons, W. K. (2015). "Interoceptive predictions in the brain." *Nature Reviews Neuroscience*, 16(7), 419–429.
  - DOI: 10.1038/nrn3950
  - 中心の主張: 内受容は受動的な読み取りではなく、内臓運動皮質が身体状態について予測を出し、予測誤差で更新する能動的推論として機能するという EPIC（Embodied Predictive Interoception Coding）モデルを、皮質間結合の解剖モデルと統合して提示した。
  - 形式モデルや計算機実験の有無: 有（形式モデル有: EPICモデル／能動的推論の枠組み。著者らによる新規の計算機実験は含まない）
  - 対応項目: 35

- Khalsa, S. S., Adolphs, R., Cameron, O. G., Critchley, H. D., Davenport, P. W., Feinstein, J. S., et al. (2018). "Interoception and Mental Health: A Roadmap." *Biological Psychiatry: Cognitive Neuroscience and Neuroimaging*, 3(6), 501–513.
  - DOI: 10.1016/j.bpsc.2017.12.004
  - 中心の主張: 神経系が体内信号を感知・解釈・統合して身体内部状態の逐次的なマッピングを作る過程として内受容を定義し、心臓・呼吸・消化器など複数系統にわたる測定法と神経回路の整理、および計算理論と恒常性制御を結ぶ今後の研究課題を示した機能的ロードマップ。
  - 形式モデルや計算機実験の有無: 無（コンセンサス・レビュー／ロードマップ。新規の計算機実験は含まない）
  - 対応項目: 35

### 項目36 層に分けた制御

- Brooks, R. A. (1986). "A robust layered control system for a mobile robot." *IEEE Journal of Robotics and Automation*, 2(1), 14–23.
  - DOI: 10.1109/JRA.1986.1087032
  - 中心の主張: 制御を能力の段階ごとに非同期モジュールからなる層に分け、層間は低帯域の通信で結び、上位層は下位層の出力を抑制・包摂（subsume）できるが下位層は上位層なしでも動作する。これにより中央の世界モデルへの密結合を避け、頑健で柔軟な移動ロボット制御（subsumption architecture）が得られる。
  - 形式モデルや計算機実験の有無: 有（アーキテクチャの形式的な記述と実移動ロボットへの実装・実証）
  - 対応項目: 36

- Brooks, R. A. (1991). "Intelligence without representation." *Artificial Intelligence*, 47(1–3), 139–159.
  - DOI: 10.1016/0004-3702(91)90053-M
  - 中心の主張: 知的行動は明示的な中央表象を介さなくても、環境に直接結合した層状の感覚運動ループの積み重ねから生じうると論じ、層を疎に結合させる設計方針の理論的根拠を与えた。
  - 形式モデルや計算機実験の有無: 無（理論論文。項目36の設計方針の根拠として収集）
  - 対応項目: 36

## H. 相手と世界

### 項目37 ★生と流し直しを区別する

> ★最優先項目。未決論点「生と流し直しが区別されない件」に直結するため4件収集した。いずれも、刺激の内容（形）が同じでも、相手が今こちらに応答しているかどうか（随伴性）で反応が変わることを示す実験である。裏返せば、区別は内容ではなく時間的な随伴性への感受性に依存する。

- Auvray, M., Lenay, C., & Stewart, J. (2009). "Perceptual interactions in a minimalist virtual environment." *New Ideas in Psychology*, 27(1), 32–47.
  - DOI: 10.1016/j.newideapsych.2007.12.002
  - 中心の主張: 1次元仮想空間で触覚刺激だけを頼りにし合う perceptual crossing 実験で、参加者は固定物や相手の影（記録された動き）と、双方向に応答し合う生きた相手とを、相互的な交差が成立するときに区別できることを示した。ただし一方向の協調だけでは記録との区別は難しくなることも報告されている。
  - 形式モデルや計算機実験の有無: 有（最小限の仮想環境を用いた人間参加者実験）
  - 対応項目: 37

- Murray, L., & Trevarthen, C. (1985). "Emotional regulation of interactions between two-month-olds and their mothers." In T. M. Field & N. A. Fox (Eds.), *Social Perception in Infants*, Ablex, pp. 177–197.
  - DOI: DOIなし（書籍）
  - 中心の主張: double video paradigm の原点。生後2か月の乳児と母親が閉回路テレビ越しに対面し、母親の映像を生（live）から直前の録画の流し直し（replay）に切り替えると、映像の内容は同じでも母親が乳児に応答しなくなるため、乳児は混乱し、やがて引きこもる反応を示した。
  - 形式モデルや計算機実験の有無: 有（double video 装置を用いた人間参加者実験。形式モデルは含まない）
  - 対応項目: 37

- Nadel, J., Carchon, I., Kervella, C., Marcelli, D., & Réserbat-Plantey, D. (1999). "Expectancies for social contingency in 2-month-olds." *Developmental Science*, 2(2), 164–173.
  - DOI: 10.1111/1467-7687.00065
  - 中心の主張: double video 方式で母親の生の映像を録画に差し替えて相互作用の同期を崩すと、生後2か月の乳児は微笑みを止め、視線を逸らし、不快を示し、生の映像に戻すと回復した。乳児が社会的随伴性への期待を既に持つことを示す追証。
  - 形式モデルや計算機実験の有無: 有（double video 装置を用いた人間参加者実験。形式モデルは含まない）
  - 対応項目: 37

- Watson, J. S. (1972). "Smiling, cooing and 'the game'." *Merrill-Palmer Quarterly*, 18, 323–339.
  - DOI: DOIなし（当該誌の当該年次論文としてDOIは確認できなかった）
  - 中心の主張: 生後2か月頃の乳児が、自分の頭の動きに随伴して反応する対象に対しては頭の動きを増やし微笑み・クーイングを示す一方、非随伴な（yoked）条件ではそうならないことを示し、随伴性の検出が社会的応答の基礎になるという仮説の源流となった。
  - 形式モデルや計算機実験の有無: 有（乳児を対象とする随伴性操作実験。形式モデルは含まない）
  - 対応項目: 37

### 項目38 参加的な意味づけ

- De Jaegher, H., & Di Paolo, E. (2007). "Participatory sense-making: An enactive approach to social cognition." *Phenomenology and the Cognitive Sciences*, 6(4), 485–507.
  - DOI: 10.1007/s11097-007-9076-9
  - 中心の主張: 意味づけ（sense-making）は個人の頭の中だけで完結せず、相互作用の過程自体が一定の自律性を持ち、参加者同士の意味づけを共に調整・生成する（participatory sense-making）と定義した。社会的認知を、他者の内面の推論ではなく協調と崩壊を含む相互作用ダイナミクスとして捉え直す枠組み。
  - 形式モデルや計算機実験の有無: 無（理論論文。相互作用の自律性の操作的定義と概念的定式化が中心で、新規の計算機実験は含まない）
  - 対応項目: 38

### 項目39 足場かけと発達の時期

- Lungarella, M., Metta, G., Pfeifer, R., & Sandini, G. (2003). "Developmental robotics: a survey." *Connection Science*, 15(4), 151–190.
  - DOI: 10.1080/09540090310001655110
  - 中心の主張: 発達ロボティクスのサーベイ。身体の成長、環境との相互作用、養育者による足場かけ（scaffolding）を含む発達の制約と段階をロボットに実装することで、開かれた生涯学習と発達理論の検証の両方が可能になると整理した。
  - 形式モデルや計算機実験の有無: 無（サーベイ論文。対象分野のモデルと実験を総覧するもので、新規の計算機実験は含まない）
  - 対応項目: 39

- Asada, M., Hosoda, K., Kuniyoshi, Y., Ishiguro, H., Inui, T., Yoshikawa, Y., Ogino, M., & Yoshida, C. (2009). "Cognitive developmental robotics: A survey." *IEEE Transactions on Autonomous Mental Development*, 1(1), 12–34.
  - DOI: 10.1109/TAMD.2009.2021702
  - 中心の主張: 認知的発達ロボティクスは、身体性、社会的相互作用、発達段階の遷移を一体として設計・検証する枠組みであり、養育者との相互作用を含む発達過程そのものが認知構造の来歴を決めることを、構成的手法（作ることで理解する）によって示そうとするサーベイ。
  - 形式モデルや計算機実験の有無: 無（サーベイ論文。新規の計算機実験は含まないが、構成的モデル群を総覧する）
  - 対応項目: 39

### 項目40 変わる世界への汎化

> 注記: 未知環境（held-out）への汎化と訓練分布の無作為化による頑健化については下記の確立した実験的証拠を収集した。一方、「季節変動のような緩やかな非定常変化の下での寿命」を直接の主題とする論文は今回の検証範囲では特定できなかったため、その点は下記2件からの外挿として扱い、直接証拠としては主張しない。

- Cobbe, K., Klimov, O., Hesse, C., Kim, T., & Schulman, J. (2019). "Quantifying Generalization in Reinforcement Learning." *Proceedings of the 36th International Conference on Machine Learning (ICML 2019)*, PMLR 97, pp. 1282–1289.
  - DOI: DOIなし（会議録。PMLR Proceedingsとして刊行され、DOIは付与されていないことを確認した）
  - 中心の主張: 手続き生成環境 CoinRun で訓練環境とテスト環境を分離（held-out）して測ると、深層強化学習エージェントは驚くほど大きな訓練集合でも過適合し、訓練と同じ環境で測る従来の評価では汎化能力を過大評価すること、正則化やデータ拡張等が汎化を改善することを定量化した。
  - 形式モデルや計算機実験の有無: 有（手続き生成環境による大規模な計算機実験と汎化ギャップの定量化）
  - 対応項目: 40

- Tobin, J., Fong, R., Ray, A., Schneider, J., Zaremba, W., & Abbeel, P. (2017). "Domain Randomization for Transferring Deep Neural Networks from Simulation to the Real World." *2017 IEEE/RSJ International Conference on Intelligent Robots and Systems (IROS)*, pp. 23–30.
  - DOI: 10.1109/IROS.2017.8202133
  - 中心の主張: シミュレータの描画条件を訓練時に無作為化（domain randomization）すると、現実の画像に一度も触れていないモデルでも実世界の物体位置推定へ転移できる。訓練時に世界を意図的にばらつかせることが、未知の実環境への頑健化の方策になることを示した。
  - 形式モデルや計算機実験の有無: 有（シミュレーションでの計算機実験と実ロボットでの物体位置推定実験）
  - 対応項目: 40

---

## 収集状況のまとめ

- 収集論文総数: 17件
- 項目34: 3件 / 項目35: 3件 / 項目36: 2件 / 項目37（★）: 4件 / 項目38: 1件 / 項目39: 2件 / 項目40: 2件
- 未収集項目: なし（全項目で最低1件を確保した）
- 留意点: 項目40のうち「季節変動など緩やかな非定常変化の下での寿命」を直接扱う論文は特定できず、held-out汎化と無作為化による頑健化の証拠で代替した。項目35は、現象性を主張する主張を避け、経路・構造・予測処理の機能的記述のみに限定した。


# bridge-protocol 論文収集 — Group 5（I章・J章・K章、項目41〜51）

- 収集方針：意識・現象性を主張する論文は除外し、機能と構造に関する論文のみを収録した。
- 各論文に、書誌情報・DOI・中心の主張（日本語1〜2行）・形式モデル／計算機実験の有無・対応項目番号を明記した。
- DOIは browser.search / browser.open で実際に確認したもののみ記載し、確認できない書籍は「DOIなし（書籍）」と明記した。推測でDOIは作っていない。
- 収集日：2026-11-04

## I. 測り方と判定

### 項目41 自律と個体性の情報理論的な測り方

- **Bertschinger, Nils; Olbrich, Eckehard; Ay, Nihat; Jost, Jürgen (2008). "Autonomy: An information theoretic perspective." *Biosystems*, 91(2), 331–345.**
  - DOI: 10.1016/j.biosystems.2007.05.018
  - 中心の主張：自律を、系の内部状態が環境の履歴にどれだけ依存せず自己の過去に依存するかという情報理論量で測る。環境に決定されない度合い（non-heteronomy）を操作的に定義した基礎論文。
  - 形式モデル／計算機実験：形式モデル 有（情報理論的定式化）／計算機実験 無（理論論文）
  - 対応項目：41

- **Krakauer, David; Bertschinger, Nils; Olbrich, Eckehard; Flack, Jessica C.; Ay, Nihat (2020). "The information theory of individuality." *Theory in Biosciences*, 139(2), 209–223.**
  - DOI: 10.1007/s12064-020-00313-7
  - 中心の主張：個体とは過去の情報を未来へ伝播させることで時間的統合性を保つ集合体であると定義し、情報理論とグラフィカルモデルで個体性を階層横断的に測る枠組み（ITI）を提案する。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 無（理論・概念の定式化が中心）
  - 対応項目：41

- **Klyubin, Alexander S.; Polani, Daniel; Nehaniv, Chrystopher L. (2005). "Empowerment: A universal agent-centric measure of control." *Proceedings of the 2005 IEEE Congress on Evolutionary Computation (CEC 2005)*, Vol. 1, 128–135.**
  - DOI: 10.1109/CEC.2005.1554676
  - 中心の主張：エンパワーメントを、行動列から将来の感覚状態へのチャネル容量として定義し、課題に依存しない主体中心の制御量として提案する。自律の測り方の代表的な計算可能指標。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有
  - 対応項目：41
  - 補足：同著者らによる姉妹論文 "All Else Being Equal Be Empowered"（*Advances in Artificial Life, ECAL 2005*, LNCS 3630, 744–753、DOI: 10.1007/11553090_75）も同一概念の別発表として確認した。

### 項目42 主体性の操作的な定義と形式化

- **McGregor, Simon (2017). "The Bayesian stance: Equations for 'as-if' sensorimotor agency." *Adaptive Behavior*, 25(2), 72–82.**
  - DOI: 10.1177/1059712317700501
  - 中心の主張：Pearlの因果形式化で主体‐環境境界の物理変数を同定し、それをベイズ意思決定理論の変数に対応させることで、「as-if」主体性を力学系・確率過程の言葉だけで厳密に定義する。主体か否かの二分ではなく解釈の論理を形式化する点が操作的である。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 無
  - 対応項目：42

- **Biehl, Martin; Ikegami, Takashi; Polani, Daniel (2016). "Towards information based spatiotemporal patterns as a foundation for agent representation in dynamical systems." *Proceedings of the Artificial Life Conference 2016 (ALIFE 2016)*, MIT Press, 722–729.**
  - DOI: 10.7551/978-0-262-33936-0-ch115
  - 中心の主張：既存の主体表現は代謝・運動性・反事実的変動と両立しないと論じ、情報理論的な「統合された時空間パターン」を力学系における主体定義の基礎単位として提案する。主体判定をパターンの統合性に帰着させる操作的提案。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 無（思考実験と定式化が中心）
  - 対応項目：42
  - 補足：Biehlの博士論文 *Formal approaches to a definition of agents*（2017, University of Hertfordshire）は学位論文のためDOIなし。本項目では査読付き会議論文の方を収録した。

### 項目43 損傷と介入による因果の分析

- **Aharonov, Ranit; Segev, Lior; Meilijson, Isaac; Ruppin, Eytan (2003). "Localization of Function via Lesion Analysis." *Neural Computation*, 15(4), 885–913.**
  - DOI: 10.1162/08997660360581949
  - 中心の主張：多重損傷（multi-lesion）に対するネットワーク性能を最もよく予測するよう各要素へ寄与値を割り当てる Functional Contribution Analysis（FCA）を提案し、進化させた自律エージェントのニューロコントローラで検証した。単一損傷だけでは機能局在を誤ることを示す基礎。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有
  - 対応項目：43

- **Keinan, Alon; Sandbank, Ben; Hilgetag, Claus C.; Meilijson, Isaac; Ruppin, Eytan (2004). "Fair Attribution of Functional Contribution in Artificial and Biological Networks." *Neural Computation*, 16(9), 1887–1915.**
  - DOI: 10.1162/0899766041336387
  - 中心の主張：多重摂動データから因果的な機能局在を導く Multi-perturbation Shapley value Analysis（MSA）を、ゲーム理論のShapley値に基づく公理的で拡張可能な方法として提示する。要素間相互作用まで含めて寄与を公平に配分できる。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有（神経生理モデルと可逆的不活性化データへの適用）
  - 対応項目：43

- **Keinan, Alon; Hilgetag, Claus C.; Meilijson, Isaac; Ruppin, Eytan (2004). "Causal localization of neural function: the Shapley value method." *Neurocomputing*, 58–60, 215–222.**
  - DOI: 10.1016/j.neucom.2004.01.046
  - 中心の主張：MSAを因果的機能局在の方法として簡潔に提示し、可逆的不活性化実験やTMSによる「仮想損傷」への応用可能性を示す。発信停止だけの介入でも、単独ではなく組み合わせ摂動として設計すべき根拠になる。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有
  - 対応項目：43

### 項目44 計算機実験の事前登録と再現性

- **Nosek, Brian A.; Ebersole, Charles R.; DeHaven, Alexander C.; Mellor, David T. (2018). "The preregistration revolution." *Proceedings of the National Academy of Sciences (PNAS)*, 115(11), 2600–2606.**
  - DOI: 10.1073/pnas.1708274114
  - 中心の主張：研究課題と解析計画を結果を見る前に定義する事前登録により、予測に基づく検証と事後的説明（postdiction）を区別でき、再現性が上がる。仮説を凍結する freeze 規律の一般的な裏づけ。
  - 形式モデル／計算機実験：形式モデル 無／計算機実験 無（方法論論文）
  - 対応項目：44

- **Grimm, Volker; Berger, Uta; DeAngelis, Donald L.; Polhill, J. Gary; Giske, Jarl; Railsback, Steven F. (2010). "The ODD protocol: A review and first update." *Ecological Modelling*, 221(23), 2760–2768.**
  - DOI: 10.1016/j.ecolmodel.2010.08.019
  - 中心の主張：個体ベース／エージェントベースモデルの記述を Overview, Design concepts, Details の標準形式で統一するODDプロトコルを改訂し、モデル記述を理解可能・完全・再現可能にする。計算機モデルの仕様凍結と文書化の標準。
  - 形式モデル／計算機実験：形式モデル 有（記述プロトコル）／計算機実験 無
  - 対応項目：44

- **Peng, Roger D. (2011). "Reproducible Research in Computational Science." *Science*, 334(6060), 1226–1227.**
  - DOI: 10.1126/science.1213847
  - 中心の主張：計算科学ではデータとコードを公開し他者が結果を再生成できることが、完全な独立再現が不可能な場合の最低限の判定基準になる。シードや手順を含む再現可能性の規範的根拠。
  - 形式モデル／計算機実験：形式モデル 無／計算機実験 無（方法論論文）
  - 対応項目：44

## J. 形式化と実装

### 項目45 最大不動点と余帰納法

- **Rutten, Jan J. M. M. (2000). "Universal coalgebra: a theory of systems." *Theoretical Computer Science*, 249(1), 3–80.**
  - DOI: 10.1016/S0304-3975(00)00056-6
  - 中心の主張：系を行動を観測する余代数として統一的に扱い、双模倣（bisimulation）と余帰納法を系の等しさの一般原理として与える。最大不動点としての行動等価性の標準的入門・基礎論文。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 無
  - 対応項目：45

- **Sangiorgi, Davide (2009). "On the origins of bisimulation and coinduction." *ACM Transactions on Programming Languages and Systems*, 31(4), Article 15, 1–41.**
  - DOI: 10.1145/1516507.1516510
  - 中心の主張：双模倣と余帰納法が計算機科学・様相論理・集合論で独立に発見された経緯を辿り、双模倣可能性が最大不動点として定義される余帰納的概念であることを明確化する。Knaster–Tarski型の不動点定理との接続も論じる。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 無
  - 対応項目：45
  - 補足：編著書 Sangiorgi & Rutten (eds.), *Advanced Topics in Bisimulation and Coinduction*, Cambridge University Press, 2012（DOI: 10.1017/CBO9780511792588）も同主題の体系的資料として確認した。

### 項目46 ガロア接続・随伴と開いた系の圏論

- **Fong, Brendan; Spivak, David I. (2019). *An Invitation to Applied Category Theory: Seven Sketches in Compositionality*. Cambridge University Press.**
  - DOI: 10.1017/9781108668804
  - 中心の主張：ガロア接続を随伴関手の順序版として、データ移行・回路・協調設計などを合成可能性（compositionality）の観点で統一的に扱う応用圏論の入門書。開いた系を関手的に合成する考え方の土台。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 無
  - 対応項目：46

- **Myers, David Jaz (2021). "Double Categories of Open Dynamical Systems (Extended Abstract)." *Proceedings of Applied Category Theory 2020 (ACT 2020)*, EPTCS 333, 154–167.**
  - DOI: 10.4204/EPTCS.333.11
  - 中心の主張：環境と相互作用する開いた力学系の一般的定義を二重圏で与え、軌道・定常状態・周期軌道といった共変的構造が合成に従うことを示す。後の *Categorical Systems Theory*（草稿書籍、DOIなし）の基礎論文。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 無
  - 対応項目：46

- **Baez, John C.; Fong, Brendan (2018). "A Compositional Framework for Passive Linear Networks." *Theory and Applications of Categories*, 33(38), 1158–1222.**
  - DOI: 10.48550/arXiv.1504.05625（arXiv版DOI。誌版は Theory and Applications of Categories 33, 2018）
  - 中心の主張：受動線形回路を開いた系として圏の射とみなし、入出力端子での接続を合成として、振る舞いを与える「ブラックボックス化」関手を構成する。装飾付きコスパンによる開いた系の圏論の代表例。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 無
  - 対応項目：46

### 項目47 定理証明器での検証

- **Immler, Fabian (2018). "A Verified ODE Solver and the Lorenz Attractor." *Journal of Automated Reasoning*, 61(1–4), 73–111.**
  - DOI: 10.1007/s10817-017-9448-y
  - 中心の主張：Isabelle/HOLで形式検証した厳密数値ODEソルバにより、TuckerがLorenzアトラクタのカオス証明に用いた計算を認証する。力学系の数値シミュレーションを定理証明器で裏づける代表例。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有（検証済みソルバによる計算）
  - 対応項目：47

- **Platzer, André (2018). *Logical Foundations of Cyber-Physical Systems*. Springer.**
  - DOI: 10.1007/978-3-319-63588-0
  - 中心の主張：ハイブリッドプログラムと微分動的論理（differential dynamic logic）により、離散・連続の混在する力学系の安全性を論理で検証する体系を教科書として提示する。検証器KeYmaera系の理論的基盤であり、Lean等での形式化の対照先になる。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有（証明器による検証例を含む）
  - 対応項目：47
  - 補足：本項目は「Leanそのもの」での力学系検証の査読論文がまだ少なく、検証済みシミュレーションの確立した事例としてIsabelle/HOLと動的論理の2件を収録した。Lean 4による radii polynomial method 等の近年の形式化はプレプリント段階のため今回は見送った。

### 項目48 言語をまたいだビット単位の再現

- **Sibidanov, Alexei; Zimmermann, Paul; Glondu, Stéphane (2022). "The CORE-MATH Project." *Proceedings of the 29th IEEE Symposium on Computer Arithmetic (ARITH 2022)*, 26–34.（Best Paper Award）**
  - DOI: 10.1109/ARITH54963.2022.00014
  - 中心の主張：正しく丸められた（correctly rounded）オープンソース数学関数を提供し、既存のlibmへ統合可能にする方法論を binary32 の powf と binary64 の cbrt で実証する。プラットフォーム間で同一ビット結果を得るための基盤。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有（最悪ケース探索と実装評価）
  - 対応項目：48

- **Brisebarre, Nicolas; Hanrot, Guillaume; Muller, Jean-Michel; Zimmermann, Paul (2025). "Correctly-rounded evaluation of a function: Why, how, and at what cost?" *ACM Computing Surveys*, 58.**
  - DOI: 10.1145/3747840
  - 中心の主張：関数を正しく丸めて評価することの意義・手法・コストを総説し、Table Maker's Dilemma（丸め困難ケース）がビット単位再現の本質的障害であることを整理する。openlibm・fdlibm系の実装をJulia・JS・Rust等で一致させる取り組みの理論的背景。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有（既存手法の評価を含む総説）
  - 対応項目：48

### 項目49 小型計算機・マイコンでの局所学習

- **Warden, Pete; Situnayake, Daniel (2019). *TinyML: Machine Learning with TensorFlow Lite on Arduino and Ultra-Low-Power Microcontrollers*. O'Reilly Media.**
  - DOIなし（書籍）
  - 中心の主張：KB級メモリのマイコン上で機械学習モデルを動かす設計・量子化・デプロイの実務を体系化したTinyMLの標準的入門書。Rust no_std の先にあるマイコン実装の参照点。
  - 形式モデル／計算機実験：形式モデル 無／計算機実験 有（実機デプロイ例）
  - 対応項目：49

- **Lin, Ji; Zhu, Ligeng; Chen, Wei-Ming; Wang, Wei-Chen; Gan, Chuang; Han, Song (2022). "On-Device Training Under 256KB Memory." *Advances in Neural Information Processing Systems (NeurIPS 2022)*.**
  - DOI: 10.52202/068431-1667（NeurIPS 2022 Proceedings版で確認）
  - 中心の主張：量子化対応スケーリングとスパース更新、コンパイル時に自動微分を処理する Tiny Training Engine により、256KB SRAMのマイコン上でのオンデバイス学習（転移学習）を初めて実用的に可能にした。推論だけでなく局所学習が極小メモリで成立することを示す。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有（マイコン実機での学習実験）
  - 対応項目：49

- **Davies, Mike; Srinivasa, Narayan; Lin, Tsung-Han; et al. (2018). "Loihi: A Neuromorphic Manycore Processor with On-Chip Learning." *IEEE Micro*, 38(1), 82–99.**
  - DOI: 10.1109/MM.2018.112130359
  - 中心の主張：オンチップ学習を備えたニューロモーフィック多コアプロセッサLoihiを提示し、プログラム可能なシナプス可塑性により局所学習をチップ内で閉じて実行できることを示す。局所可塑性による学習のハードウェア側の根拠。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有（実チップの性能・エネルギー測定）
  - 対応項目：49

### 項目50 最小の身体を持つ主体

- **Braitenberg, Valentino (1984). *Vehicles: Experiments in Synthetic Psychology*. MIT Press.**
  - DOIなし（書籍）
  - 中心の主張：センサとモータを直接つないだだけの極小の乗り物（Braitenberg vehicles）が、配線の仕方だけで接近・回避など一見目的的に見える多様な行動を生むことを思考実験で示す。最小の身体を持つ主体の原点。
  - 形式モデル／計算機実験：形式モデル 有（概念モデル）／計算機実験 無（思考実験）
  - 対応項目：50

- **Beer, Randall D. (1996). "Toward the evolution of dynamical neural networks for minimally cognitive behavior." In Maes, Pattie et al. (eds.), *From Animals to Animats 4: Proceedings of the Fourth International Conference on Simulation of Adaptive Behavior*, MIT Press, 421–429.**
  - DOI: 10.7551/mitpress/3118.003.0051
  - 中心の主張：連続時間リカレントニューラルネットワークを進化させ、最小認知行動を示すエージェントを得て、その行動を神経系‐身体‐環境の結合力学系として解析する枠組みを示す。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有（進化的シミュレーション）
  - 対応項目：50

- **Nolfi, Stefano; Floreano, Dario (2000). *Evolutionary Robotics: The Biology, Intelligence, and Technology of Self-Organizing Machines*. MIT Press.**
  - DOIなし（書籍）
  - 中心の主張：ロボットの身体と制御器を進化によって同時適応させる進化ロボティクスの方法論を体系化し、身体性が行動と学習を規定することを実証的に整理する。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有（実機・シミュレーション実験の総説を含む）
  - 対応項目：50

- **Froese, Tom; Ziemke, Tom (2009). "Enactive artificial intelligence: Investigating the systemic organization of life and mind." *Artificial Intelligence*, 173(3–4), 466–500.**
  - DOI: 10.1016/j.artint.2008.12.001
  - 中心の主張：身体化・状況化されたAIを、自己を維持する系の組織（構成的自律性）の観点から整理し、エナクティブAIの設計要件を機能・構造のレベルで論じる。現象性の主張ではなく、系の組織と自律性の条件を扱う部分を参照する。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 無（理論的総説）
  - 対応項目：50

## K. 優先度低（参考）

### 項目51 LLMの役割

- **Jacovi, Alon; Goldberg, Yoav (2020). "Towards Faithfully Interpretable NLP Systems: How Should We Define and Evaluate Faithfulness?" *Proceedings of the 58th Annual Meeting of the Association for Computational Linguistics (ACL 2020)*, 4198–4205.**
  - DOI: 10.18653/v1/2020.acl-main.386
  - 中心の主張：説明の「忠実さ（faithfulness）」を、もっともらしさ（plausibility）と区別し、モデルの実際の推論過程を正確に反映することとして定義・評価すべきと論じる。LLMを盲検の通訳として使う際に、その説明を鵜呑みにできない根拠。
  - 形式モデル／計算機実験：形式モデル 有（評価概念の定式化）／計算機実験 無
  - 対応項目：51

- **Turpin, Miles; Michael, Julian; Perez, Ethan; Bowman, Samuel R. (2023). "Language Models Don't Always Say What They Think: Unfaithful Explanations in Chain-of-Thought Prompting." *Advances in Neural Information Processing Systems (NeurIPS 2023)*.**
  - DOI: 10.48550/arXiv.2305.04388（arXiv版DOI）
  - 中心の主張：入力にバイアス特徴（例：選択肢の並べ替え）を加えるとLLMの答えは変わるのに、Chain-of-Thought説明はその影響に言及せず、説明が事後的な正当化になりうることを13タスクで実証した。LLMの説明の不忠実さの代表的実験。
  - 形式モデル／計算機実験：形式モデル 無／計算機実験 有（LLMへの介入実験）
  - 対応項目：51

- **Lapuschkin, Sebastian; Wäldchen, Stephan; Binder, Alexander; Montavon, Grégoire; Samek, Wojciech; Müller, Klaus-Robert (2019). "Unmasking Clever Hans predictors and assessing what machines really learn." *Nature Communications*, 10, 1096.**
  - DOI: 10.1038/s41467-019-08987-4
  - 中心の主張：説明手法（LRP等）で学習機械を分析すると、本来の対象ではなくデータ中の見かけの相関（透かし等）に頼る「Clever Hans」型予測器が検出できることを示す。LLMを感覚の入口や教育係に使う場合にも、見かけの手がかりへの依存を点検すべき根拠になる。
  - 形式モデル／計算機実験：形式モデル 有／計算機実験 有
  - 対応項目：51
  - 補足：「LLM as teacher」そのものを主題とする査読論文は本項目では特定せず、上記3件（忠実さの定義・不忠実さの実証・Clever Hans検出）を、段2の盲検の通訳および段17〜18でのLLM利用に対する注意喚起として収録した。

---

## 収集サマリ

- 収集論文総数：30件
- 項目41：3件／項目42：2件／項目43：3件／項目44：3件／項目45：2件／項目46：3件／項目47：2件／項目48：2件／項目49：3件／項目50：4件／項目51：3件
- 未収集項目：なし（全11項目で最低1件を収集）
- 注記：項目47はLean固有の査読論文が乏しく、検証済み力学系シミュレーションの確立事例（Isabelle/HOL、動的論理）で代替した旨を本文に明記した。項目51の「LLM as teacher」専論は特定できず、関連する忠実さ／Clever Hans論文で構成した旨を本文に明記した。


## L. 上層の追加分野（Museリスト由来）

> 担当範囲：項目52〜62。いずれも bridge-protocol（GitHub yaaman18/bridge-protocol、Lean 4 + Julia で自己維持系の圏論的理論を機械検査するプロジェクト）の未決論点に直結する分野である。各論文について、書誌情報・DOI・中心の主張・形式モデルや計算機実験の有無・対応項目番号を記載する。DOI は browser.search / browser.open による検索で実際に確認したもののみ記載し、確認できないものはその旨を明記した。意識や現象性を主張する論文は除外し、機能と構造に関する論文のみを採用した。

### 項目52 Φ_rich の重みづけ（Pareto／多目的最適化、richness/diversity 尺度）

- Deb, K., Pratap, A., Agarwal, S., & Meyarivan, T. (2002). "A Fast and Elitist Multiobjective Genetic Algorithm: NSGA-II". *IEEE Transactions on Evolutionary Computation*, 6(2), 182–197.
  - DOI: 10.1109/4235.996017
  - 中心の主張：非支配ソートと crowding distance により、Pareto フロントへの収束と解の多様性（diversity）の保持を同時に実現する多目的最適化の標準手法を提示した。複数の目的を単一スカラーに合成せず、フロントとして保持する設計は、(Φ_depth, Φ_div, Φ_level) を安易に重みづけ合成しない判断の参照点になる。
  - 形式モデルや計算機実験の有無：有（アルゴリズムの形式化とベンチマーク計算機実験）
  - 対応項目：52
- Zitzler, E., Thiele, L., Laumanns, M., Fonseca, C. M., & Grunert da Fonseca, V. (2003). "Performance Assessment of Multiobjective Optimizers: An Analysis and Review". *IEEE Transactions on Evolutionary Computation*, 7(2), 117–132.
  - DOI: 10.1109/TEVC.2003.810758
  - 中心の主張：多目的最適化器の性能指標（hypervolume 等の quality indicator）を分析し、指標が Pareto 適合性を持つかどうかで順序づけの妥当性が変わることを示した。豊かさ尺度 Φ_rich の指標選択そのものが評価結果を左右するという、尺度設計への警告として読める。
  - 形式モデルや計算機実験の有無：有（指標の形式的分析と実験的比較）
  - 対応項目：52

### 項目53 増殖の射の正確な定義（多水準選択・Price 方程式、世代間の豊かさ継承）

- Kramer, J., & Meunier, J. (2016). "Kin and Multilevel Selection in Social Evolution: A Never-Ending Controversy?" *F1000Research*, 5 (F1000 Faculty Rev): 776.
  - DOI: 10.12688/f1000research.8018.1
  - 中心の主張：血縁選択と多水準選択は Price 方程式の異なる分割として形式的に等価であり、進化変化を個体水準と集団水準の効果に分解できることを整理した総説。増殖の射を「世代間の変化の分解」として定義する際の水準混同への注意を与える。
  - 形式モデルや計算機実験の有無：有（形式モデル：Price 方程式による分解の理論的整理。計算機実験は無）
  - 対応項目：53
- Okasha, S. (2020). "The Price Equation and the Causal Analysis of Evolutionary Change". *Philosophical Transactions of the Royal Society B*, 375(1797), 20190365.
  - DOI: 10.1098/rstb.2019.0365
  - 中心の主張：Price 方程式自体は統計的恒等式にすぎず、その各項（選択項・伝達バイアス項）に因果的意味を与えるには因果構造についての実質的仮定が別途必要だと論じた。世代間の豊かさ継承を恒等式の分割だけで「継承した」と主張することの限界を示す。
  - 形式モデルや計算機実験の有無：有（形式モデル：Price 方程式と因果モデルの分析。計算機実験は無）
  - 対応項目：53

### 項目54 入れ子の圏論的足場（fibration／Grothendieck 構成 vs operad、階層的個体性）

- Vagner, D., Spivak, D. I., & Lerman, E. (2015). "Algebras of Open Dynamical Systems on the Operad of Wiring Diagrams". *Theory and Applications of Categories*, 30(51), 1793–1822.
  - DOI: DOIなし（同誌掲載論文として書誌を確認したが、DOI は確認できなかった）
  - 中心の主張：配線図（wiring diagrams）の operad を定義し、開放力学系がその operad 上の代数をなすことを示した。小さな系を大きな箱の中に入れ子にする階層的合成の構文を operad が担い、意味を代数が与えるという分業を提示する。
  - 形式モデルや計算機実験の有無：有（形式モデル：operad とその代数の圏論的定式化。計算機実験は無）
  - 対応項目：54
- Fong, B., & Spivak, D. I. (2019). "Hypergraph Categories". *Journal of Pure and Applied Algebra*, 223(11), 4746–4777.
  - DOI: 10.1016/j.jpaa.2019.02.014
  - 中心の主張：配線図で記述できる系の意味論として hypergraph category（各対象に特殊可換 Frobenius 構造を持つ対称モノイダル圏）を特徴づけ、cospan による配線の合成と等価であることを示した。operad 的構文に対する圏論的意味論の側の足場を与える。
  - 形式モデルや計算機実験の有無：有（形式モデル：圏論的特徴づけ定理。計算機実験は無）
  - 対応項目：54

### 項目55 Σ-purity = 情報流非干渉（noninterference、taint 解析、metamorphic/differential testing）

- Goguen, J. A., & Meseguer, J. (1982). "Security Policies and Security Models". *Proceedings of the 1982 IEEE Symposium on Security and Privacy*, 11–20.
  - DOI: 10.1109/SP.1982.10014
  - 中心の主張：セキュリティポリシーを noninterference（非干渉）の主張の集合として定式化し、高水準の入力が低水準の観測者に影響を与えないことをポリシーの意味とした古典。Σ-purity を「許されない情報流が存在しない」という観測可能性ベースの性質として定義する原型である。
  - 形式モデルや計算機実験の有無：有（形式モデル：状態機械モデル上の非干渉の定義。計算機実験は無）
  - 対応項目：55
- Sabelfeld, A., & Myers, A. C. (2003). "Language-Based Information-Flow Security". *IEEE Journal on Selected Areas in Communications*, 21(1), 5–19.
  - DOI: 10.1109/JSAC.2002.806121
  - 中心の主張：言語ベースの情報流セキュリティ（セキュリティ型付け、taint 的なラベル伝播を含む）を総覧し、非干渉を型システムで静的に強制する方法と、その厳密さゆえの限界・緩和（declassification）の論点を整理した。purity を静的解析で担保する設計の参照点になる。
  - 形式モデルや計算機実験の有無：有（形式モデル：型システムと非干渉の健全性。計算機実験は無）
  - 対応項目：55
- Segura, S., Fraser, G., Sanchez, A. B., & Ruiz-Cortés, A. (2016). "A Survey on Metamorphic Testing". *IEEE Transactions on Software Engineering*, 42(9).
  - DOI: 10.1109/TSE.2016.2532875
  - 中心の主張：正解オラクルが得られない場合に、入力変換に対する出力間の関係（metamorphic relation）の保持で正しさを検査する metamorphic testing の研究 119 件を総覧した。期待値が書けない性質（purity のような関係的性質）を、関係の保存として検査する手法の基礎になる。
  - 形式モデルや計算機実験の有無：有（metamorphic relation の定式化と、対象論文群の実証研究の総覧）
  - 対応項目：55

### 項目56 賭け W1–W6 と構成的独立性（独立性証明・モデル構成による未決定性）

- Cohen, P. J. (1963). "The Independence of the Continuum Hypothesis". *Proceedings of the National Academy of Sciences of the United States of America*, 50(6), 1143–1148.
  - DOI: 10.1073/pnas.50.6.1143
  - 中心の主張：forcing（強制法）を導入し、ZFC の可算推移モデルに generic な対象を付け加えて連続体仮説の否定が成り立つモデルを構成した。命題の未決定性を「反対の性質を持つモデルを実際に構成する」ことで示す方法論の原型である。
  - 形式モデルや計算機実験の有無：有（形式モデル：モデル構成による独立性証明。計算機実験は無）
  - 対応項目：56
- Cohen, P. J. (1964). "The Independence of the Continuum Hypothesis, II". *Proceedings of the National Academy of Sciences of the United States of America*, 51(1), 105–110.
  - DOI: 10.1073/pnas.51.1.105
  - 中心の主張：前編の forcing 構成を完成させ、選択公理の ZF からの独立性を含む結果を確立した。Gödel の構成可能宇宙（CH が成り立つモデル）と対になって、CH が ZFC から証明も反証もできないことが確定した。
  - 形式モデルや計算機実験の有無：有（形式モデル：モデル構成による独立性証明。計算機実験は無）
  - 対応項目：56

### 項目57 台帳と checker の意味論（decision procedure／witness validator、soundness–completeness、要求トレーサビリティ）

- Berger, U., Lawrence, A., Nordvall Forsberg, F., & Seisenberger, M. (2015). "Extracting Verified Decision Procedures: DPLL and Resolution". *Logical Methods in Computer Science*, 11(1:6), 1–18.
  - DOI: 10.2168/LMCS-11(1:6)2015
  - 中心の主張：DPLL 証明系の健全性と完全性を証明支援系で形式化し、完全性証明からプログラム抽出することで、正しさが構成的に保証された SAT 決定手続き（充足モデルか反証導出のいずれかを返す witness 付き checker）を得た。「決定する」「証拠を検証するだけ」「健全だが不完全」の区別を実装水準で体現する。
  - 形式モデルや計算機実験の有無：有（形式モデル：証明支援系 Minlog での形式化とプログラム抽出）
  - 対応項目：57
- Gotel, O. C. Z., & Finkelstein, A. C. W. (1994). "An Analysis of the Requirements Traceability Problem". *Proceedings of the IEEE International Conference on Requirements Engineering*, 94–101.
  - DOI: 10.1109/ICRE.1994.292398
  - 中心の主張：100 名超の実務家への調査に基づき、要求トレーサビリティの問題の多くは仕様化以前（pre-RS）の来歴追跡の欠落に起因するとし、pre-RS／post-RS の区別を導入した。仕様被覆監査では「仕様項目が実装に落ちているか」だけでなく「仕様項目がどこから来たか」の追跡が要ることを示す。
  - 形式モデルや計算機実験の有無：無（形式モデル・計算機実験は無。実務家への実証調査に基づく分析）
  - 対応項目：57
- Ramesh, B., & Jarke, M. (2001). "Toward Reference Models for Requirements Traceability". *IEEE Transactions on Software Engineering*, 27(1), 58–93.
  - DOI: 10.1109/32.895989
  - 中心の主張：26 の開発組織への調査から、低水準／高水準のトレーサビリティ実践を抽出し、開発タスクごとに必要なトレースリンクの種類を示す参照モデルを構築した。台帳が「何と何を結ぶべきか」の被覆基準を与える先行研究である。
  - 形式モデルや計算機実験の有無：無（形式モデル・計算機実験は無。組織調査に基づく参照モデルの構築）
  - 対応項目：57

### 項目58 検証の検証（mutation testing、敵対的検証、自己検証バイアス）

- DeMillo, R. A., Lipton, R. J., & Sayward, F. G. (1978). "Hints on Test Data Selection: Help for the Practicing Programmer". *Computer*, 11(4), 34–41.
  - DOI: 10.1109/C-M.1978.218136
  - 中心の主張：プログラムに小さな故障（mutant）を意図的に埋め込み、テストスイートがそれを検出できるかでテストの質を測る mutation testing を提唱した古典。検証系自身を「わざと壊した対象で試す」という、検証の検証の原型である。
  - 形式モデルや計算機実験の有無：有（mutant 生成の定式化と初期の実験的検討）
  - 対応項目：58
- Jia, Y., & Harman, M. (2011). "An Analysis and Survey of the Development of Mutation Testing". *IEEE Transactions on Software Engineering*, 37(5), 649–678.
  - DOI: 10.1109/TSE.2010.62
  - 中心の主張：mutation testing の発展を総合的に総覧し、等価 mutant 問題やコストなど未解決の実務的障害を整理した標準サーベイ。「検証が通る」ことと「検証が壊れた対象を実際に落とせる」ことの間の溝を測る方法論の現状を示す。
  - 形式モデルや計算機実験の有無：無（総説論文。形式モデル・計算機実験そのものは無）
  - 対応項目：58

### 項目59 反証条件の方法論（falsification の科学哲学、severity testing）

- Popper, K. R. (1959). *The Logic of Scientific Discovery*. Hutchinson & Co.（原著 *Logik der Forschung*, 1934）
  - DOI: DOIなし（書籍）
  - 中心の主張：科学理論の条件は検証可能性ではなく反証可能性であり、普遍言明は有限の観測で証明できないが単一の反例で反証できるという非対称性を、線引き基準として提示した。反証条件を書けない主張は科学的テストの対象にならない、という bridge-protocol の「反証条件 0/91 の負債」への直接の方法論的根拠である。
  - 形式モデルや計算機実験の有無：無（科学哲学の著作。形式モデル・計算機実験は無）
  - 対応項目：59
- Mayo, D. G., & Hand, D. (2022). "Statistical Significance and Its Critics: Practicing Damaging Science, or Damaging Scientific Practice?" *Synthese*, 200, 220.
  - DOI: 10.1007/s11229-022-03692-0
  - 中心の主張：Mayo の severity（厳密さ）の観点から、主張に証拠力があるのは、その主張が誤りであれば高い確率で落としたはずのテストを通過した場合に限ると論じた。反証条件は「書く」だけでなく「誤りを実際に検出できる能力（error probability）」を伴わなければならないことを示す。
  - 形式モデルや計算機実験の有無：無（統計学の哲学・方法論の論文。形式モデル・計算機実験は無）
  - 対応項目：59

### 項目60 個体性 = ⟨系 S, 分解 D⟩（分解依存の個体性、生理的個体性 vs 進化的個体性、ホロビオント）

- Godfrey-Smith, P. (2009). *Darwinian Populations and Natural Selection*. Oxford University Press.
  - DOI: 10.1093/acprof:osobl/9780199552047.001.0001
  - 中心の主張：Darwinian population を「変異・遺伝・繁殖成功の差」を持つ集団として段階的に定義し、個体であることは二値ではなく、ボトルネック・生殖／体細胞の分業・統合度などのパラメータに依存する程度問題だと論じた。個体性が系そのものではなく系への分解・見方に依存するという ⟨S, D⟩ 型の発想の基礎になる。
  - 形式モデルや計算機実験の有無：無（生物学哲学の著作。形式モデル・計算機実験は無）
  - 対応項目：60
- Devanesan, A. (2025). "Are Physiological Individuals Evolutionary Individuals? The Case of the Holobiont". *Philosophy of Science*.
  - DOI: 10.1017/psa.2025.15
  - 中心の主張：Pradeu の免疫学的基準による生理的個体性と Clarke の進化的個体性の議論を組み合わせ、宿主と微生物叢からなるホロビオントも進化的個体として扱えると論じた。同じ系でも採用する個体性概念（分解）によって個体の切り方が変わることを、ホロビオントという難例で具体化する。
  - 形式モデルや計算機実験の有無：無（生物学哲学の論文。形式モデル・計算機実験は無）
  - 対応項目：60

### 項目61 内生時間と機能終了（系固有の時間、構造から導かれる機能終了）

> 本項目は bridge-protocol の TemporalDC／内生時間に完全一致する分野が確立していないため、近接分野からの採用として、以下の代表論文を収録する。

- Connes, A., & Rovelli, C. (1994). "Von Neumann Algebra Automorphisms and Time-Thermodynamics Relation in Generally Covariant Quantum Theories". *Classical and Quantum Gravity*, 11(12), 2899–2917.
  - DOI: 10.1088/0264-9381/11/12/007
  - 中心の主張：thermal time hypothesis を提示し、一般共変な理論では時間の流れは外部から与えられるのではなく、系の熱力学的状態から Tomita–Takesaki 理論により導かれる 1 径数自己同型群として内生的に定まると論じた。「系固有の時間」を状態依存に定義する代表的定式化である。
  - 形式モデルや計算機実験の有無：有（形式モデル：von Neumann 代数と modular 理論による定式化。計算機実験は無）
  - 対応項目：61（近接分野からの採用）
- Montévil, M., & Mossio, M. (2015). "Biological Organisation as Closure of Constraints". *Journal of Theoretical Biology*, 372, 179–191.
  - DOI: 10.1016/j.jtbi.2015.02.029
  - 中心の主張：生物の組織化を、互いに生成・維持し合う制約の閉包（closure of constraints）として概念的・形式的に特徴づけ、制約同士の相互依存が崩れれば組織化そのものが維持できないとした。機能が構造の閉包に依存し、その破綻が機能終了を導くという見方の基礎になる。
  - 形式モデルや計算機実験の有無：有（形式モデル：制約とプロセスの区別に基づく形式的特徴づけ。計算機実験は無）
  - 対応項目：61（近接分野からの採用）

### 項目62 理論翻訳と二軸原則（理論間の翻訳、形式仕様と散文被覆の区別）

> 本項目は「certified が散文被覆を含意しない」という bridge-protocol 固有の区別に完全一致する先行研究が無いため、近接分野からの採用として、理論翻訳・解釈の代表論文を収録する。

- Lawvere, F. W. (1963). "Functorial Semantics of Algebraic Theories". *Proceedings of the National Academy of Sciences of the United States of America*, 50(5), 869–872.
  - DOI: 10.1073/pnas.50.5.869
  - 中心の主張：代数理論そのものを一つの圏として提示し、そのモデルを背景圏への関手（解釈）として定義する functorial semantics を創始した。理論と解釈（翻訳）の関係を、散文的な対応づけではなく関手という検査可能な対象として扱う原型である。
  - 形式モデルや計算機実験の有無：有（形式モデル：圏論的意味論の定式化。計算機実験は無）
  - 対応項目：62（近接分野からの採用）
- Freire, A. R. (2019). "Translating Non Interpretable Theories". *South American Journal of Logic*, 5(1), 1–21.
  - DOI: DOIなし（同誌掲載論文として書誌を確認したが、DOI は確認できなかった）
  - 中心の主張：理論間の「翻訳」は解釈可能性（interpretability）と同一視できないとし、解釈が存在しない理論間でも相対的無矛盾性の証明等を通じて翻訳と呼べる関係が成立しうることを、翻訳写像とその健全性の定義から論じた。翻訳証書が何を保証し何を保証しないかを切り分ける際の参照点になる。
  - 形式モデルや計算機実験の有無：有（形式モデル：一階理論間の翻訳・解釈の論理学的定式化。計算機実験は無）
  - 対応項目：62（近接分野からの採用）

---

## 収集状況のまとめ

- 収集論文総数：24 件
- 項目別件数：項目52＝2件、項目53＝2件、項目54＝2件、項目55＝3件、項目56＝2件、項目57＝3件、項目58＝2件、項目59＝2件、項目60＝2件、項目61＝2件、項目62＝2件
- 未収集項目：なし（全11項目について最低1件を収集した）
- 注記：項目61・62は完全一致する先行分野が無いため、指示に基づき最も近い代表論文を「近接分野からの採用」と明記して収録した。項目54の Vagner et al. (2015) と項目62の Freire (2019) は DOI が確認できなかったため「DOIなし」と明記した。項目59の Popper (1959) は書籍のため「DOIなし（書籍）」とした。


---

# 未収集・注意メモ

## 未収集項目
- **未収集項目はなし。** 全62項目（項目1〜62）すべてで最低1件の代表論文を収集した（62/62、カバー率100%）。
- ★最優先10項目（13・17・18・20・21・24・28・29・30・37）はすべて2件以上を確保した（内訳：13=2件、17=2件、18=2件、20=3件、21=2件、24=2件、28=2件、29=3件、30=2件、37=4件）。
- 収集論文総数： **153件**（A・B章29件、C・D章29件、E・F章24件、G・H章17件、I・J・K章30件、L章24件）。

## DOI・書誌に関する注意
- DOI はすべて担当者が web 検索で実際に検証したもののみ記載した。推測で作った DOI はない。
- DOI が確認できなかったものは本文中でその旨を明記した。代表例： 書籍（Thompson 2007、Gánti 2003、Ashby 1952、Popper 1959、Di Paolo et al. 2017 など）は「DOIなし（書籍）」、Murray & Trevarthen 1985・Watson 1972・Walter 1950 は DOIなし、Fontana & Buss 1994（PNAS）は「DOI未確認」、Vagner, Spivak & Lerman 2015・Freire 2019 は「DOIなし」、Cobbe et al. 2019 は会議録のため DOIなし、Aubin 1991 と Ashby 1960 は再刊／電子版の DOI を確認しその旨を併記した。
- 項目12の O'Regan & Noë 2001 はタイトルに consciousness を含む指定文献のため、現象性の主張を切り離し感覚運動随伴の機能的・構造的側面のみを要約し、その旨を該当パート冒頭に注記した。その他、意識・現象性を中心に主張する論文は採用していない。
- 項目23（および項目25・33）は強化学習・最適化系の文献を「対照」として明記した場合にのみ採用した。Mordvintsev et al. 2020（項目11）も外部目標で訓練されるため「内生的自己維持との対照」と位置づけた。

## 完全一致がなく近接分野で代替した箇所
- **項目40**： 「季節変動のような緩やかな非定常変化の下での寿命」を直接主題とする論文は検証範囲で特定できなかったため、held-out 汎化（Cobbe et al. 2019）と domain randomization（Tobin et al. 2017）で代替し、直接証拠としては主張しない旨を注記した。
- **項目47**： Lean 固有の査読論文が乏しいため、検証済み力学系シミュレーションの確立事例（Isabelle/HOL、微分動的論理）で代替した。
- **項目51**： 「LLM as teacher」専論は特定できなかったため、説明の忠実さの定義・不忠実さの実証・Clever Hans 検出の3件で構成した。
- **項目61・62**： 完全一致する分野が存在しないため、最も近い代表論文を「近接分野からの採用」と明記して採用した（61： thermal time と制約閉包による組織的存続／終了、62： functorial semantics と理論翻訳論）。
- **項目35**： 内受容については経路・構造・予測処理の機能的記述のみに限定し、phenomenal_claim に触れる主張は要約に含めていない。

## 次の作業への申し送り
- 本ファイルは「分野→代表論文」の一次収集である。各項目の2件目以降の拡充、特に項目40（非定常環境での寿命の直接証拠）、項目47（Lean 固有事例）、項目52（多様性尺度そのものの論文で Pareto 最適化からの代替を置き換えること）は今後の追加収集候補。
- パートファイル（検証作業の原稿）は `parts/group1-A-B.md` 〜 `parts/group6-L.md` に残してある。
