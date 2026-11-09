# S25 駆動で保つ sed_fade の変種 SFD と SF の比較（agenda T1、`notes/T1.md`）

- 状態: r1・実施済み（README 項番124）（2026-11-08、往復1 の codex 1〜8 を反映）。変種は既定オフ（`core/circuit.jl` sed_fade_drive、`variant_horizon.jl` SEDFADE_DRIVE）。採用はユーザー判断。探索の比較で、必要な精度の根拠はない（codex 7）。
- 規則（codex 2・8）: 更新で辺 k が駆動し（drove[k]）、その辺の運動がその更新の acting に入るとき、確かめと同じく lastC[k]＝now（sg は変えない）。選ばれた運動に入る駆動の辺は全部戻る（行為に不可欠でない辺も保たれうる）。同点で別の運動が行為した辺は戻らない。
  順序: 行為の決定の後、同じ更新の sed_fade の段で薄れの代わりに戻す。Lean `SedFade.stepDrive`・`driven_keeps`・`stepDrive_undriven`・`stepDrive_le`・`clears_unused`（証明済み）。育ちと試しの両方に効く（非 grow 版）。
- (a) 習慣の側（`sfd_habit.jl`、S18 habit3.jl と同じ判定、育ちの再現も SFD で）: **種子 251〜290（未使用）**、両腕、生存の予定表 4（320 走）を SF と SFD で。点 t∈64:32:384。
  分けて報告（codex 4）: ① 出現＝j3（沈殿だけの型）の点が 1 つ以上ある走りの数、② 条件つきの持続＝j3 の点のうち N（無介入）が t＋400 に E の支えを保つ割合、③ R3-b′ の全条件の成立＝(1)(2)(3) がすべて判定できた点のうちの成立数。
- (b) 兼ね合い（`variant_horizon.jl` SFD=1）: **種子 291〜310（未使用）**、両構造、地平 60・294・392・588、CUR std と swap。道具の L2 を SF と SFD で同じ種子の対で比べ、(地平, 構造, 腕) ごとに真の数と、SF 真→SFD 偽・SF 偽→SFD 真の数を報告（codex 5）。
  L2 は AS.evaluate の真偽で、死・未判定の別の分母はない（各走りが一つの真偽）。地平・構造・腕は独立の種子として数えない。
- 予測（凍結、`experiments/predictions-sfd.md`）。
