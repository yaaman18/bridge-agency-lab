# Predictions for the depletion world, revision 2 (variant_sensor_ge.jl), written 2026-10-29 before the run.
# Same world (env_deplete.jl) and the same W0-W7 as predictions-world.md, re-registered unchanged:
W0  63/63 with labels-precision.toml.
W1  selfloop-pair-agent (EXPLORE on) alive at step 1000.
W2  EXPLORE off: dies after step 600.
W3  >= 10 switches of the harvested patch in steps 1-300.
W4  m1 fires through stale contingencies within steps 601-650.
W5  reflex and thermostat die in the patch-1 drought (steps 301-600).
W6  alternator survives 1000 steps.
W7  silencing a motor changes some patch sensor's firing rate for the agent (nonzero).
Added after seeing v1: thermostat died at step 116 in v1, before the drought; W5 for thermostat is kept as
registered (dies in 301-600) and will be reported as missed if it dies earlier again.
