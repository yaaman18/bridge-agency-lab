# Predictions for item 76, step 1 (frozen 2026-11-02 before the runs)

User 2026-11-02: "じゃあその順番でやってみて" (item 75's next steps in order: 1. survival schedules with both patches
positive, as a lab variant, predictions first; 2. wiring through the core, after seeing 1).

Variant (experiments/variant_horizon.jl LOW=4; adoption is the user's): each frozen survival schedule with its empty
patch given 4 (p1-high [5,4], p2-high [4,5], p1-then-p2 [5,4] -> [4,5], p2-then-p1 [4,5] -> [5,4], switch_at 20 frozen);
the choice schedules, window and every number of the substrate unchanged. body_org with bin3 + idle_first (item 75).
Measured before (design, not a trial): with only one patch yielding, the body lives 392 steps on a yield of 1 already
(end body 4 sites; yield 5: 21-23 sites; yield 0: death at step 194), seed 1.

- SV1: H = 294, 392, 588, both readings: value-differentiated true with value-tracking units r2, r8 (the choice
  schedules are unchanged), 10/10.
- SV2: ValueNeeded false and L2 false, 10/10 at each horizon (the poorer patch sustains the body: margin).
- SV3 (eval_surv.jl, H = 392): with r2, r8 silenced, in p2-high-4 ([4,5]) m1 is on at more than half of the steps
  (the act moves to the poorer patch), for 10/10 seeds; intact, m2 is on at more than half.
- SV4: in p2-high-4 the end body with r2, r8 silenced is smaller than intact, for 10/10 seeds (value tracking pays in
  the amount of body, not in survival).
- SV5: the intact body_org survives all 4 variant schedules (alive_somewhere true), 10/10.

Reported without prediction: LOW = 1, the other schedules' body sizes, L3.

Falsification: if SV2 fails (some seed needs r2, r8 to survive), the margin reading of item 75 is refuted; if SV3 fails,
r2, r8 do not carry the patch-2 choice in survival as they do in the choice window; if SV4 fails, value tracking does not
even pay in the amount of body under this variant.
