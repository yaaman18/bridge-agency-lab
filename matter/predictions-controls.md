# Predictions for stages 40-41 (test_controls.js, summarize_controls.js), written 2026-10-31 after stage 39 and before
# any run of seeds 1-10. Exploratory before freezing (seed 99, 1000 steps, seen): with defaults test_controls.js
# reproduces test_neutral.js byte for byte; GATE=0: LEAN ba 0.050 (above all markers), RICH 0.007; MIX=50: lines 28
# (LEAN, shadow 2.5% 45) and 50 (RICH, 2.5% 66), counts 219 and 830. New constants: GATE=0 (stage 40), MIX=50 (stage 41).
# Stage 40, the division gate removed (any constituent with B >= THETA_DIV divides, whatever its activity):
G0  Conservation |error| < 1e-6 and persistence at every 500-step sample, all 20 runs.
G1  The selection on ba disappears: final ba above all 20 neutral markers in <= 3/10 seeds of each world.
G2  The birth side no longer favours high ba: Cb(ba) > 0 in <= 7/10 seeds of each world.
G3  The excess of ba over the marker median is smaller than with the gate (stage 39, same seed) in >= 8/10 seeds per world.
# Stage 41, the constituents mixed every 50 steps (gate 0.5 as in stage 39):
X0  Conservation and persistence, all 20 runs.
X1  Spatial structure protects lineages: final founder lineages fewer than in stage 39 (same seed) in >= 8/10 per world.
X2  Mixed lineages fall to (or below) well-mixed drift: final lineages <= the median of the run's 200 shadows in >= 7/10
    seeds of each world.
X3  Selection on ba persists under mixing: final ba above the median of the 20 marker means in >= 8/10 seeds per world.
