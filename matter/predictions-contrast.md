# Predictions for stage 48 (memory/turn_sed.js, body_org.js CONTRAST, test_contrast.js), written 2026-10-31 before any run
# with CONTRAST. Checked first: turn_sed.js without the option = turn.js (check_turn_sed.js, 108000/108000 steps);
# body_org.js still reproduces stages 43 and 47 (verdict lines). New constants: ALPHA = 0.05, THETA_C = 0.5.
# Reasoning before the run: gating only the sediment ("sed") leaves the confidence of chance contingencies, which are
# confirmed whenever they co-occur with an answered act (99% of acts are answered), so they stay kept and paid for.
S0  Conservation |error| < 1e-6 in all runs.
S1  The old rule with noise and clock (no capacity, raised on the body) dies in >= 8/10 worlds (stage 46 across phases).
S2  Gating only the sediment is not enough: SED dies in >= 6/10.
S3  Gating the learning by contrast keeps the body: LEARN alive at 10000 in >= 8/10.
S4  LEARN keeps fewer contingencies per step alive than OLD in 10/10.
S5  LEARN still adapts: receptors crossed at 5800, alive at 10000 in >= 7/10.
S6  LEARN does as well as removing the receptors by hand: mean body >= NR mean body - 1 in >= 7/10.
