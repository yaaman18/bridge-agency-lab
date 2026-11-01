# Trial (not adopted), 2026-10-29. User decisions of 2026-10-29: (1) the precariousness of L3 is read as
# the dissipation of confidence, not the loss of structure; (2) borrow from active inference only the
# epistemic part (no preferences), applied to the system's own sensorimotor contingencies.
#
# Reading of the substrate under this variant:
# * An edge src -> dst is a contingency the system holds ("when src fires, dst fires"). It is never
#   deleted: absence of evidence is not evidence of absence.
# * `strength` is reinterpreted as the confidence (precision) of that contingency. Its dynamics are the
#   adopted ones unchanged: confirmed (src sent and dst fired) -> +1 up to smax, paying grow_cost;
#   not confirmed at a tick (every decay_period steps) -> -1. Confidence dissipates without enactment.
# * Precision as gain: an edge transmits only while its confidence is at least 1 (as adopted).
# * Epistemic sampling (the only addition): a non-sensor unit all of whose incoming contingencies have
#   lost all confidence attends to them anyway, i.e. its stale edges transmit. No objective, no
#   preferred outcome, no new number: "all at 0" is the floor of the existing scale.
# EXPLORE[] = false gives the ablation (the adopted dynamics exactly).
@eval AgencySubstrate const EXPLORE = Ref(true)
@eval AgencySubstrate function step!(st::State, s::Substrate, p::Params, sch::Schedule, silenced::Set{Int})
    if st.dead
        _decay_unused!(st, s, p, fill(false, length(s.edges)))
        st.t += 1
        return st
    end
    n = nunits(s)
    old = st.active
    stale = fill(false, n)
    if EXPLORE[]
        for u in 1:n
            is_sensor(s, u) && continue
            ins = [k for (k, (_, dst, _)) in enumerate(s.edges) if dst == u]
            stale[u] = !isempty(ins) && all(k -> st.strength[k] == 0, ins)
        end
    end
    total = zeros(Int, n)
    for (k, (src, dst, w)) in enumerate(s.edges)
        ((st.strength[k] >= 1 || stale[dst]) && old[src] && !(src in silenced)) && (total[dst] += w)
    end
    new = Vector{Bool}(undef, n)
    for u in 1:n
        new[u] = if haskey(s.patch_sensors, u)
            patch = s.patch_sensors[u]
            yield_of(sch, patch, st.t) > yield_of(sch, 3 - patch, st.t)
        elseif haskey(s.resource_sensors, u)
            level, mode = s.resource_sensors[u]
            mode == "low" ? st.resource < level : st.resource >= level
        else
            total[u] >= s.theta[u]
        end
    end
    gain = sum((yield_of(sch, patch, st.t) for (m, patch) in s.motors if new[m] && !(m in silenced)); init=0)
    resource = st.resource + gain - count(new)
    if resource < 0
        st.dead = true
        st.active = fill(false, n)
        st.resource = 0
        st.t += 1
        return st
    end
    resource = min(resource, p.rmax)
    used = [old[src] && !(src in silenced) && new[dst] for (src, dst, _) in s.edges]
    if s.maintain
        for k in eachindex(s.edges)
            if used[k] && st.strength[k] < p.smax && resource >= p.grow_cost
                st.strength[k] += 1
                resource -= p.grow_cost
            end
        end
    end
    _decay_unused!(st, s, p, used)
    st.active = new
    st.resource = resource
    st.t += 1
    st
end
