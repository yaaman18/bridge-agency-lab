# Predictions for the depletion world (env_deplete.jl), written 2026-10-29 before any run.
# Substrate: precision variant (variant_precision.jl), params of templates.toml, 1000 steps.

W0  With labels-precision.toml, the frozen templates agree 63/63 under the precision variant.
W1  selfloop-pair-agent with epistemic sampling (EXPLORE on) is alive at step 1000.
W2  The same agent with EXPLORE off dies after step 600 (its patch-1 contingencies go stale in the patch-1
    drought and cannot be re-engaged when patch 1 returns).
W3  In season 1 (steps 1-300) the agent switches the harvested patch at least 10 times, driven by its own
    depletion of the patch it is on (no switch in the yields is scheduled by the environment).
W4  Firing through stale contingencies (all in-edges at confidence 0) occurs for m1 within steps 601-650.
W5  reflex and thermostat (patch 1 only) die in the patch-1 drought (steps 301-600).
W6  alternator (harvests both in turn, no sensing) survives all 1000 steps: survival alone does not
    discriminate agency here either.
W7  Sensitivity of sensing to action (P-04 source silencing of one motor for the whole run, season 1 only):
    for the agent, silencing m1 changes the firing rate of s1 or s2 (nonzero), i.e. the agent's sensing
    depends on its own action in this world. (In the earlier worlds it was zero by construction.)
