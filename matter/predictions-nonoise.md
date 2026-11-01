# Predictions for stage 47 (body_org.js DROPR/PHASE, test_nonoise.js), written 2026-10-31 before any run. Checked first:
# body_org.js with defaults still reproduces stages 43 and 46 (their verdict lines). Hypothesis from stage 46: what fills
# the capacity matters; the sediment of chance contingencies from noise (r5) and clock (r6) takes the capacity and the
# patch contingencies are lost first. New: the seasons' phase varies by seed (PHASE = (seed - 1) x 100), because without
# r5 the circuit has no randomness; both circuits (with and without r5/r6) meet the same worlds.
N0  Conservation |error| < 1e-6 in all runs.
N1  Without noise/clock contingencies the grown circuit keeps its body: GROWNR alive at 10000 in >= 8/10, while GROW (with
    them) is alive in <= 3/10 of the same worlds.
N2  The same for the pre-raised circuit with capacity: PRECAPNR alive in >= 8/10.
N3  Fewer contingencies are lost per step alive without noise/clock (GROWNR < GROW) in >= 8/10.
N4  The grown circuit without noise/clock still adapts: receptors crossed at 5800, alive at 10000 in >= 7/10.
N5  The capacity stays necessary: without it (BODYNR) the body dies in >= 8/10.
