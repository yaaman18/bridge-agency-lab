# Predictions for S5 (discussion/specs/S5-body-tcontent.md r1), frozen before any tcontent.jl run

Same objects as S4: RULE=sf (current + sed_fade, KC_trial 0.0015), seeds 21-30, H 294/392/588, arms :std and :swap.
Arm type by T: P2-detector (T = {r2,r8}), P1-detector (T = {r1,r7}), both (T = {r1,r2,r7,r8}).
- CP0: T and choices recomputed equal S4's record for 60/60 (seed, H, arm); the repeat equals; negative controls detected.
- CP1: the discriminating cues (true in exactly one choice schedule over window 5:15) are r7 and r8 only; r1 and r2 are
  true at all 11 window steps of both choice schedules.
- CP2: P2-detector arms have q >= 1 on r2->m2 and r8->m2; P1-detector arms have q >= 1 on r1->m1 and r7->m1.
- CP3: with T silenced, P2-detector arms choose m1 in both choice schedules, P1-detector arms m2 in both.
- CP4 (main): on eq-high (4,4), P2-detector arms choose m1 and P1-detector arms m2; so seeds 24, 28, 29 differ between
  the arms on eq-high at each H.
- CP5: on lo-1 (2,1) and lo-2 (1,2), P2-detector arms choose m1 on both, P1-detector arms m2 on both.
- CP6 (weak): seeds with the same T in both arms (21, 22, 23, 25, 27, 30) choose the same on every probe.
- Seed 26's both-detector arm: no prediction.
Falsification: CP2 or CP3 false -> withdraw reading the T difference as "which patch the detector picks out".
CP4 false -> the content difference does not show as action outside the frozen schedules (T difference only).
