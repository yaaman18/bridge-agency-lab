# Predictions for stage 33, TRM-type constituents on the material layer (trm.js, matter2.js, test_trm.js), written
# 2026-10-31 before any run of test_trm.js. Constants of trm.js (D 4, K 4, N_REC 3, ETA 0.05, ERR0 0.05, THETA_PI 0.5,
# MUT 0.05, INIT 0.5) were set once and run in a short exploratory pass (explore_trm.js, supply x1, 4000 steps, seeds 1-2,
# reported): TRM populations were larger in lean seasons (147-181 vs 98-101 for the fixed rule) at activity ~0.6-0.7.
# matter2.js without control reproduces matter.js exactly (checked). Seeds 1-3; "survived" = constituents > 0 two thousand
# steps after a starvation of L steps that starts at step 4000.
Z1  Conservation: |error| < 1e-6 mu in every run.
Z2  TRM persists (> 0 at every 100-step sample to 6000) with supply x0.5 and x1 in all 3 seeds.
Z3  Dormancy pays under starvation: the longest starvation survived (of 500/1000/1500) is at least as long for TRM as
    for the fixed rule in 3/3 seeds and longer in >= 2/3.
Z4  (explored, restated) In lean seasons (supply x1, steps 3000-6000) TRM's mean count exceeds the fixed rule's in 3/3.
Z5  Anticipation: TRM's mean activity in the 100 steps before a lean season starts is lower than before a rich season
    starts (supply x1, after step 3000) in >= 2/3 seeds.
Z6  Regeneration: after removing the left half at 4000, TRM's count is >= 0.8 of its undamaged twin by +1000 steps in >= 2/3.
Z7  Heredity carries organization: TRM's mean precision (steps 3000-6000, x1) exceeds noinherit's in >= 2/3 seeds, and its
    minimum count at x0.5 is at least noinherit's in >= 2/3.
Z8  The precision gate on division changes little: nogate's mean precision is within 0.05 of TRM's in >= 2/3 seeds.
