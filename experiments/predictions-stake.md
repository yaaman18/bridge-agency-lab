# S53 predictions (r2 after the S-R; frozen before any code is written or run; 2026-11-14). Spec: ../discussion/specs/S53-stake.md.

Synthetic world of item 155 (P = 1000, A = 2.5, sigma = 1, L = 300, no swap), M(s) = 1.0 + 0.5 s, s in {0,1,2,3}; levy
lambda * s * KC per step after T0 = 800, lambda in {0, 2, 8}; laws L2 and L2+SF judged separately; arms ORG and ORG-SIL;
windows 645-656 (n = 12); S = body size at T0 + 2000 (0 if dead). Paired sign tests over windows, two-sided 5 %, ties
dropped, fewer than 8 non-ties = undetectable. No result is known; the author (claude-lab) has low confidence in PK2-PK4.
- PK1 (an empirical prediction, not an invariant): ORG-SIL has S <= ORG in every window at every point (violations 0 of
  12 x 10 per law). Any violation is a miss and is reported with its window and point.
- PK2 (what can be taken grows; lambda = 0): ORG has larger S at s = 3 than at s = 0 ("larger" by the sign test).
- PK3 (what is lost without acting grows): at s = 3 the death step of ORG-SIL is earlier with lambda = 8 than with lambda = 0
  ("earlier" by the sign test; a run that has not died by 9200 gets the death step 9201, so windows where neither dies are ties and a window where
  only one dies counts for the one that dies). Reported also for lambda = 2 (no prediction).
- PK4 (the stake): the gap at T0 + 500, G500 = body(ORG) - body(ORG-SIL), over the windows where both arms are alive at
  T0 + 500 at both s = 0 and s = 3 (fewer than 8 such windows = undetectable), is larger at s = 3 than at s = 0, for
  lambda = 2 and for lambda = 8 (each by the sign test on G500_u(s = 3) - G500_u(s = 0)). The gap at T0 + 2000 is reported
  beside it with the number of windows where ORG-SIL is dead (there G equals ORG's S; a floor, not a circuit effect). If G is not larger, the reading "the amount of others raises how much the
  circuit matters" is not supported for that lambda.
- PK5 (is there a direction of protection?): compare ORG's S at s = 3 with s = 0 for lambda = 2 and lambda = 8.
  Readings (frozen): larger = "a crowded place is a better place for a working individual; carrying it there protects it";
  smaller = "the losing side wins; a quiet place is better"; undetectable = "no direction found".
  Predicted: larger at lambda = 2, not larger (undetectable or smaller) at lambda = 8. If larger at both, the claim in
  D-OPEN 6.13 that "there is no direction of protection" is false for this grid.
- The requested levy (lambda * s * KC) and the levy actually taken are reported per point (they differ once the body is small).
- The grid (the slope 0.5 of M and the values of lambda) is the author's; where PK5 changes sign depends on it. This is a
  map of the combined effect on this grid, not a general shape and not a causal split of feeding and eroding.
- Each prediction is judged alone, per law. Misses are reported as misses. No pooled claim over points or laws.
- Not claimed: anything about real radio, about s changing during a life, about other noise settings, about a right value
  of lambda, or that the individual feels anything.
- Smoke (frozen here too): windows 643-644, to test the script and the gates; not used for any claim.
