# Predictions for the D6 horizon variant (experiments/variant_horizon.jl; frozen 2026-11-01 before the runs)

User 2026-11-01: D6 as recommended (keep the frozen 60 steps and show L2/L3 as not measurable there; a lab variant with a
horizon from the system's own time scales: 392 = 2 x 196, the body's starvation time without the circuit; 294 and 588
as sensitivity declared in advance; predictions frozen first). Then "じゃあ次はD6の作業をやってください".
AGENCY-001's criteria are called unchanged on body_org (adapter choices B1-B7 in the script's header). Seeds 1-10
(noise only). Horizons 60, 294, 392, 588. Two structure readings: :constituents (D1, L3 on the material constituents)
and :q (the circuit's confidences, reference only).

Known before: the body without the circuit dies at step 196 (seeds 1-3, item 66); body_org's ORG lives 10 000 steps
under the seasons (10/10, stage 42); in the app's being (audit A, 60 steps) the core was c1, c2, c3, the being was not
value-differentiated and the :q structure did not persist with the sensors silenced. Only a smoke test at horizon 16
with its output hidden was run (to see that the script runs).

- HP1 (by construction): H = 60: L2 false for 10/10 seeds (no body can starve within 60 steps, so the ablated column
  survives wherever the intact one does). Reported as "not measurable at this horizon", not as a result.
- HP2: H = 60, :constituents: L3 false for 10/10 (with every unit silenced the body still has constituents at step 60).
- HP3: H = 392, :constituents: with every unit silenced no constituent remains under any schedule (10/10).
- HP4: H = 392, :constituents: L3 true for 10/10 (the body fed without harvesting keeps constituents by its own binding).
- HP5: H = 392, :q: L3 false for 10/10 (without sensing the circuit does not act, nothing is confirmed, confidences
  dissipate), as in the app's being.
- HP6: H = 392: alive_somewhere true for 10/10 (the intact body_org survives at least one frozen schedule).
- HP7: H = 392: L2 false for 10/10. Expected reason (inference, not part of the prediction): not value-differentiated
  in the frozen choice window 5-15 (with yields 5 and 4 both patch receptors y>=3 are on).
- HP8: every seed's verdicts (L2, L3 :constituents) are the same at 294, 392 and 588.
- HP9 (implementation): L2 and its diagnostics are identical between the two structure readings.
- HP10 (implementation): Lean's checkSelfProducing and checkValueNeeded (formal/LabCircuit.lean) on the exported tables
  agree with the Julia verdicts (self_producing for both readings; value_needed where value-tracking units exist).
- HP11: the verdicts are the same for all 10 seeds at each horizon and reading.

Falsification of the variant's point: if at H = 392 the intact body_org dies under every schedule (HP6 fails), survival
cannot serve as the proxy for L2 in this system; if L3 :constituents differs between 294 / 392 / 588, the horizon still
decides the result.
