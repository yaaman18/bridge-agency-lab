# Predictions for stage 50 (learn2 in the organization layer, offline; the app is not changed), written 2026-10-31
# before any run with turn_learn2.js. Checked first: turn_sed.js without the option = turn.js (108000/108000 steps), and
# test_scaffold.js with CORE=./turn.js reproduces results-scaffold.json (stage 25) byte for byte. No new constants
# (learn2's ALPHA 0.05, THETA_C 0.5, FORGET 100 from stages 48-49). learn2 touches only receptor -> patch motor edges.
O1  Foraging is kept: answered fraction of patch acts with learn2 >= turn.js - 0.02 in >= 36/45 (3 conditions x 5 seeds x
    phases A, B, C of test_scaffold.js).
O2  Waiting is kept: late waiting share of phase A with learn2 <= turn.js + 0.05 in >= 4/5 seeds, for SCAF-RAISED and
    for RESP-ADULT.
O3  Chance sediment falls: sediment on r5, r6 -> m1, m2 at step 3000 of test_org_learn2.js lower with learn2, 5/5 seeds.
O4  The weakness of stage 49 is there too: after the receptors are crossed, learn2's answered fraction (steps 1000-3000
    after) <= turn.js's in >= 4/5 seeds, and learn2 recovers later (or never) in >= 4/5.
O5  The circuit's form (closed loop share) in phase A of SCAF-RAISED with learn2 >= turn.js - 0.05 in >= 4/5 seeds.
