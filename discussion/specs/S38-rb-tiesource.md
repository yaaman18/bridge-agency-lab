# S38 同点の行為を生む受容器はどれか（S8 の RB 版）

- 状態: r1（2026-11-09、ユーザー「現行の RB で 3 つをやり直す」。読みは `notes/RB-redo.md` r2 §3。claude-lab が書き、codex-lab が I-R）。
- 対象: RB、腕 :std・:swap、**種子 451〜460（未使用）**、H 392。同点の試し (1,1)〜(5,5)（S8 と同じ作り方: choice_params、switch 20、窓 5:15）。
- 介入: S8 の J0・J3・J4・J5・J6・J12・J56・J125・J126・J1256 × rb の条件「通常の入力」「rb 偽固定（BODY_CLAMP、試しの全歩）」。偽固定は経路の除去ではない。差が出ても結論はこの二条件の間の依存に限る（RB-redo §3）。
- 記録（同じ分母＝窓の歩×試し）: 各歩の行為（勝者、step! の acting、読むだけの差し込み口）＝m0・区画（m1/m2）・なし、運動の点灯（m1・m2・m0、S8 の「選択」は区画の運動の点灯）、窓の最初の歩の rb と窓の中の rb の点灯の数。
- くり返しの一致（同じ組を 2 回）。
- 予測（凍結、`experiments/predictions-rb-tiesource.md`）: TR1〜TR4。J5・J6・J125・J126 は記述（r5・r6 のどちらが効くか）。
- 予測は煙試験（種子 1）を見た後に書いた。規則だけからの独立な予測ではない。
- `GATE: cd experiments && julia --project=.. tiesource_rb.jl && julia --project=.. check_rb_tiesource.jl`（関門: 凍結の sha〈必要なファイルの一覧〉・組の網羅と一意・くり返し → TR）
