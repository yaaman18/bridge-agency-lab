# Predictions for item 86: the upkeep in the trials that makes L2 true most often (frozen 2026-11-03 before the runs)

User 2026-11-03: "L2 の真を安定させる試行実験を繰り返して最適な値を探して" (the user allows changing the upkeep value for
this search; the rules are not changed).

Knob: KCTRIAL, the upkeep per kept contingency during the AGENCY-001 trials only (variant_horizon.jl). It does not change
the raised circuit (item 85 KQ5). Item 85: KCTRIAL 0 gives L2 false everywhere; item 84 (0.002): 5 of 30 per reading.
Families (L2's rule bin3 + idle_first + core gate, criteria unchanged, horizons 294 392 588, seeds 1-10, both readings):
  G  = raised with the body (GROW=1, raising KC 0.002) + sed_fade (differentiated seeds 2 3 5 6 7 8 9)
  S  = the scripted raising of L2's system (GROW=0; differentiated 10/10 in items 77/84), KCTRIAL now also applied there
  SF = S + sed_fade
Grid: KCTRIAL = 0.0005 0.001 0.0015 0.002 0.0025 0.003 0.004 (G 0.002 repeated from item 84).
Score = runs with L2 true out of 30 per reading.

- WQ1: with KCTRIAL unset, the scripted raising reproduces results-horizon-gate.json (L2 false everywhere).
- WQ2: every family has an inside maximum: the score at 0.0005 and at 0.004 is lower than its best value.
- WQ3: G's best score >= 10/30 in the constituents reading (better than item 84's 5/30).
- WQ4: S's best score >= G's best score (S differentiates in 10/10 seeds).
- WQ5: the best KCTRIAL of G lies in 0.0015-0.0025.
- WQ6: at 0.004, the runs with a schedule lost even with the tracking intact are >= 15/30 in every family.

The search then refines around each family's best value (step 0.00025) and validates the chosen value on seeds 11-20
with predictions frozen separately before those runs.
