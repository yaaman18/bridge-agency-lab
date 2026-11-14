# S50 predictions (frozen before any code exists; hash in freeze-phase-jump.txt; 2026-11-14). Spec: ../discussion/specs/S50-phase-jump.md r3.

Smoke (seeds 629-630): gates Z0-Z4; timing only. Main: seeds 631-642, laws L2, L2+SF, reference GREEDY,
Tj in {3800, 4250}, J in {0, 100, 300, 500, 700, 1000}. Cells = law x Tj x J in {100, 300, 500, 700}: 16 for ORG, 8 for GREEDY.
Main quantity: V_J(w) = D_J(w) - A_J(w) per seed (paired), D_J = agreement of baseline steps t+J and t+J+1000.
"Disturbance present" in a cell = at least 8 untied seeds, exact two-sided sign test p <= 0.05, and the positive side larger
(12 untied needs 10 or more positive). It is not a count of seeds with V_J > 0 nor a mean.

- PJ1 (negative control): every J = 1000 run is bit-identical to its J = 0 run. Any difference = the construction is wrong, no reading.
- PJ2 (right after the jump): in window 1, "disturbance present" in more than half of the 16 ORG cells. Miss: 8 or fewer.
- PJ3 (it settles within one period): in window 10, "disturbance present" in fewer than half of the 16 ORG cells. Miss: 8 or more.
- PJ4 (the fixed rule too): GREEDY shows "disturbance present" in window 1 in at least half of its 8 cells. Weak guess.
- PJ5 (no excess death): in no ORG cell does the number of lives dying in [Tj, Tj+2000) in the jump run exceed the number dying
  in the same interval [Tj, Tj+2000) of the baseline run of the same seeds by 3 or more. Miss: 1 or more cells.
- No prediction on the body size, on the first-step difference, on B_J, or on ORG versus GREEDY.
- Reading limits: phase jump = stop only under a periodic schedule; two Tj are local; the seeds differ in noise only; the cells
  share seeds, so the cell majorities are descriptive, not independent replications; low power with 12 seeds; no pooled p value;
  nothing is claimed beyond acts, kept connections and body. The table "result -> what changes" (spec section 5) is part of this.
