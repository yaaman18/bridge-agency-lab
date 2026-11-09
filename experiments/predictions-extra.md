# Predictions for item 78 B: more kinds of patch receptors (frozen 2026-11-02 before the runs)

User 2026-11-02: "おすすめで実装していって" (B after A). Written after A's results (predictions-worldvar.md: 5/7; the
"richer" share failed as a measure, because the seen yields are the pools the body lowers by its own harvest; the mean
body size is used here instead).

Change (lab option, default off, app unchanged): six more patch receptors for body_org's circuit (core/circuit.jl
EXTRA_FEATURES 12-17: y1>=1, y2>=1, y1>=4, y2>=4, y1>=y2+2, y2>=y1+2, as r9-r14, each with a contingency to m1 and m2 of
confidence 0; the reversal crosses them pairwise like the others). The learning rule is unchanged (no Lean statement is
needed: the Lean Net and the DC/CoreGate statements are for any wiring). L2's rule (bin3 + idle_first + core gate).
The waiting receptors' recomputation now names their slots (10-11) instead of "slot >= 10" (same for every existing
circuit).

- WB1: with the new option unset, sh core/check/run.sh is identical everywhere.
- WB2: at the end of the raising, each motor has at least one confident input from a new receptor (m1 from y1>=1,
  y1>=4 or y1>=y2+2; m2 from the mirrored ones), for >= 8/10 seeds.
- WB3: at the end of the raising, the noise (r5) and clock (r6) receptors have no confident input to a motor, 10/10.
- WB4: H = 294, 392, 588, both readings: value-differentiated true, core_enables_action true, ValueNeeded false,
  L2 false, 10/10.
- WB5: H = 392, :constituents: L3 true, alive_somewhere true, 10/10.
- WB6: the three worlds of A (seasons, held-out, random), 10 000 steps: L2's rule with the new receptors survives 10/10
  in each.
- WB7: the mean body size of L2's rule with the new receptors is at least that without them in >= 2 of the 3 worlds.

Reported without prediction: the value-tracking units found, the "richer" share, the stage 42 rule with the new
receptors.

Falsification: if WB3 fails, the contrast rule does not keep chance receptors out once the receptors are many; if WB6
fails, more receptors cost survival; if WB7 fails in all three worlds, the new kinds of input do not pay in the body.
