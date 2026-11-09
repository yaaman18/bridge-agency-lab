# S2 同じ契約・同じ主対象で D と N を測る（R-BODY-1 の続き）

- 状態: **確定 r2**（2026-11-06、codex S-R の 1〜6 を反映。I 段へ進むことを受理）。
- 目的: S1 と同じ比較契約（同じ出生状態 B、同じ法則、保育期の台本だけが違う）のもとで育てた二つの腕を、同じ身体の段階に入れ、AGENCY-001 の
  D（ValueDifferentiated）と N（ValueNeeded）を測る。D0 決1 の「H・D・N を同じ対象・同じ契約に束縛する」を、BODY（元の規則の版）で満たす。
- 対応する要件: `requirements.md` R-BODY-1（次の手「D・N を同じ契約・同じ主対象で」）。
- 出典: S1（`specs/S1-body-history.md` r3、README 項番87）、D0 決4（N は現行 survives を用いた ValueNeeded、空の追跡集合なら false のガード）、
  `lab:experiments/variant_horizon.jl`（LabBodyAgency: BodyOrg・initial_state・setup_with、bp の criteria を変えずに呼ぶ）、項番70・74 の記録。

## 0. 確認した事実

- `BodyOrg(seed; cur, contrast, idle_first, core_gate, …)` は、S1 と同じ手続きで回路を育て（`variant_horizon.jl:82–83`）、その状態を `raised` と
  `noise` に持つ。身体の段階の各軌跡は、`raised` の複製と、新しく作る世界（`make_world(; reservoir = 300.0)`、`seed!(w, 12, 12, 1)`）と、
  プール `[0, 0]` から始まる（`initial_state`、`:95–100`）。
- `AS.evaluate(s, su)` は bp の criteria を変えずに呼ぶ。D は選択の窓での二つの予定表（c1-better・c2-better）で行為が価値に応じて分かれるか、
  N は D で特定した追跡集合 T を止めたときの生存の比較。**T が空なら N は false**（bp のガード、D0 決4）。
- 既存の記録（読み取り、`results-horizon.json`＝元の規則 :std、`results-horizon-swap.json`＝:swap）: H＝294・392・588 で、
  :std は両予定表とも m2、:swap は両予定表とも m1。D は 0/10、N は 0/10（どちらの腕も）。

## 1. 要件

- S2-1（S1 との連結）: 各腕の `BodyOrg` が持つ `raised` と `noise` の直列化（S1 の `_ser!`）が、S1 の手続きで同じ種子・同じ腕から育てた
  800 歩後の c・nz の直列化と**バイト単位で同じ**。これで S2 の対象は S1 の契約で比べた二つの腕そのものになる。
  `BodyOrg` のそのほかの欄（names・edges・motors・b・structure・abundant_r0・U・MCOST・規則の旗・KC・PER・w0・pool0、評価前の空の side）は、
  二つの腕でバイト単位で同じであること（codex S-R 1）。違う欄があれば、その欄も宣言差に帰属できない限り契約違反。
- S2-2（身体の段階の開始の一致）: 二つの腕の身体の段階の開始状態のうち、育成で形成されたもの（回路の状態・乱数）を除いた部分
  《世界 w、プール pool、パラメータと予定表 su》が、腕の間でバイト単位で同じ。違えば D・N の差を育成史に帰属させない。
- S2-3（同じ測り方）: 二つの腕は同じ `AS.evaluate` を同じ `su`（`setup_with(H)`）で呼ぶ。地平 H は 294・392・588（60 は L2 を測れない、項番70）。
- S2-3b（入力の網羅、codex S-R 2・3）: `evaluate` の入力は《BodyOrg、su》だけで、各軌跡の実行中の入力は su の予定表（腕で同じ）から作られる。
  bp の AgencySubstrate と ラボの core に `rand(`・`Random`・`time(`・`global` はない（grep、2026-11-06）。評価順への依存がないことは
  S2-7 の再評価の一致と、腕の評価順を入れ替えても結果が同じであることで確かめる。どれかが破れたら、D・N を Lean の f と読む適用は反証される。
- S2-7（再現の対照）: 同じ腕を同じ su で二度評価し（新しく BodyOrg を作り直して）、選択・D・T・N・生存の表がすべて等しい。腕の評価順（std→swap と swap→std）を
  入れ替えても等しい。
- S2-4（観測）: 腕・種子・H ごとに、選択（予定表ごとの行為）、D（differentiated）、T（value_tracking）、N（value_needed）、生存の表。
- S2-5（N の読みの区別）: T が空で N が false のときは「N: ガードにより偽（追跡集合が空、検定していない）」と書き、T が空でない N の偽・真と分ける。
- S2-6（判定の語）: S1 の受け入れ条件と S2-1〜S2-3 が通った種子で、選択・D・N のどれかが腕で違えば「契約のもとでその観測に H の支持」。
  D・N の真偽そのものは腕ごとに報告し、H∧D∧N の成立は D と N（ガードでない）がともに真のときだけ言う。
  N は「ガードで偽」「検定して偽」「検定して真」を別々に集計し、ガードで偽を H∧D∧N に算入しない（codex S-R 4）。
  契約を通らなかった種子の数と理由を残し、結果は通過した種子だけについてと明記する（codex S-R 5）。
  H の支持が言うのは「宣言した位置の差が観測の差に必要」までで、それを超える主張はしない（codex S-R 5）。

## 2. 非目標

- 規則・数値・地平の変更。現行版（bin3＋idle_first＋核の関門）。L3・L3R。

## 3. 設計（新しいファイルだけ）

- `experiments/dn_body_swap.jl`: `variant_horizon.jl` を include して LabBodyAgency を使う（主の走りは PROGRAM_FILE の条件で走らない）。
  種子 1〜10、腕 :std・:swap、元の規則（contrast＝nothing、idle_first＝偽、core_gate＝偽）、structure＝:constituents、H＝294・392・588。
  S1 の直列化は `h_body_swap.jl` から関数を写すか include する（変えない）。結果は `experiments/results-dn-body-swap.json`。
- `experiments/check_dn_body_swap.jl`: 種子が正確に 1〜10・H が 3 つ、S2-1・S2-2・S2-7 がすべて真、負の対照が働いたら exit 0。
  負の対照: 片腕の身体の開始の世界を一か所変えた組（例 `w.C[1]` を 1 増やす）を S2-2 の比較が検出すること、片腕の BodyOrg の MCOST を変えた組を
  S2-1 の欄の比較が検出すること、何もしない組は一致すること。負の対照は検査器が働くことの確認で、契約の網羅性の証明ではない（codex S-R 6）。
  種子ごとに S2-5・S2-6 の判定を表示（終了コードに入れない）。

## 4. 予測（凍結、`experiments/predictions-dn-body-swap.md`）

既存の記録の再現（新しい予測ではない）と、新しく測る契約の検査を分ける。
- DP1（新）: S2-1 は 10/10（BodyOrg の育成は S1 の手続きと同じ引数）。
- DP2（新）: S2-2 は 10/10（世界・プール・予定表は定数から作る）。BodyOrg のほかの欄も 10/10 で一致。負の対照は検出される。
- DP5（新）: S2-7 の再評価と評価順の入れ替えは 10/10 で一致。
- DP3（再現）: 3 つの H で、:std は両予定表とも m2、:swap は両予定表とも m1、10/10。
- DP4（再現）: D は両腕とも 0/10（3 つの H で）。したがって T は空で、N はガードにより偽（0/10）。
- 反証条件: DP1・DP2・DP5 が偽なら、D・N の差・不差を育成史に帰属させない（その種子を外す）。DP3・DP4 が偽なら記録と今のコードの食い違いとして報告。

## 5. 試験（GATE）

- `FILE: experiments/dn_body_swap.jl`、`FILE: experiments/check_dn_body_swap.jl`、`FILE: experiments/results-dn-body-swap.json`
- `GATE: cd experiments && julia --project=.. dn_body_swap.jl`
- `GATE: cd experiments && julia --project=.. check_dn_body_swap.jl`
- `GATE: grep -q '"negative_control_detected": true' experiments/results-dn-body-swap.json`
- 凍結の sha256 の一致

## 6. 形式

- `formal/History.lean` に `observable_difference_needs_declared` を足した（証明済み）: 契約のもとで、run から計算する任意の観測 f の差は、
  宣言した位置の台本の差を要する。身体の段階は、育成の結果に対する固定の決定的な続き（世界・予定表は腕で同じ、S2-2）なので、D・N は f の一つとして読む。
  この読みの適用条件（codex S-R 3）: S2-1・S2-2・S2-3b・S2-7 が通ること。実行中の入力に宣言していないものがあって結果が変われば、適用は反証される。

## 7. 影響範囲 / 仮定

- 新しいファイルだけ。依る仮定: H1、読み #1・#2（未承認）。bp の criteria は変えずに呼ぶ。
