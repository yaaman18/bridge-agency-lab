# Predictions for item 76, step 2: the core gate (frozen 2026-11-02 before the runs)

User 2026-11-02: "じゃあその順番でやってみて" (step 2 after step 1: wiring through the core). Written after step 1's
results (predictions-surv.md, 3/5).

Rule (opt-in, core/circuit.jl step!(...; core_gate = true); default off, app unchanged): a patch motor comes on only if
its input reaches the threshold and some contingency from a core unit drove it this step. Not removing the direct
receptor->motor contingencies: then each motor would have one core input (c1->m1, c2->m2) and never reach its threshold
of 2 (by construction), and the core units c1, c2 keep each other on whatever is sensed, so they carry no choice.
Lean first (formal/LabCircuit.lean CoreGate): gate_le (the gate never adds an act), off_when_core_silenced (with every
core unit silenced no gated motor comes on). No number changed. body_org with bin3 + idle_first (item 75), frozen
schedules (and LOW=4 of step 1, reported).

- GQ1: with core_gate off, sh core/check/run.sh is identical everywhere.
- GQ2 (Lean's off_when_core_silenced, in Julia): with the core silenced, no patch motor is ever on in the choice runs,
  10/10 seeds.
- GQ3: H = 294, 392, 588, both readings: core_enables_action true, 10/10.
- GQ4: value-differentiated true with value-tracking units r2, r8, 10/10 (c1, c2 stay on, so the gate is open and the
  receptor contingencies decide as before).
- GQ5: L2 false, 10/10 at each horizon (ValueNeeded false, as in items 75 and 76 step 1).
- GQ6: H = 392, :constituents: L3 true, alive_somewhere true, 10/10.
- GQ7: body_org ORG 10 000 steps with bin3 + idle_first + the gate survives 10/10.
- GQ8: in the raising's school the winner still switches at least once, 10/10.

Reported without prediction: LOW=4 with the gate, the number of school switches.

Falsification: if GQ3 fails, silencing the core still leaves the choice of some schedule unchanged, so the gate does not
make the action pass through the core as AGENCY-001 reads it; if GQ4 fails, routing the act through the core costs the
value differentiation.
