# Predictions for S3 (discussion/specs/S3-body-dn-current.md r1), frozen before any current-rule run of dn_body_swap.jl

Rule "current" = bin3 + idle_first + core gate (items 75, 77). Same contract as S1/S2; seeds 1-10; horizons 294, 392, 588.
- EP1 (new): the contract checks (S2-1, S2-2, S2-3b, S2-7) pass for 30/30 (seed, H); the negative controls are detected.
- EP2 (reproduction of results-horizon-gate.json): :std at each H, 10/10: c1-better -> m1, c2-better -> m2, D true,
  T = {r2, r8}, N tested and false.
- EP3 (new): :swap at each H, >= 9/10: c1-better -> m1, c2-better -> m2, D true; where T is not empty, N tested and false.
- EP4 (new): at each H, >= 9/10 seeds have the same D and the same N category (guard / tested_false / tested_true) in both arms.
- EP5 (new): RULE=old reproduces results-dn-body-swap.json byte for byte (sha256 81f617be...); Lean's checks agree with
  Julia on every trial table of the :swap arm under the current rule (horizon_lean.jl).
Falsification: EP1 false -> those seeds excluded. EP3 or EP4 false -> the raising history changes D/N under the current
rule too; reported as a miss and examined as a candidate for H and D and N.
