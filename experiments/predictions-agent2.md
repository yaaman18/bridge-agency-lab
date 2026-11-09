# Predictions for S17 (discussion/specs/S17-body-agent2.md r1), frozen before any agent2.jl run
Seeds 91-100 (never run), SF, arms :std/:swap (20 objects; the two arms of a seed are not independent samples), H 392. One contract: survival schedules.
- AH1 (trajectory control): for all 20 objects, the survival recorded in B1 (p1-high) and B2 (p2-high) equals the tab's intact entries.
- AH2: an Agent value is built (agentOf type-checks) for >= 15 of the 20 objects.
- AH3: for >= 18 of the 20 objects, the window w passes checkDC.
- AH4: for >= 15 of the 20 objects, checkValueNeeded holds with T_struct (silenced from update 1 in all 4 survival schedules).
Each object that fails is reported with the missing fields; an unattributable receptor is not counted as a failure by itself.
