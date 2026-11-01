# Predictions for action selection (variant_select.jl, with :consolidate), written 2026-10-29 before any run.
# Labels: templates-digest.toml, re-derived under this rule before the run and found unchanged. Reasoning for
# the type the rule affects most: omnivore's two motors tie, so it keeps acting at patch 1 (never chooses):
# L2 false; kept where patch 1 answers: L3 true; its three-unit core repairs: L3R true. Others are unaffected
# in concept (each acts at one patch at a time already, or has no motors).
X1  templates-digest.toml: 36/36.
X2  World (env_digest_wta.jl, 1000 steps): selfloop-pair-agent, agent and triangle-agent keep form at
    >= 95% of steps; omnivore below 95% and below the agents.
X3  Random circuits (seed 20261009, 20,000): agents with direction <= 15.
X4  In the world, the agent's m1 fires through stale contingencies within steps 601-650.
X5  Fragility (silencing any unit of selfloop-pair-agent for 1/3/10/30 steps, 11 start times): no form at
    step 1000 in 0/11 for every perturbation.
