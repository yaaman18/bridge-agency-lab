# S7 D2 の自己維持の規則を BODY の実走に当てる（R-BODY-4、三値判定）

- 状態: r2（codex I-R 1〜11 を反映。r1 2026-11-07、ユーザー「R-BODY-4 … をやって」。claude-lab が書き、codex-lab が I-R）。
- 目的: `notes/D2.md` の T（(a)(a′)(b)(c)）・T⁺・T_core を、SF 版の BODY の走りの事象に当て、成立／不成立／未判定で記録する。
- 対象: SF 版（L2 の系の既定、README 項番93: bin3＋idle_first＋core_gate＋sed_fade＋KC_trial 0.0015）、腕 :std・:swap、
  **種子 31〜40（今まで一度も使っていない種子。S4〜S6 の 21〜30 は振る舞いを見てしまったので、主張には使わない、2026-11-07 の取り決め）**、
  生存の予定表 4 つ（凍結の templates の survival、su.params、豊富でない）、地平 H＝294・392・588。

## 1. 測るもの
- 本走: `AS.initial_state` から H 回の更新（`AS.step!`、無介入）。生きている各更新の後に `LC.dc_record(b, o, c; partner_live=false, y, phase="world")`
  （`o` は `LC.step!` の結果、`c` は更新後の回路の状態、`y` は読んだ収量）。記録は `variant_horizon.jl` に足す読むだけの差し込み口 `ON_STEP` から取る
  （既定は nothing。動力学に何も書き戻さない。対照 (v) で確かめる）。
- (a): 事象 t（t≥32、t の更新の後に身体が生きている）で、t で終わる 32 件の記録の窓の `check_dc`（`core/dc.jl`、alpha=:state）。dc が真なら成立、偽なら不成立。
  Q4（定位反応・試しの確かめを自己産出に数えない）は `elem_self` の `enables`（確かな自己の結びつきに可能にされた運動の行為だけを数える）のとおりで、追加の除外はしない。
- (a′): 窓の記録はすべて回路自身の `LC.step!` の `acting`・`drove` から作る（BODY には外のテープがない）。各記録に `external=false` を付け、一件でも true の窓は未判定。
- 分岐点: E＝{t ∈ 32:32:H | t の更新の後に本走の身体が生きている}。各 t で、更新の後の全状態（回路・世界・物質のたまり・乱数）を deepcopy し、
  無介入 N・X（t＋1 から m1・m2 を sil）・Y（t＋1 から c1・c2 を sil）の 3 分岐を絶対時刻 t＋H まで進める（予定表の位相は絶対時刻で保つ）。
  死の時刻＝更新の後に身体の場所がなくなった最初の絶対時刻。
- (b1): X の分岐で、t＋1〜t＋32 のどこかの更新の後に κ（q≥1 で受容器から出ない辺）が空になるか身体が死んでいれば成立。
  X の分岐で確かめ（`confirmed_patch` か `call_confirmed`）が一件でも起きれば L9 の対応が退けられるので未判定。確かめがないのに 32 更新後も κ が空でなく生きていれば、L2 の対応が退けられるので未判定。
- (b2): N が t＋H で生きていて X が t＋H までに死ねば成立。N が死ぬ、または X が生き残れば不成立（有効な測定の不成立）。分岐が作れなければ未判定。
- (b3)（T_core）: N が t＋H で生きていて Y が t＋H までに死ねば成立、それ以外は (b2) と同じ。Y の分岐の確かめも数える（記録だけ）。
- (c): 規則の判定（F9、bin3 は収量の比較を使わない、`formal/README.md:75`）。全事象で成立と記録する。
- T(t): (a)(a′)(b1)(b2)(c) がすべて成立なら成立。どれかが不成立なら不成立（(b2) の不成立は「その t に T を当てない」、D2 §5）。それ以外は未判定。T_core(t)＝T(t) かつ (b3)。
- T⁺: t0 ∈ E で T(t0) が成立のとき、t0 から本走の終わり（H）までの連続する事象で (a)(a′) が成立し続ける最長の区間 [t0, t1]。

## 2. 照合と対照
- Lean: 本走の窓から、各節（self・smc・act・bound・dc）の真偽がそれぞれ出る窓を選び（あれば各 2 つ）、`formal/gen/WindowsBody.lean` に書き出して Lean の `Window.checkDC` で評価し、Julia と全部一致すること（D2 §5、食い違えば (a) を退ける）。
- 負の対照: (i) X の名で何も黙らせない分岐を 1 つの事象で作ると、確かめの検出が正（b1 未判定）かつ (b2) 不成立になること。(ii) 窓の記録の一件に external=true を立てると (a) が未判定になること。
  (iii) 同じ組を 2 回走らせて全記録が一致。(iv) 予測の外の種子 1 で、1 つの予定表・H 294 の短い走りを最初の確かめとして使う（主張に使わない）。
  (v) 差し込み口あり・なしで本走の終わりの状態（q・sg・活動・身体の場所）が一致。

## 3. 予測（凍結、`experiments/predictions-selfmaint.md`）
- SP1〜SP7（ファイルのとおり）。

## 4. 試験
- `GATE: cd experiments && for H in 294 392 588; do HORIZONS=$H EXTRAS=$([ $H = 294 ] && echo 1 || echo 0) OUT=$PWD/results-selfmaint-H$H.json julia --project=.. selfmaint.jl; done && julia --project=.. check_selfmaint.jl && sh dc_lean_body.sh`
  （H ごとに別の過程で並行に走らせる。対照と Lean の書き出しは H294 の過程だけ。検査は 3 つのファイルを読み、組（H・種子・腕・予定表）の網羅と一意を確かめる。codex I-R 4・8）
- I-R での限定（codex 2026-11-07）: (a′) は「外のテープを使わず回路自身の acting・drove を記録する構成」に限る（external=false は検出ではない、3）。
  X の分岐で確かめが一件でもあれば、L9 の対応は全体で退けられ、すべての (b1) とそれに依る T を未判定とする（6）。Y の分岐の確かめは記録だけ。
  SP4 が外れても「区画の行為が同等でない」とは結論しない（維持費は kept の数に依り、回路の状態の違いが死の時刻に効きうる、5）。
  (c) は規則の判定で、根拠は X5 を外した bin3（`formal/README.md:75`）と `core/circuit.jl` の統計の更新（区画の答えの有無 dm>0 を 1/0 にして、受容器の点いた・消えたで比べる。二つの区画の収量どうしは比べない）。
  core/dc.jl の変更は `sh core/check/run.sh` と既存の `sh audit/dc_lean.sh` の一致を確かめてから受け入れる（10）。
- 凍結の sha の一致。S4〜S6 の結果ファイルが変わらないこと（差し込み口の既定は nothing）。
