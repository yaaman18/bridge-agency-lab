# Attention as winner-take-all, with credit per action (2026-10-29, user approval of the proposal).
# Load after variant_digest.jl (replaces its step!) and variant_direction.jl (uses CAPACITY).
#
# * Allocation: the capacity (CAPACITY = 5 per step) goes to the patches acted on, richest first (patch 1 on
#   a tie); a patch gets min(its yield, what is left). An acting motor is ANSWERED when its patch got > 0.
# * ATTN_MODE[] = :credit (the approved rule): an enacted contingency is confirmed when the step digests
#   something and, if its source or target is a motor, that motor was answered.
# * ATTN_MODE[] = :consolidate (exploratory comparison, not approved): additionally, nothing is confirmed in a
#   step in which some acting motor was not answered (undigested prediction error blocks consolidation).
# Unconfirmed contingencies lose confidence at ticks as before; transmission, epistemic sampling, sensors,
# form and the absence of any resource are as in variant_digest.jl.
@eval AgencySubstrate const ATTN_MODE = Ref(:credit)
@eval AgencySubstrate function allocate(offer::Vector{Int})
    d = zeros(Int, length(offer)); left = CAPACITY
    for i in sort(findall(>(0), offer); by=i -> (-offer[i], i))
        d[i] = min(offer[i], left); left -= d[i]
    end
    d
end
@eval AgencySubstrate function step!(st::State, s::Substrate, p::Params, sch::Schedule, silenced::Set{Int})
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
            yield_of(sch, patch, st.t) > 0 && yield_of(sch, patch, st.t) >= yield_of(sch, 3 - patch, st.t)
        elseif haskey(s.resource_sensors, u)
            level, mode = s.resource_sensors[u]
            mode == "low" ? st.resource < level : st.resource >= level
        else
            total[u] >= s.theta[u]
        end
    end
    acting = [m for m in keys(s.motors) if new[m] && !(m in silenced)]
    offer = [0, 0]
    for m in acting; offer[s.motors[m]] = yield_of(sch, s.motors[m], st.t); end
    d = allocate(offer)
    answered = Dict(m => d[s.motors[m]] > 0 for m in acting)
    gate = sum(d) > 0 && (ATTN_MODE[] == :credit || all(values(answered)))
    ok(u) = !haskey(s.motors, u) || get(answered, u, false)
    used = [old[src] && !(src in silenced) && new[dst] for (src, dst, _) in s.edges]
    confirmed = [used[k] && gate && ok(src) && ok(dst) for (k, (src, dst, _)) in enumerate(s.edges)]
    if s.maintain
        for k in eachindex(s.edges)
            (confirmed[k] && st.strength[k] < p.smax) && (st.strength[k] += 1)
        end
    end
    _decay_unused!(st, s, p, confirmed)
    st.active = new
    st.t += 1
    st
end
