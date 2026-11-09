# Predictions for S8 (discussion/specs/S8-body-tiesource.md r1), frozen before any tiesource.jl run

Objects: RULE=sf, arms :std/:swap, H 294/392/588; seeds 21-30 (seen in S6) and 31-40 (not seen). Tie probes (1,1)..(5,5).
Interventions common to every arm: J0, J3 {r3}, J4 {r4}, J5 {r5}, J6 {r6}, J12 {r1,r2}, J56 {r5,r6}, J125, J126, J1256.
Written from the features of the receptors at ties (r3, r4, r7, r8 off; r1, r2 on only for k >= 3), not from runs of seeds 31-40.
- RP1: J3 and J4 each give the J0 choice on every tie probe, for every arm (receptors that are off at ties do not drive).
- RP2: J1256 gives no choice on every tie probe, for every arm.
- RP3: J12 gives the J0 choice on (1,1) and (2,2), for every arm (r1, r2 are off there).
- RP4: J56 gives no choice on (1,1) and (2,2), for every arm.
Each RP is reported separately for seeds 21-30 and 31-40. Falsification: RP1 or RP3 false -> a receptor that is off at the
probe changes the tie choice (through the state carried from the raising, or a rule not read here); RP2 or RP4 false ->
something other than r1, r2, r5, r6 produces tie acts.
