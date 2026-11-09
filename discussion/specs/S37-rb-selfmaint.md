# S37 D2 の規則 T を RB の実走に当てる（R-BODY-4 の RB 版、三値判定）

- 状態: r1（2026-11-09、ユーザー「現行の RB で 3 つをやり直す」。読みは `notes/RB-redo.md` r2。claude-lab が書き、codex-lab が I-R）。
- 対象: RB（SF 版＋rest＋rest_body :B＋α、`notes/RB-redo.md` §0）、腕 :std・:swap、**種子 441〜450（未使用）**、生存の予定表 4、H 392 の 80 走。
- 手順は S7（`specs/S7-body-selfmaint.md` r2）と同じ（`experiments/selfmaint.jl`、`RBV=1` で RB。既定は S7 のまま、S7 の欄は種子 31 で一致を確かめた）。

## 1. RB で足すもの（読みは RB-redo §2）
- 元の T（(a)(a′)(b1)(b2)(c)）と T_core はそのまま判定して記録する。RB では元の (a) は規則で成り立たない（`formal/LabCircuit.lean` Window.no_self_of_unreproduced: 確かめられない生まれつきの自己の辺 c1・c2→m0 が kept にある）、元の κ は X で空にならない（`formal/SelfMaintenance.lean` lsH2k）。
- κ_prec＝κ のうち減衰を免除されない辺（失われうる辺。α の免除は patch 4 の運動への q0>0 の辺だけ、`core/circuit.jl:289`）。
- H2（(b1) の κ_prec 版、b1p）: X の分岐で t＋1〜t＋32 のどこかの更新の後に κ_prec が空か身体が死ねば成立。X の確かめが一件でもある、または κ_prec の辺の q が X で増えれば（lsH2 の写しの反証）未判定。H2 の反証＝32 更新まで生存し、その間 κ_prec が一度も空にならない（RB-redo §2）→ b1p 不成立。lsH2 の写し（κ_prec の q≤4、各更新で q_new≤decay(now, q_old)、now は回路の時計）を X の分岐の更新ごとに確かめ、破れれば未判定（codex I-R 3・4）。
- H3（(a) の κ_prec 版、a_prec）: 窓の kept を κ_prec に限って check_dc。除外の理由は α の免除に限る（減衰を免除された辺は失われえず、確かめも受けない。生まれつきの辺一般を産出の対象外とは言わない、codex I-R 1）。T_prec はこの対象に限った命題。
- T_prec＝(a_prec)(a′)(b1p)(b2)(c)、T_prec_core＝T_prec かつ (b3)。T と T_prec は別の命題で、一方の成立を他方へ移さない。
- 記述: 本走の生きた歩ごとの行為（m0・区画・なし、同じ分母）、各分岐の m0 の行為の数、元の κ が X で空になったか。
- Lean: 元の窓と κ_prec の窓の両方から、各節の真偽が出る窓を（あれば各 2 つ）書き出し、Lean の checkDC と全部一致すること（`dc_lean_body.sh rb`）。
- 対照: S7 の (i)〜(v)。RB の :std は食べず確かめがないので、対照は :swap の腕（種子 1、主張外）で行い、(ii) は a_prec で行う。

## 2. 予測（凍結、`experiments/predictions-rb-selfmaint.md`）
- RP1〜RP9（ファイルのとおり）。

## 3. 試験
- `GATE: cd experiments && RBV=1 SEEDS=$(seq -s, 441 450) HORIZONS=392 EXTRAS=1 GEN=rb OUT=$PWD/results-rb-selfmaint.json julia --project=.. selfmaint.jl && julia --project=.. check_rb_selfmaint.jl`（Lean の照合は検査の関門の中）
- 検査は組（種子 10×腕 2×予定表 4）の網羅と一意、対照、凍結の sha、Lean の checkDC と Julia の一致を関門として確かめてから RP を判定する（codex I-R 5）。
- 予測は煙試験（種子 1）を見て κ_prec・H3 を定めた後に書いた。規則だけからの独立な予測ではない（codex I-R 2）。
