# Predictions for S4 (discussion/specs/S4-body-dn-sf.md r1), frozen before any RULE=sf run

Rule "sf" = current (bin3 + idle_first + core gate) + sed_fade, trial upkeep KC_trial 0.0015 (raising has no upkeep).
Same contract as S1-S3. Seeds 21-30 (verification; seeds 1-20 selected KC 0.0015 in item 86). Horizons 294, 392, 588.
- FP1 (new): contract checks pass for 30/30 (seed, H); negative controls detected; RULE=old and RULE=current outputs
  reproduce their files byte for byte.
- FP2 (new, item 86's falsification test): :std, at each H, >= 8/10 seeds have D true and N tested true.
- FP3 (new): :swap, at each H, >= 7/10 seeds have D true and N tested true.
- FP4 (new): at each H, at least 1 seed where the arms differ in choices, D, T or N (support of H).
- FP5 (new): at each H, at least 1 seed that is an example of H and D and N (support of H, and both arms D and N).
Falsification: FP2 below 8/10 at some H refutes the stability of KC 0.0015 (item 86). FP5 zero at every H: no H and D
and N under the same contract in this line either.
