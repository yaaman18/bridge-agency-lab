# Predictions for S12 (discussion/specs/S12-body-clamp.md r2), frozen before any clamp.jl run

Objects: SF rule, seeds 51-60 (never run before), arms :std/:swap, 4 survival schedules, main run H 392, branch points t in 32:32:392,
window t+1..t+15. Z = both patches exchanged (schedule and pools). Written from the rule (two channels from one y), not from runs of these seeds.
A prediction whose denominator is 0 is "not evaluable" (neither held nor failed).
- CP1 (identity control): with both channels yoked to N, the act sequence and the end-of-window circuit state equal N's at every
  common-survivor branch point, in both series (at least one point compared).
- CP2 (series A): denominator = common-survivor points where the shift under (ii) is determined: the shift holds under (ii) (answer
  channel yoked, sense real) at >= 90% of them. Denominator = common-survivor points: D > 0 under (i) (sense yoked, answer real) at >= 50% of them.
- CP3 (series B, coupled receptors silenced in N and Z): denominator = common-survivor points where (o) shifts: the shift does not hold
  under (ii) at >= 90% of them. (This tests the dependence on the answer channel, not that the answer channel alone suffices.)
- CP4 (Q-B saturation): denominator = usable events of the one-step alpha check (as S9): the yield of m's patch read at t+2 is 5 in both C
  and Bm at >= 90% of them. (A failure refutes this 90% prediction for these objects; S9's own events need a separate check.)
- CP5 (Q-B near threshold NT): no mismatch on undeclared pairs at any usable NT event.
Q-C is described only. Falsification: CP1 false -> an unknown path or a synchronisation fault, every Q-A attribution is stopped.
