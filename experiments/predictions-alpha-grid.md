# Predictions for S20 (discussion/specs/S20-body-alpha-grid.md r1), frozen before any alpha_grid.jl run
New seeds 151-160 (never run), SF, arms :std/:swap, 4 survival schedules, points t in 64:32:384, motors m1 and m2, pools set on the 7x7 grid {0..6}U before t+1.
A motor with zero usable events makes its pairs not evaluable.
- AG1: each of the 8 declared pairs (m1->r1,r3,r7,r8; m2->r2,r4,r7,r8) is realized (a receptor difference at the second update) in at least one usable event.
- AG2: the undeclared coupled pairs (m1->r2,r4; m2->r1,r3) show zero differences over all usable events.
- AG3: r5 and r6 show zero differences over all usable events.
- AG4 (natural state, no grid; the 1% is a guess without an established basis): numerator = natural-state usable events (m1 and m2 pooled) with a difference in r7 or r8 (an event counted once); denominator = natural-state usable events (m1 and m2 pooled). The ratio is <= 1%; above 1% is a miss. Zero natural-state usable events -> not evaluable (not a success), whatever the grid shows. Per-motor and per-receptor counts are reported.
