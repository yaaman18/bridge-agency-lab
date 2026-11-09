# Predictions for S1 (discussion/specs/S1-body-history.md, R-BODY-1), frozen before h_body_swap.jl is run

Runs: experiments/h_body_swap.jl, seeds 1-10, arms :std and :swap (experiments/curricula.jl), the old rule (contrast none,
idle_first false, other optional rules off), raising outside the body (as eval_body_bin3.jl `raise`).

- HP1 (S1-2): the births B = (b, c, nz) of the two arms serialize to identical bytes, 10/10.
- HP2 (S1-4): the scripts have equal length 800; they differ at every nursery step 1-400 and at no school step 401-800, 10/10.
- HP3 (S1-5): running :std twice with the same seed gives equal school counts, equal confident inputs, and identical
  serialized states after step 800, 10/10.
- HP4 (known result of item 74 SQ1, a reproduction, not a new prediction): :swap gives m1 >= 390 of the 400 school steps and
  :std gives m2 >= 390, 10/10.
- HP5 (S1-1b): no mutable object (nested included) is shared between the two arms, 10/10.

Falsification: if HP1, HP3 or HP5 fails for a seed, that seed is excluded from the history comparison and item 74 SQ1 is not
read as support of H for it; if HP1 or HP3 fails at all, the raising is not reproducible as implemented or B misses state,
and the reading "SQ1 supports H" is withdrawn until explained. If HP4 fails, the record of item 74 and the current code
disagree (reported as a provenance problem).
