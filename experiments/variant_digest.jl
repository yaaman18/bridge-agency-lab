# Digestion variant (2026-10-29). User decisions of 2026-10-29: the system has no physical substance, so the
# shared resource ("store") is removed; what sustains the system is the digestion of prediction error that
# the world still offers (choice 2a, "consumption of learnable surprise"). Choice 1a (taken on the agent's
# recommendation, not yet confirmed by the user): there is no physical death; losing form is collapse.
#
# Vocabulary (kept narrow on purpose):
# * residual prediction error R_i of patch i: what acting at patch i can still reduce. The world model
#   (env_digest.jl) keeps R_i; yield y_i = min(R_i, 5) is the amount digested by one step of acting there.
# * digestion: an active, non-silenced motor at patch i reduces R_i by y_i. A step "digests" when the sum
#   is positive.
# * confirmation gated by digestion (three-factor rule): an enacted contingency (src sent, dst fired) gains
#   confidence (+1 up to smax) only on a step that digests. No cost is paid: there is no resource.
# * dissipation and precision-as-gain: unchanged from variant_precision.jl (every decay_period steps an
#   unconfirmed contingency loses 1; a contingency transmits while its confidence is >= 1).
# * epistemic sampling: unchanged (a non-sensor unit whose incoming contingencies are all at 0 uses them).
# * patch sensor: fires when its patch offers something (y > 0) and not less than the other.
# Named assumption (not a theorem, not computed by the substrate): the patch sensor's report stands for the
# epistemic term of expected free energy (expected information gain) being largest at that patch, and
# digestion stands for the reduction of variational free energy by learning. The substrate computes
# neither free energy.
# Form (replaces "alive"): at the end of a window, the non-sensor units active in the window and the
# contingencies among them with confidence >= 1 contain a directed cycle. Collapse = no such cycle. Collapse
# is not absorbing: activity can continue through epistemic sampling, and form can return.
@eval AgencySubstrate const EXPLORE = Ref(true)
@eval AgencySubstrate const DIGEST_GATE = Ref(true)   # false: ablation, every enacted contingency confirmed
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
    digested = sum((yield_of(sch, patch, st.t) for (m, patch) in s.motors if new[m] && !(m in silenced)); init=0)
    gate = !DIGEST_GATE[] || digested > 0
    used = [old[src] && !(src in silenced) && new[dst] for (src, dst, _) in s.edges]
    if s.maintain && gate
        for k in eachindex(s.edges)
            (used[k] && st.strength[k] < p.smax) && (st.strength[k] += 1)
        end
    end
    _decay_unused!(st, s, p, gate ? used : fill(false, length(s.edges)))
    st.active = new
    st.t += 1
    st
end
@eval AgencySubstrate function form(window, s::Substrate)
    U = Set(u for st in window for u in 1:nunits(s) if st.active[u] && !is_sensor(s, u))
    q = last(window).strength
    adj = Dict(u => [d for (k, (a, d, _)) in enumerate(s.edges) if a == u && d in U && q[k] >= 1] for u in U)
    color = Dict(u => 0 for u in U)
    function dfs(u)
        color[u] = 1
        for v in adj[u]
            color[v] == 1 && return true
            color[v] == 0 && dfs(v) && return true
        end
        color[u] = 2
        false
    end
    any(u -> color[u] == 0 && dfs(u), collect(U))
end
@eval AgencySubstrate alive(traj, s::Substrate, p::Params) = form(traj[(end - p.alive_window + 1):end], s)
# L3 under this reading: without activity confidence dissipates under every schedule; with the system's
# own activity in the world (nothing silenced) it persists under some schedule. (The adopted test silenced
# the sensors; here confirmation needs the world's answer, so a test without the world is not meaningful.)
@eval AgencySubstrate function self_producing(s, p, pc, schedules)
    everything = Set(1:nunits(s))
    !any(x -> structure_persists(s, p, x; silenced=everything), schedules) &&
        any(x -> structure_persists(s, p, x), schedules)
end
