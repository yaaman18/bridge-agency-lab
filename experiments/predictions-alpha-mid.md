# Predictions for S23 (discussion/specs/S23-body-alpha-mid.md r1), frozen before any alpha_mid.jl run
New seeds 221-230 (never run), SF, arms std/swap, lab schedules mid-32 (3,2), mid-23 (2,3), mid-32to23 (3,2)->(2,3), mid-41to14 (4,1)->(1,4) (switch 20), points t in 64:32:384, motors m1/m2, pre-step pools {0..10}U x {0..10}U; pairs, cells and "realized" as in S20b.
Pooled over all conditions. A pair whose motor has zero usable pairs is not evaluable (not a success).
- AM1: m1->r7 and m2->r8 are each realized (a nonzero C-B difference) in at least one usable pair.
- AM2: all 8 declared pairs (m1->r1,r3,r7,r8; m2->r2,r4,r7,r8) are realized.
- AM3: the undeclared coupled pairs (m1->r2,r4; m2->r1,r3) show zero differences over all usable pairs (one -> miss).
- AM4: r5 and r6 show zero differences over all usable pairs (one -> miss).
