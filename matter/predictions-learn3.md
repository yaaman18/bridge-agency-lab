# Predictions for stage 51 ("learn3" of memory/turn_sed.js; matter/test_learn3.js, memory/test_org_learn3.js,
# memory/summarize_org_learn3.js), written 2026-10-31 before any run of learn3. Checked first: turn_sed.js without the
# option = turn.js (108000/108000); learn2 reproduces results-scaffold-learn2.json byte for byte and stage 49's verdicts.
# learn3 = learn2 + a patch motor idle for FORGET (100) steps counts as untried for sampling. No new constants.
# The recovery is measured by acts per step this time (stage 50's measure saw only the answered fraction).
P0  Conservation |error| < 1e-6 in all body runs.
P1  Body, receptors crossed at 5800: learn3 alive at 10000 in >= 8/10 worlds.
P2  Body, no crossing: learn3 alive 10/10 and mean body >= learn2's - 1 in >= 8/10.
P3  Body, crossed: learn3 acts on >= 90% of steps 6800-10000 in >= 8/10.
P4  Organization world, crossed at 3000: learn3 acts per step over 1000-3000 steps after >= 0.85 in >= 4/5 seeds
    (turn.js 0.90, learn2 0.47-0.61 in stage 50).
P5  Organization world: noise/clock sediment on patch motors at 3000 <= 2 in 5/5 (learn2: 0).
P6  test_scaffold.js with learn3: patch answered fraction >= turn.js - 0.02 in >= 36/45, and SCAF-RAISED late waiting
    share <= turn.js + 0.05 in >= 4/5.
