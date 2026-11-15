# S55 (A0) predictions (r2 after the S-R; r1 is in freeze 0; frozen before any code is written or run; 2026-11-15). Spec: ../discussion/specs/S55-draw.md.

Arms DET, UNI, FIXP (weights 5 : 3 : 2 for the motors of patch 1, patch 2 and m0); world of item 155 at M = 2.5; laws L2
and L2+SF judged separately; pilot windows 670-673, evaluation windows 674-685 (n = 12). Nothing is known for these
windows or for any drawing arm. No claim of an adaptive effect is made from this stage.
- PA1 (pilot; the stage can be measured): for both laws and all three arms, alive at T0 + 2000 in at least 3 of 4 pilot
  windows, and at least 200 drawing steps (two or more candidates) after T0 in every pilot window. Low confidence: how
  often two or more candidates occur is not known. If PA1 fails for any one arm, none of the three arms of that law is
  run on the evaluation windows ("cannot be measured") and that is the reported result.
- PA2 (frequencies match the specified probabilities): for UNI and FIXP, per law, pooled over the evaluation windows,
  for every candidate set with at least 400 draws: the chi-square goodness-of-fit test against the specified
  probabilities does not reject at 1 % with the Holm correction over the candidate sets judged within that law and arm
  (the uncorrected p-values are listed beside as diagnostics), and every chosen share is within 0.05 of the specified
  one. Candidate sets with fewer than 400 draws are reported, not judged. No candidate set with 400
  draws = "undetectable" for that arm and law.
- PA3 (replay): every recorded choice is reproduced from the bit file and the recorded bit positions (100 %), and a
  second run with the same bit file is bit-identical at every step (gates D3; restated as a prediction for the
  evaluation windows).
- PA4 (the draw changes the life): for UNI and FIXP, in at least 10 of 12 evaluation windows the state differs from DET
  at T0 + 2000 (the drawing arms are not trivially equal to DET). "State at T0 + 2000" is the saved state of the run at
  that step whether alive or dead (a dead run keeps its last state); two runs that died at different steps count as
  different, two that died at the same step with the same last state count as equal.
- Reported without prediction: survival, body sizes, death steps, share of answered acts, agreement with DET's choice,
  number of drawing steps, share of rejected bit groups.
- Not claimed: that drawing helps or harms; anything about real radio bits, a predictor, traces, other worlds, or that
  the individual feels anything.
