# Predictions for stage 54 (plan 1 = "bin3", plan 2 = "donly" of memory/turn_sed.js; matter/test_alt.js,
# memory/test_org_alt.js, memory/test_scaffold_seeds.js, memory/summarize_alt.js), written 2026-10-31 before any run of
# bin3 or donly. Checked first: turn_sed.js without the option = turn.js (108000/108000); learn2 and learn3 reproduce
# their scaffold results byte for byte. New constant THETA_B = 0.1 (difference of answer probabilities; chosen before
# any run). Same protocols as stages 50-52 (org world: 5 seeds; body: 10 worlds; scaffold: seeds 1-40 vs turn.js).
Q1  bin3 removes chance sediment without amounts: noise/clock sediment on patch motors at 3000 (org world) <= 2 in 5/5.
Q2  bin3 keeps the body's advantage: alive at 10000 in >= 9/10 worlds, mean body >= old rule's + 1 in >= 8/10.
Q3  bin3 with receptors crossed at 5800: body alive in >= 8/10.
Q4  donly does not remove chance sediment: noise/clock sediment >= 10 in 5/5.
Q5  donly keeps acting after the crossing: org world acts per step >= 0.85 in 5/5, and body crossed alive >= old rule's.
Q6  Scaffold (seeds 1-40) for both: patch answered fraction >= turn.js - 0.02 in >= 80% of seed x condition x phase, and
    no condition with a significant (5%, sign test) change of the phase-A late waiting share.
