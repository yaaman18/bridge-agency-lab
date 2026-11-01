# Predictions for stage 44 (body_org.js KC, test_upkeep.js), written 2026-10-31 before any run with KC > 0. Measured first
# (mechanics, not outcome): the circuit keeps 16.6 contingencies on average (of 22) in the stage 42 run of seed 1; harvest
# 0.087 mu/step, so an upkeep of 16.6 x KC uses it up at KC ~ 0.005. New constant KC (grid 0.001-0.006); GREEDY pays for 4.
U0  Conservation |error| < 1e-6 in all runs.
U1  The organization's upkeep is paid in body: ORG mean body falls strictly with KC over 0, 0.001, 0.002, 0.004 in >= 9/10 seeds.
U2  Above the harvest the organization kills its body: ORG dies at KC 0.006 in >= 9/10 seeds; alive at KC 0.001 in 10/10.
U3  In the unperturbed world upkeep widens the fixed rule's lead (it keeps 4 contingencies, the circuit ~17): relative lead
    (GREEDY - ORG) / ORG larger at KC 0.002 than at KC 0 in >= 9/10 seeds.
U4  Adaptability still pays where the world changes: at KC 0.002 with receptors crossed at 5000, ORG alive at 10000 in
    >= 8/10 seeds and GREEDY dies (10/10, deterministic).
