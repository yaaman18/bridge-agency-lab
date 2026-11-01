# Predictions for the precision variant (variant_precision.jl), written 2026-10-29 before any run.
# Choice is measured with the frequency variant (variant_freq.jl) unless "frozen choice" is stated.
# Held-out envs: flip7, flip13, rand1-5, fast-then-slow, const-p1 (horizon 200, as eval_adapt2.jl).

V1  All 21 frozen templates (63 labels: L2, L3 read as confidence, L3R) agree under the precision variant.
V2  selfloop-pair-agent (no rehearsal): survives all 9 held-out envs; dies in all with patch sensors silenced;
    still differentiated (behavioural test from the aged state) wherever it survives.
V3  Ablation (EXPLORE = false) reproduces the earlier result: selfloop-pair-agent dies in rand1-5 and fast-then-slow.
V4  The frozen `agent` template behaves like selfloop-pair-agent (V2). repairing-agent still dies in the
    switching envs (its budget is net 0; precision does not fix economics).
V5  selfloop-pair-agent is L2 = true also under the frozen (set-based) choice: no rehearsal enters the window.
V6  Poor-motor share of selfloop-pair-agent in const-p1 stays at 0.0 (no rehearsal tax).
V7  Random circuits (seed 20261009, 20,000): number robust in the 7 held-out envs AND behaviourally still
    differentiated after 200 steps rises above the 1 of the adopted dynamics.
V8  Controls stay non-agents: reflex, thermostat, alternator, no-loop have L2 = false.
