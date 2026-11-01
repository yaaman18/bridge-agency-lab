# Predictions for stage 28, candidate 1 (i): configural units grown on surprise, with shared credit
# (surprise.js = turn.js rev. 2 + J units recruited on S1/S2 + the configuration takes the credit from its elements).
# Written 2026-10-31 before any run of surprise.js with surprise=true. surprise=false reproduces results-scaffold.json
# and results-turn.json exactly (checked before this file). Harnesses: test_config.js (scaffold + J summaries),
# diag_scaffold.js, test_config_orient.js. No new numerical constants. Reference = turn.js rev. 2 (stage 25):
# SCAF-ADULT late share of calls made while waiting 0.110/0.099/0.146/0.144/0.100 (seeds 1-5), calls made while waiting
# right after a gesture 6/9/14/14/10, r9->m3 sediment 4/4/4/3/3, late calls 155/142/151/153/150, answer 0.69/0.67/0.56/0.65/0.58.
I1  No harm: form >= 0.99 and share of patch actions answered within 0.05 of BASELINE in every phase, seed, condition.
I2  Waiting improves (criterion): SCAF-ADULT late share of calls made while waiting is below the stage 25 value in
    >= 4/5 seeds, and <= 0.08 in >= 3/5 seeds.
I3  The residual is what improves: calls made while waiting right after a gesture (diag) fewer than stage 25 in >= 4/5.
I4  Growth stays bounded: <= 25 configural units at the end of phase A in every seed (SCAF-ADULT).
I5  The configuration takes over: J(r9+r11) -> m3 has sediment >= 1 at the end of A in >= 3/5 seeds, and r9 -> m3 has
    less sediment than in stage 25 in >= 3/5 seeds (SCAF-ADULT).
I6  Calling is not suppressed: SCAF-ADULT late calls >= 100 and phase-A answer share >= 0.55 in >= 4/5 seeds.
I7  Quiet and return (test_config_orient.js, RESPONSIVE): calls in the last 500 steps of B <= 50, and the first call
    strictly after the first gesture of C within 3 steps, in >= 4/5 seeds.
