# Predictions for S6 (discussion/specs/S6-body-tcommon.md r1), frozen before any tcommon.jl run

Same objects as S4/S5: RULE=sf, seeds 21-30, H 294/392/588, arms :std and :swap (60 arms). Interventions the same for
every arm (not chosen by the arm's T): I0 none, I1 = r1..r6 silenced (only r7, r8 left), I2 = r1, r2 silenced.
Probes (lab only, constant yields, switch 20, window 5:15, choice_params): ties (1,1) (2,2) (3,3) (4,4) (5,5);
non-ties (2,1) (1,2) (3,1) (1,3) (5,3) (3,5) (4,2) (2,4) (5,1) (1,5) (3,2) (2,3) (5,4) (4,5).
- AP0: S5 reproduced: under I0, the S5 probes give S5's choices for 60/60 arms; the repeat equals; negative control detected.
- AP1 (main): under I0, on every non-tie probe, every arm chooses the motor of the higher patch only (60/60 arms, 14 probes).
- AP2: under I0, the two arms of a seed differ on some probe only if that probe is a tie (every seed, every H).
- AP3: under I1 and under I2, the two arms of a seed differ on some probe only if that probe is a tie (every seed, every H).
- AP4: under I1, on every non-tie probe, every arm chooses the motor of the higher patch only.
Falsification: AP1 or AP2 false -> "the arms differ only at ties" is refuted for the unintervened system.
AP3 false -> under an intervention common to the arms, the arms also differ off ties.
