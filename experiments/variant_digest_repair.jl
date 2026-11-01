# Self-repair under the digestion reading (2026-10-29). The adopted test damaged a core unit with the
# sensors silenced and abundant resource; under the digestion variant nothing is confirmed without the
# world's answer, so that test cannot be passed by anything. Here the damage is the same (source silencing
# of one core unit u for smax * decay_period steps, then release, then `horizon` more steps), but in the
# world: the first survival schedule, sensors working. Constituents of u: its outgoing contingencies with
# confidence > 0 at the end of the undamaged run in the same schedule. Repaired: every constituent is back at
# confidence >= 1 at the end, and the system has form over the last alive_window steps. Required for every
# core unit; at least one core unit must have a constituent. Self-producing is required first.
@eval AgencySubstrate function self_repairing(s, p, pc, schedules)
    self_producing(s, p, pc, schedules) || return false
    sch = schedules[1]
    core = endogenous_core(s, pc, sch)
    isempty(core) && return false
    undamaged = last(run_trajectory(s, p, sch)).strength
    damage = p.smax * p.decay_period
    any_constituent = false
    for u in core
        constituents = [k for (k, (src, _, _)) in enumerate(s.edges) if src == u && undamaged[k] > 0]
        any_constituent |= !isempty(constituents)
        st = initial_state(s, p)
        traj = State[]
        for t in 1:(damage + p.horizon)
            step!(st, s, p, sch, t <= damage ? Set([u]) : Set{Int}())
            push!(traj, deepcopy(st))
        end
        form(traj[(end - p.alive_window + 1):end], s) || return false
        all(k -> st.strength[k] >= 1, constituents) || return false
    end
    any_constituent
end
