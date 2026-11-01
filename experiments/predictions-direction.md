# Predictions for direction + capacity (variant_direction.jl, env_digest_cap.jl), written 2026-10-29 before any run.
# Readings loaded: frequency choice, digestion, digestion repair, minimal tracking sets, direction.
R1  templates-digest.toml: 36/36 (every labelled agent is directed; no control becomes an agent).
R2  Random circuits (seed 20261009, 20,000): agents with direction <= 20, and every one of them follows the
    better patch (choice in c1-better contains m1's patch and not only patch 2, and symmetrically).
R3  Falsification check of the capacity (as stated to the user): among the 182 agents without direction, the
    share that is directed is higher when val is capped (capacity) than when val is the uncapped sum
    (15/182 post hoc). If it is not higher, the capacity does not give choice its meaning.
R4  World (env_digest_cap.jl, 1000 steps): selfloop-pair-agent keeps form at >= 95% of steps; omnivore's form
    count is lower than the agent's.
