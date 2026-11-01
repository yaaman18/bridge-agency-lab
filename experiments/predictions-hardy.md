# Predictions for the hardiness trial, written 2026-10-29 before any run. Agent: selfloop-pair-agent,
# depletion world (env_deplete.jl), fragility battery of fragility.jl (11 start times per perturbation).
# Baseline (fragility-before.out, rev. 2 sensors, rmax 30): famine 10 kills 11/11, silence m1 10 kills 6/11.

H1  Sensor change alone (rmax 30): famine 10 kills 0/11 (in a famine only the core, 2 per step, burns).
    famine 30 still kills (30 reserve / 2 per step = 15 steps).
H2  rmax 100 with the sensor change: famine 30 kills 0/11. silence m1 30 still kills some (the agent keeps
    its futile motor running, about 4 per step, 120 > 100).
H3  rmax 200 with the sensor change: no perturbation in the battery kills.
H4  Frozen templates (63 labels, with labels-precision.toml) agree at every rmax tried and with the sensor
    change (resource0 = 10 is unchanged, so survival over the 60-step horizon is decided as before).
H5  The agent still lives 1000 steps unperturbed in the world, at every setting.
