# Predictions for stage 27, option D: configural units for the call (config.js = turn.js rev. 2 + Pearce-type J units
# recruited at the first co-occurrence of a receptor pair; m3 driven only by c3 and J units). Written 2026-10-31 before
# any run of config.js with configural=true. configural=false reproduces results-scaffold.json exactly (checked).
# Harnesses: test_config.js (= test_scaffold.js + J summaries), diag_scaffold.js, test_config_orient.js (= test_orient.js,
# null-safe + J summary). No new numerical constants (CALL_THETA stays 2).
D1  No harm: form >= 0.99 and share of patch actions answered within 0.05 of BASELINE in every phase, seed, condition.
D2  Waiting under scaffolding (criterion): SCAF-ADULT late share of calls made while waiting <= 0.05 in >= 4/5 seeds.
D3  It is learned as a configuration with "not waiting": at the end of A (SCAF-ADULT), >= 0.8 of the sedimented J -> m3
    edges contain r11 and none contains r10, in >= 4/5 seeds.
D4  Calling is not suppressed: SCAF-ADULT has >= 50 calls in the last 1000 steps of A and answers >= 0.5 of its
    phase-A calls, in >= 4/5 seeds.
D5  The partner matters: RESP-ADULT late share of calls made while waiting exceeds SCAF-ADULT's by >= 0.1 in >= 4/5 seeds.
D6  Recognition and quiet (test_config_orient.js, RESPONSIVE): calls in the last 500 steps of B <= 50 in >= 4/5 seeds,
    and the first call strictly after the first gesture of C within 3 steps in >= 3/5 seeds.
Not predicted, reported: number of J units grown; live vs replay; ABSENT babble.
