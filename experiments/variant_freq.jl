# Trial (not adopted), 2026-10-29: choice measured by frequency instead of by "active at some step".
# choice = the set of motors active at the largest number of steps of the window (the modal motors);
# empty when no motor is active. No threshold (P-05). Every criterion that reads choice
# (value_differentiated, value_tracking_units, core_enables_action) follows. Survival is unchanged.
@eval AgencySubstrate function choice(s, pc, sch, window; silenced=Set{Int}())
    traj = run_trajectory(s, pc, sch; silenced)
    cnt = Dict(m => count(t -> traj[t + 1].active[m], window) for m in keys(s.motors))
    best = maximum(values(cnt); init=0)
    best == 0 ? Set{Int}() : Set(m for (m, c) in cnt if c == best)
end
