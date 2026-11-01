# Predictions for stage 45 (test_controls2.js BINDC, summarize_bind.js), written 2026-10-31 before any run with BINDC.
# Checked first (mechanics): fmatter.js/fevo.js with the new option absent stay bit-identical (check_fast.js), and
# test_controls2.js without BINDC reproduces the GATE=0 seed-99 smoke run of stage 40. New constant BINDC = 0.7 (the
# realised mean activity of stage 39 was 0.64-0.75). Hypothesis from stage 40: high activity is selected because it
# raises binding (BIND x a x A) and so reaches THETA_DIV sooner. With binding at 0.7 for all, activity only costs.
H0  Conservation |error| < 1e-6 and persistence, all 40 runs.
H1  GATE 0: the selection for high ba disappears: ba above all 20 markers in <= 2/10 seeds per world.
H2  GATE 0: it reverses: final ba below the median of the marker means in >= 8/10 seeds per world.
H3  GATE 0.5: ba below the marker median in >= 6/10 seeds per world (downward, held back by the gate).
H4  Final realised activity lower than stage 39 (same seed) in >= 8/10 seeds per world, in both GATE conditions.
