# S53b predictions (r2 after the S-R; r1 is in freeze 0; frozen before any code is written or run; 2026-11-15). Spec: ../discussion/specs/S53b-stake-fix.md.

World, levy, laws and points as in S53 (predictions-stake.md). Arms ORG and ORG-FIX (FIXAT = T0 = 800). Windows 657-668
(n = 12). Paired sign tests over windows, two-sided 5 %, ties dropped, fewer than 8 non-ties = undetectable. Each
prediction is judged alone, per law. Known before this freeze: S53's results for ORG on windows 645-656 (item 161), and
item 155 (without the levy, on other windows, fixing made the body smaller at 13 of 20 points for L2 and at 0 of 20 for
L2+SF). Nothing is known for these windows or for ORG-FIX under the levy. The author's confidence is low.
- PF1 (the control lives; eligibility): for lambda = 0 and lambda = 2, at s = 0 and at s = 3, ORG and ORG-FIX are both
  alive at T0 + 2000 in at least 8 of 12 windows (both laws). For lambda = 8 at s = 3 fewer than 8 (S53: ORG itself died
  there in all windows), so lambda = 8 falls to G500 or is undetectable. The primary quantity per law and lambda follows
  the frozen order of the spec, section 2 (G2000, else G500, else undetectable). "Both alive in 8 windows" is counted on
  the common set: windows (same seed) where all four runs (ORG and ORG-FIX at s = 0 and at s = 3) are alive at that time.
- PF2 (is the control weaker at s = 0?): L2: S_ORG > S_FIX at s = 0 ("larger"). L2+SF: undetectable.
- PF3 (the stake, as "what updating is worth"): G(s = 3) - G(s = 0), by the sign test on the primary quantity, for
  lambda = 0, 2, 8 separately. Predicted: L2: larger for lambda = 2; no prediction for lambda = 0 and 8 (reported).
  L2+SF: undetectable for every lambda. If not larger for L2 at lambda = 2, the reading "the amount of others raises
  what updating is worth" is not supported there; if smaller, the opposite reading is reported.
- PF4 (replication of S53's PK5 on new windows, ORG only, S at T0 + 2000, s = 3 against s = 0): L2+SF larger at
  lambda = 2 (sign test). For the other three cells only a direction is predicted, judged apart from significance, by
  the count of windows (more windows on the predicted side than on the other; equal counts = miss): L2 at lambda = 2:
  more windows larger than smaller; lambda = 8, both laws: more windows smaller than larger. The sign-test result is
  reported beside each.
- Reading limit (frozen): G is the body gap on windows where all four runs are alive; it is not the total worth of
  updating including death, and survivor selection depends on arm, s and lambda.
- Reported without prediction: requested and taken levy per arm, death steps, bodies at T0 + 500 and at the horizon, requested and taken levy, realized
  mean yield, the share of steps on which ORG and ORG-FIX act alike.
- Not claimed: what having a circuit is worth (the silenced arm dies at once; S53), anything about real radio, s changing
  during a life, other noise, a right lambda, a general shape of the stake, or that the individual feels anything.
- Smoke: windows 643-644, script and gates only; not used for any claim.
