# S47 predictions (frozen before any code exists; 2026-11-13). Spec: ../discussion/specs/S47-synth-grid.md r3 (§5 judgments, §7, §7.1).

## Smoke (seeds 561-564): timing and gates only
- Every gate G0-G6 (with G1g) and its negative control G5 behaves as specified. G4 reproduces results-grow81.json
  (frozen seasons L2 10/10 alive, random L2 1/10, GREEDY 10/10).
- The smoke measures the time of one run of each arm. No effect, p value or survival count of the smoke is read for any
  decision. Reduction rule (spec §8 Q5): if the estimated total wall time of the main run on this Mac (with the parallelism
  actually used) exceeds 48 hours, cut in this order until it does not: (1) the NC of the GREEDY table, (2) the L=1 points,
  (3) the P=250 points. The estimate and the decision are written to results-pa-grid-smoke.out before the main run starts.

## Main (evaluation seeds 565-576, NC donors 577-588; 60 points x laws L2, L2+SF; tau = 2000)
- PA1 (a): ORG-SIL has a body at T0+tau not larger than ORG in every point and window.
- PA2 (b): at the K=none, sigma=0 points (4 points x 2 laws), (b) is established (D>0, p<=0.05) in at least 5 of 8.
  At sigma=2, L=300 points: undetectable is predicted (no count frozen).
- PA3 (c, body size): at the 20 K=none points, "gain" (ORG larger, sign test two-sided 5%, at least 8 untied windows)
  occurs at 0 points, for each law. Miss: at least 1 point.
- PA4 (c, K=2000): "gain" at more than half of the 20 K=2000 points, for each law. K=250: no prediction.
- PA5: at K=none, sigma=0 points the agreement of the acts of ORG and ORG-FIX after T0 is at least 0.9.
- PA6 (reference for b): at the 4 K=none, sigma=0 points the GREEDY table also establishes (b) at 3 or more. Miss: fewer than 3.
- PA7 (c with matched upkeep billing): over the 20 K=none points x 2 laws, the number of points judged "no gain
  (GREEDY-KC larger)" in ORG vs GREEDY-KC is smaller than the number judged "no gain (GREEDY larger)" in ORG vs GREEDY.
  Miss: equal or larger.
- Refutation conditions: G4 fails -> no map. NC significant at more than 15% of point x law tables -> (b) not used until
  examined. PA4 misses with "no gain" at more than half of K=2000 -> record that no region where learning pays was shown
  under this KC.
- No overall success is declared; the result is a map per point. Reading limits are those of spec §5 (what a rejection says).
- The table "result -> what changes in stage B / JB" (spec §7.1) is frozen with these predictions.
