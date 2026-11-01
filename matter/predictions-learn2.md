# Predictions for stage 49 (memory/turn_sed.js "learn2", test_learn2.js), written 2026-10-31 before any run of learn2.
# Diagnosis first (post hoc, stage 48 "learn", world seed 3, reported): m1 had lost all receptor contingencies, their
# contrasts were 0.00 (patch 1 stayed full, digestion 5 with the receptor on or off), m1 no longer acted and its
# statistics could not change; the circuit stood idle at (y1, y2) = (5, 0) on 786 steps. Checked: turn_sed.js without
# the option still equals turn.js (108000/108000), and "learn" still gives stage 48's verdicts. New constant FORGET = 100.
L0  Conservation |error| < 1e-6 in all runs.
L1  LEARN2 alive at 10000 in >= 9/10 worlds.
L2  The missed harvest is gone: LEARN2 acts on >= 90% of the steps alive and harvests >= 0.08 mu per step in >= 8/10.
L3  LEARN2 does as well as removing the receptors by hand: mean body >= NR mean body - 1 in >= 7/10.
L4  LEARN2 adapts: receptors crossed at 5800, alive at 10000 in >= 7/10.
L5  LEARN2 keeps fewer contingencies per step alive than OLD in >= 9/10.
L6  LEARN2 mean body larger than LEARN (stage 48 rule) in >= 8/10.
