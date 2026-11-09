# Predictions for S20b (discussion/specs/S20b-body-alpha-scan.md r1), frozen before any alpha_scan.jl run
New seeds 161-170 (never run), SF, arms :std/:swap, 4 survival schedules, points t in 64:32:384, motors m1 and m2, pre-step pools x in {0..10}U x {0..10}U.
A pair = C and B from the same snapshot and the same x; a difference = C vs B at the second update within that pair. A motor with zero usable pairs makes its pairs not evaluable; a pair-set of size 0 is not counted as support of a zero difference.
- AG1b: each of the 8 declared pairs (m1->r1,r3,r7,r8; m2->r2,r4,r7,r8) shows a nonzero C-B difference in at least one usable pair.
- AG2b: the undeclared coupled pairs (m1->r2,r4; m2->r1,r3) show zero differences over all usable pairs.
- AG3b: r5 and r6 show zero differences over all usable pairs.
