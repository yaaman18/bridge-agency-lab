# Predictions for the DC audit with a state-dependent alpha (D4, item 69; frozen 2026-11-01 before the runs)

D4 revised again (user 2026-11-01, "推奨どおりでいい、D4から進めて"): alpha depends on the medium's state at the
occurrence (read by intervention on the world's rules, core/life.jl and core/circuit.jl):
- m1 reaches its declared features (r1, r3, r7, r8 of item 67) only in the world phase while y1 > 0 (an act on patch 1
  then takes a positive share, allocate: offer > 0, and R1 decreases); m2 likewise with y2 > 0.
- In the nursery and school phases the yields are scripted and no act changes them: m1, m2 reach nothing.
- m3 reaches r9 only while the partner is live (unchanged).
Everything else as in predictions-dc2.md (L = 32, kappa, the same 2000-step runs, the same partner script). The rules of
the circuit and the world are not changed; only the observer's alpha is. The previous (fixed) alpha is kept and reported
beside the new one for comparison.

Not blind: the fixed-alpha values are known (results-dc.json, item 67). Nothing has been run with the new alpha.

- DQ7 (follows from Lean `no_dc_when_gate_closed`, an implementation check): newborn, partner absent: no DC in the
  nursery and school phases (occurrences up to 800). Falsified if any.
- DQ8 (new): newborn, partner absent: the overall DC rate is lower than with the fixed alpha (21.0%). Falsified if not lower.
- DQ9 (new, the hypothesis of item 67): saved being v518, partner absent: the hSMC rate is higher than with the fixed
  alpha (0.1%). Falsified if not higher (then "the receptor of the empty patch blocks hSMC" is wrong).
- DQ10 (new, bolder): saved being v518, partner absent: DC at 10% of the occurrences or more. Falsified if below 10%.
- DQ11 (new): newborn, partner absent: the DC rate in the world phase (occurrences 801-2000) is at least the fixed-alpha
  value (1.3%). Falsified if lower.
- DQ12 (known form): the M4b check holds in every run (all living occurrences act).
- DQ13 (implementation): Lean's Window.checkDC agrees with Julia on every exported window (sh audit/dc_lean.sh).

Reported without prediction: the runs with the answering partner, and the saved being v528.
