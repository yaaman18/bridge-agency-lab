# Predictions for S27 (discussion/specs/S27-body-gfp.md r1), frozen before any agent_gfp.jl run
Seeds 321-330 (never run), SF, arms std/swap (20 objects; the two arms of a seed are not independent), H 392, S17's contract.
Checks (not predictions; a failure refutes the implementation or the correspondence, not the reading):
- C1: Lean's `#eval w.nuFin` equals Julia's `nu_fin` on all 20 windows.
- C2: in every window with checkDC true, kappa (kept self edges) is a subset of nu_fin, and value_gfp(e) >= value_kappa(e) for every receptor e.
Predictions:
- GP1: kappa is a subset of nu_fin AND nu_fin contains at least one receptor -> motor edge, in >= 15 of the 20 windows (denominator 20, non-DC windows included; the inclusion is measured in every window).
- GP2: T_struct under the gfp value is a strict superset of T_struct under kappa in >= 10 of the 20 objects.
- GP3 (the tab of each built Agent is traceable in the generated file to the gfp T_struct silenced from update 1, recorded per object): an Agent value is built with `agentOfGfp` (DC, a value-differentiation witness on the gfp value, and checkValueNeeded with the gfp T_struct) for >= 10 of the 20 objects.
C1/C2 failures are reported as implementation or correspondence problems; GP1-GP3 shortfalls as missed predictions, separately.
