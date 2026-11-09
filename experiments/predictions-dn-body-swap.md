# Predictions for S2 (discussion/specs/S2-body-dn.md r2), frozen before dn_body_swap.jl is run

Runs: experiments/dn_body_swap.jl, seeds 1-10, arms :std and :swap raised as in S1 (old rule: contrast none, idle_first
false, core_gate false), then body_org's trials through variant_horizon.jl's LabBodyAgency and bridge-protocol's
AgencySubstrate.evaluate (unchanged), structure :constituents, horizons 294, 392, 588.

New (checks of the contract):
- DP1 (S2-1): each arm's BodyOrg raised/noise serialize to the same bytes as S1's procedure after step 800, 10/10.
- DP2 (S2-1 other fields, S2-2): every other BodyOrg field and the body start (world, pool, setup) are byte-equal across
  the arms, 10/10; the negative controls (one arm's w.C[1] changed; one arm's MCOST changed) are detected, the clean pair is not.
- DP5 (S2-7): re-evaluating an arm (rebuilt) and swapping the order of evaluation give equal results, 10/10.
Reproductions of items 70/74 (not new predictions):
- DP3: at all three horizons, :std chooses m2 in both choice schedules and :swap chooses m1 in both, 10/10.
- DP4: D (differentiated) is false for both arms, 10/10 at all three horizons; T is empty, so N is false by the guard
  (not tested), 10/10.

Falsification: if DP1, DP2 or DP5 fails for a seed, its D/N are not attributed to the history and the seed is excluded
(reported with the reason); if DP3 or DP4 fails, the records of items 70/74 and the current code disagree (reported).
