# Predictions for stage 29: three treatments of orienting/habituation for configural units (surprise3.js, jorient a/b/c),
# written 2026-10-31 before any run with jorient set. jorient unset reproduces results-surprise-scaffold.json and
# results-surprise-orient.json exactly (checked before this file). Harnesses: test_config.js, diag_scaffold.js,
# test_config_orient.js. Stage 25 reference (SCAF-ADULT late share of calls made while waiting): 0.110/0.099/0.146/0.144/0.100.
# Stage 28 (no treatment): 0.465/0.385/0.424/0.506/0.212; J(r5+r6) drove 37-44 calls made while waiting.
Q1  No harm (a, b, c): form >= 0.99 and share of patch actions answered within 0.05 of BASELINE everywhere.
Q2  The noise+clock configuration is silenced (a, b, c): J(r5+r6) drives <= 5 of the calls made while waiting in the
    last 1000 steps of A (diag) in >= 4/5 seeds.
Q3a (a) Configurations are rarely tried, so the circuit behaves like stage 25: late share within 0.05 of stage 25 in
    >= 4/5 seeds, and J(r9+r11) -> m3 sediment 0 in >= 3/5 seeds.
Q3b (b) Waiting improves on stage 25: late share below stage 25 in >= 4/5 seeds and <= 0.08 in >= 3/5;
    J(r9+r11) -> m3 sediment >= 1 in >= 4/5 seeds.
Q3c (c) Waiting improves on stage 28 but not as much as b: late share below stage 28 in >= 4/5 seeds, and above b's in
    >= 3/5 seeds.
Q4  Quiet when the partner leaves (b, c; test_config_orient.js RESPONSIVE): calls in the last 500 steps of B <= 50 in
    >= 4/5 seeds.
Q5  Calling is not suppressed (a, b, c): SCAF-ADULT late calls >= 100 in >= 4/5 seeds.
