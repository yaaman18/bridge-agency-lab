# Predictions for the DC audit (frozen 2026-10-31 before any run; item 66 of README)

Setting: the organization layer's circuit (D1), core/dc.jl (= Window.ElemDC of formal/LabCircuit.lean, D2-D4 as decided).
Runs: (i) the saved being of the app (audit/in/state-v518.json) lived 2000 steps by core/life.jl, no gestures (partner
absent); (ii) a newborn lived 2000 steps (nursery 400, school 400, world). Occurrences from step 32 on (full windows).

- DP1 (i): hBound holds at >= 0.95 of the occurrences (c1->m1 is kept). Falsified if < 0.95.
- DP2 (i): hAct holds at >= 0.90. Falsified if < 0.90.
- DP3 (i): hSMC holds at <= 0.50 (r10/r11 are coupled only to m3, which an on coupled receptor rarely drives through a
  kept contingency). Falsified if > 0.50.
- DP4 (i): hSelf holds at <= 0.50 (reproductions with acts not enabled by the self do not count; c3->m3 cannot be
  re-produced without a partner). Falsified if > 0.50.
- DP5 (i): DC (all four) holds at <= 0.30. Falsified if > 0.30.
- DP6 (i) and (ii): the M4b check (every living occurrence acts) holds. Falsified if a living occurrence has no act.
- DP7 (ii): the DC rate in the nursery (occurrences 32-400) is lower than in the world phase (801-2000). Falsified if
  not lower.
