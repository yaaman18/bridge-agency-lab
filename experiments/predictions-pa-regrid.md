# S47b predictions (frozen before any code exists; 2026-11-14). Spec: ../discussion/specs/S47b-regrid.md r1.

Note frozen with the predictions: these are written after seeing README item 155 (descriptive, K=2000: alive at the horizon
ORG 143/240 (L2), 123/240 (L2+SF), GREEDY 66/240; lifetime "gain" at 6 and 7 points). They are not an independent prior.

Smoke (seeds 601-602): gates R0-R3 behave as specified; timing only. No effect of the smoke is read.

Main (evaluation seeds 603-614 shared by the three candidates; 20 points (P, sigma, L, M) x laws L2, L2+SF):
- PB1: for each candidate (C1: K=2000 read at T0+4000; C2: K=2000 read at T0+9200; C3: K=1000 read at T0+2000) and each law,
  "gain" (ORG body larger than GREEDY, sign test two-sided 5%, at least 8 untied windows) at more than half of the 20 points.
  Six cells (3 candidates x 2 laws), each reported on its own. Miss for a cell: 10 or fewer.
- PB2: with the same seeds and K=none, "gain" at 0 of the 20 points at each of the three reading steps, for each law. Miss: 1 or more.
- PB3: ORG vs GREEDY-KC (all windows): with K present, "no gain (GREEDY-KC larger)" at 0 of the 20 points, each candidate and law. Miss: 1 or more.
- Refutation: each PB that fails is recorded as a miss as it stands. C3 changes K and the reading step together and is not
  read as the effect of K alone. The three candidates share windows and are not three independent confirmations.
  No pooled p value, no overall success. The table "result -> what changes" (spec section 5) is frozen with these predictions.
