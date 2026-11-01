# Predictions for the digestion variant (variant_digest.jl, env_digest.jl), written 2026-10-29 before any run.
# "Form" = confident enacted cycle over the last alive_window (5) steps. Choice by the frequency variant.

D1  selfloop-pair-agent: L2 = true, L3 = true under this reading.
D2  static-agent: L2 = true, L3 = false (its confidence never changes, so it persists without activity).
D3  reflex, alternator, no-loop: L2 = false. (thermostat is not predicted: its resource sensor has no meaning
    without a resource; it is reported only.)
D4  In the 1000-step world, selfloop-pair-agent has form at >= 95% of steps, and m1 fires through stale
    contingencies within steps 601-650 (re-engaging patch 1 after its static season).
D5  Consumption drives switching: in season 1 the agent switches the patch it acts at >= 10 times; with
    CONSUME = false it switches < 3 times.
D6  Battery (start times as fragility.jl, 11 each): no silencing of any unit for 1/3/10/30 steps and no wipe
    leaves the agent without form at step 1000. "stasis k" (the world offers nothing for k steps): k = 30
    keeps form throughout (confidence lasts about 32 steps); k = 60 loses form at some step and regains it by 1000.
D7  Ablations after stasis 60: with EXPLORE = false form is not regained by step 1000; with DIGEST_GATE = false
    form is never lost (confirmation no longer needs the world, so the world is not needed).
D8  Sensor ablation: with both patch sensors silenced for the whole run, the agent has no form at step 1000.
