# Predictions for S28 (discussion/specs/S28-body-yoke12.md r1), frozen before any yoke12.jl run
Seeds 331-340 (never run), SF, arms std/swap, 4 survival schedules, points t in 64:32:352, W = 32, both channels yoked, H = 392.
A point whose N dies within W is excluded for all conditions (reason recorded). Usable point for Y1 / Y2 = not excluded (provider alive at t and its N alive through W / Y2 sequence differs from N's) and N and the branch alive at t+W.
Pooled over seeds, arms, schedules and t (also reported per arm and schedule). Zero usable points for a condition -> not evaluable. YP2 and YP3 are conditional on survival to t+W.
Check (not a prediction): C0 Y0 equals N bit for bit (every update's acting set and CState) at every point where N survives W. A C0 failure is a failed check, and YP1-YP3 are not adopted until it is resolved.
- YP1: the act divergence (updates in W whose patch-acting set differs from N's) is > 0 at >= 50% of the usable Y1 points, and at >= 50% of the usable Y2 points.
- YP2: the body size at t+W is smaller than N's at more than half of the usable Y1 points (a guess, no established basis).
- YP3: survival at t+H under Y1 and Y2 is each >= 90% of the usable points (the yoke is short and the real input resumes).
