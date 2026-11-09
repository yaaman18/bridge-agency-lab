# Predictions for item 79: seen both before growing (frozen 2026-11-02 before the runs)

User 2026-11-02: "じゃあ1の規則変更を試してみて" (item 78's option 1: change bin3 so that a contingency does not grow
before it has been seen both ways, and see whether the circuit then learns with more receptors).

Rule (opt-in, core/circuit.jl step!(...; seen_both = true); default off, app unchanged): under bin3, a receptor->motor
contingency whose contrast is undefined (no answer rate yet with the receptor on, or none with it off, since its
statistics were last emptied) no longer passes; it grows only when seen both ways and its contrast exceeds THETA_B. It
still drives as before (stale / orienting), so trying is unchanged; only growing changes. No number is changed.
Lean first (formal/LabCircuit.lean SeenBoth): new_le_old, agree_when_seen, always_on_never_passes. body_org with L2's
rule (bin3 + idle_first + core gate), raising seeds 1-10, with and without the extra receptors (item 78 B).

- SB1: with seen_both off, sh core/check/run.sh is identical everywhere.
- SB2 (Lean's gate, in Julia): with seen_both on, no receptor->motor contingency grows at a step where its contrast is
  undefined, in every raising (both receptor sets, 10 seeds). (With it off such growth happens: reported.)
- SB3: extra receptors + seen_both: at the end of the raising m1 has a confident input from a receptor that favours
  patch 1 (r1 y1>=3, r7 y1>y2, y1>=4 or y1>=y2+2) and m2 one that favours patch 2 (mirrored), for >= 8/10 seeds.
- SB4: extra receptors + seen_both: H = 294, 392, 588, both readings: value-differentiated true, 10/10.
- SB5: base receptors + seen_both: value-differentiated true, 10/10 at each horizon (the change does not cost what bin3
  learned without it).
- SB6: L2 false in every run (ValueNeeded false, item 77); core_enables_action true.
- SB7: extra receptors + seen_both, the three worlds of item 78 A: survives 10/10 in each.
- SB8: extra receptors + seen_both: the mean body size is at least that of extra receptors without the change (item 78
  B) in >= 2 of the 3 worlds.

Reported without prediction: base + seen_both in the worlds, the value-tracking units, L3.

Falsification: if SB3 and SB4 fail, the reading of item 78 (an undefined contrast passing lets always-on receptors push
out the ones that track the richer patch) is refuted; if SB5 fails, the change costs the value differentiation bin3 had.
