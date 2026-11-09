# Predictions for S19 (discussion/specs/S19-body-sedfade-cause.md r1), frozen before any sedfade_cause.jl run
New seeds 111-150 (never run), SF, arms :std/:swap, 4 survival schedules, points t in 64:32:384 where (3) of S18 holds.
Usable point = both N and F alive at t+400. Zero target points or zero usable points -> every prediction not evaluable.
- GC1 (replication): at every usable point, N has sgkept false at t+400.
- GC2 (attribution; the threshold is a guess without an established basis, codex P4): at more than half of the usable points, F has sgkept true at t+400. A shortfall is a miss even if weaken explains it.
- GC3 (route check, separate from GC2): over the F branches of all target points (alive or not), for the updates t+1..t+400 (the first intervened update included) up to death, every decrease of an E edge's sg is classified as weaken (none as sed_fade, none as other). Zero decreases -> not evaluable (not counted as a confirmed route).
- GC4 (acts): the median over usable points of the per-point difference (acts of m* in F) - (acts of m* in N) over the 400 updates is > 0; reported also per run.
- Control (not a prediction, must pass): with SEDFADE_OVERRIDE = nothing, the main runs and the N branches equal those without the override (same acts, same CState every update) on the first run.
