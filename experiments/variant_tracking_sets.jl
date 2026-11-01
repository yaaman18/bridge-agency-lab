# Value-tracking by minimal sets (2026-10-29, user decision: "silence sets in increasing size").
# The adopted criterion silences one unit at a time; a unit is value-tracking when its silencing changes the
# motor choice in exactly one of the two choice schedules. Redundant sensing (two sensors per patch, either
# suffices) is invisible to it. Here: among the units outside the endogenous core (core units are not
# ablated as value-tracking, user decision of 2026-10-24), every set S whose silencing changes the choice in
# exactly one schedule, and that contains no smaller such set, is a minimal value-tracking set. Sets are
# tried in increasing size up to all non-core units (no size bound is fixed: P-05). T = union of the
# minimal sets. Everything else in `evaluate` is unchanged.
using Combinatorics: combinations
@eval AgencySubstrate function minimal_tracking_sets(s, pc, c, window, core)
    value_differentiated(s, pc, c, window) || return Vector{Vector{Int}}()
    base = [choice(s, pc, x, window) for x in c]
    cand = [u for u in 1:nunits(s) if !(u in core)]
    found = Vector{Vector{Int}}()
    for k in 1:length(cand), S in Main.combinations(cand, k)
        any(F -> issubset(F, S), found) && continue
        count(i -> choice(s, pc, c[i], window; silenced=Set{Int}(S)) != base[i], 1:2) == 1 && push!(found, S)
    end
    found
end
@eval AgencySubstrate function evaluate(s::Substrate, setup)
    p, pc, c, w, surv = setup.params, setup.choice_params, setup.choice, setup.choice_window, setup.survival
    core = endogenous_core(s, pc, surv[1])
    sets = minimal_tracking_sets(s, pc, c, w, core)
    T = sort!(unique(vcat(Int[], sets...)))
    alive_somewhere = any(x -> survives(s, p, x), surv)
    differentiated = value_differentiated(s, pc, c, w)
    needed = value_needed(s, p, surv, T)
    hinge = core_enables_action(s, pc, c, w, core)
    (; agency=!isempty(core) && hinge && alive_somewhere && differentiated && needed,
       self_producing=self_producing(s, p, pc, surv),
       self_repairing=self_repairing(s, p, pc, surv),
       core=[s.names[u] for u in core], core_enables_action=hinge,
       alive_somewhere, differentiated, value_needed=needed,
       value_tracking=[s.names[u] for u in T],
       tracking_sets=[[s.names[u] for u in S] for S in sets],
       choices=Dict(x.name => sort!([s.names[m] for m in choice(s, pc, x, w)]) for x in c))
end
