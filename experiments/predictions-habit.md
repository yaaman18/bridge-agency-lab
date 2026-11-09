# Predictions for S13 (discussion/specs/S13-body-habit.md r1), frozen before any habit.jl run

New seeds 61-70 (never run): SF rule, arms :std/:swap, 4 survival schedules, main run H 392, points t in 64:32:384, branches to t+400.
- RB1: among the points where R3-b(t) is determined, R3-b holds at <= 5% (if no point is determined, not evaluable).
- RB2: in every X branch alive through t+32, the q of every edge of E is 0 after the update t+32 (L2, with m* silenced no edge into m* is confirmed).
Reproduction check on seen objects (frozen separately from the new-seed predictions):
- RB3: seed 35 :swap p2-high t=64 and seed 37 :swap p2-high t=64: (3) holds at both.
Everything else (the sg necessity G, the q-independence of all inputs, the :std arms) is described.
