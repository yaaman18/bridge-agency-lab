# The circuit of the organization layer (canonical version). Port of memory/turn_sed.js (stage 48-54), which with
# contrast = nothing is memory/turn.js rev. 2 (memory/check_turn_sed.js). Rules, constants and order of operations are
# those of the JavaScript file; its header (stages 19-25, 48-54) is the specification. Indices are 1-based here; the
# JavaScript copies are 0-based, and conversions happen only at the JSON boundary (life.jl, core/check/).
#
# Contrast rules (opts contrast): nothing (turn.js), :sed, :learn, :learn2, :learn3, :bin3 (the app since v3.5), :donly.

const P_SMAX = 4; const P_DECAY = 8; const P_WINDOW = 5; const P_CAPACITY = 5; const P_CAP = 50
const P_W = 10; const P_FRESH = 20; const P_KINDS = 4
const ALPHA = 0.05; const THETA_C = 0.5; const FORGET = 100; const THETA_B = 0.1

# Receptor features. ys = [yield1, yield2, gesture kind or 0, waiting 0/1]; t = the step; r = the noise rng.
const FEATURES = Tuple{String,Function}[
    ("y1>=3", (y, t, r) -> y[1] >= 3), ("y2>=3", (y, t, r) -> y[2] >= 3), ("y1==0", (y, t, r) -> y[1] == 0),
    ("y2==0", (y, t, r) -> y[2] == 0), ("noise", (y, t, r) -> r() < 0.5), ("clock3", (y, t, r) -> t % 3 == 0),
    ("y1>y2", (y, t, r) -> y[1] > y[2]), ("y2>y1", (y, t, r) -> y[2] > y[1]), ("partner", (y, t, r) -> y[3] > 0),
    ("waiting", (y, t, r) -> y[4] > 0), ("not waiting", (y, t, r) -> y[4] == 0)]
# The JavaScript files permute their module-level FEATURES array to cross the receptors (the reversal of the world);
# here each circuit carries the permutation: slot s holds feature perm[s].
const CROSS = ((1, 2), (3, 4), (7, 8))
cross!(perm::Vector{Int}) = (for (i, j) in CROSS; perm[i], perm[j] = perm[j], perm[i]; end; perm)
feature(perm, s) = FEATURES[perm[s]][2]

mutable struct Circuit
    names::Vector{String}
    kind::Vector{Char}        # 'R' receptor, 'C' core, 'M' motor
    feat::Vector{Int}         # feature slot (1-based) for receptors, 0 otherwise
    theta::Vector{Int}
    patch::Vector{Int}        # motors: 1, 2 (patches), 3 (call); 0 otherwise
    edges::Vector{NTuple{3,Int}}
    q0::Vector{Int}
    initial::Vector{Bool}
    perm::Vector{Int}
    ins::Vector{Vector{Int}}  # edges into each unit, in edge order
end
function reindex!(b::Circuit)
    b.ins = [Int[] for _ in b.names]
    for (k, e) in enumerate(b.edges); push!(b.ins[e[2]], k); end
    return b
end
unit(b::Circuit, n::AbstractString) = findfirst(==(n), b.names)

function newborn(partner::Bool = true, proprio::Bool = partner; perm = collect(1:length(FEATURES)))
    names = String[]; kind = Char[]; feat = Int[]; theta = Int[]; patch = Int[]
    nr = partner ? (proprio ? 11 : 9) : 8
    for i in 1:nr; push!(names, "r$i"); push!(kind, 'R'); push!(feat, i); push!(theta, 0); push!(patch, 0); end
    for n in (partner ? ("c1", "c2", "c3") : ("c1", "c2")); push!(names, n); push!(kind, 'C'); push!(feat, 0); push!(theta, 1); push!(patch, 0); end
    for (i, n) in enumerate(partner ? ("m1", "m2", "m3") : ("m1", "m2")); push!(names, n); push!(kind, 'M'); push!(feat, 0); push!(theta, 2); push!(patch, i); end
    id(n) = findfirst(==(n), names)
    edges = NTuple{3,Int}[]; q0 = Int[]
    add(a, c, q) = (push!(edges, (id(a), id(c), 1)); push!(q0, q))
    add("c1", "c1", 4); add("c2", "c2", 4); add("c1", "c2", 4); add("c2", "c1", 4)
    if partner; add("c3", "c3", 4); add("c1", "c3", 4); add("c3", "c1", 4); add("c2", "c3", 4); add("c3", "c2", 4); end
    pairs = partner ? (("c1", "m1"), ("c2", "m2"), ("c3", "m3")) : (("c1", "m1"), ("c2", "m2"))
    for (c, m) in pairs; add(c, m, 0); for i in 1:nr; add("r$i", m, 0); end; end
    reindex!(Circuit(names, kind, feat, theta, patch, edges, q0, [n[1] == 'c' for n in names], perm, Vector{Int}[]))
end
# Remove every contingency whose source is one of the named units (body_org.js DROPR; the units stay).
function drop_sources!(b::Circuit, units)
    drop = Set(unit(b, n) for n in units); keep = [!(e[1] in drop) for e in b.edges]
    b.edges = b.edges[keep]; b.q0 = b.q0[keep]; reindex!(b)
end

mutable struct Pend
    t::Int
    E::Vector{Int}
    R::Vector{Int}
end
mutable struct CState
    active::Vector{Bool}; q::Vector{Int}; sg::Vector{Int}; h::Vector{Int}; off::Vector{Int}; t::Int
    pend::Vector{Pend}; fresh::Vector{Int}
    prev::Union{Nothing,Vector{Bool}}
    cOn::Union{Nothing,Vector{Float64}}; cOff::Union{Nothing,Vector{Float64}}
    lastM::Union{Nothing,Vector{Int}}
end
init(b::Circuit) = CState(copy(b.initial), copy(b.q0), zeros(Int, length(b.q0)), zeros(Int, length(b.q0)), zeros(Int, length(b.names)),
                         0, Pend[], fill(5, P_KINDS), nothing, nothing, nothing, nothing)

function allocate(offer)
    d = [0.0, 0.0]; left = Float64(P_CAPACITY)
    idx = sort(filter(i -> offer[i] > 0, [1, 2]); lt = (i, j) -> (offer[i] != offer[j] ? offer[i] > offer[j] : i < j))
    for i in idx; d[i] = min(offer[i], left); left -= d[i]; end
    return d
end

const L2RULES = (:learn2, :learn3, :bin3)
# One step of the circuit. y = [yield1, yield2(, gesture)]. Returns what turn_sed.js returns (unit indices 1-based).
function step!(st::CState, b::Circuit, y; noise = nothing, contrast::Union{Nothing,Symbol} = nothing, explore = true,
               fail = true, memory = true, orient = true, sil = Set{Int}(), idle_first = false)
    n = length(b.names); old = st.active; ne = length(b.edges)
    g = length(y) >= 3 ? y[3] : 0
    ys = Float64[y[1], y[2], g, isempty(st.pend) ? 0 : 1]
    mem = memory; now = st.t + 1; prev = st.prev === nothing ? old : st.prev
    ct = contrast
    onset = [orient && b.kind[u] == 'R' && old[u] && !prev[u] for u in 1:n]
    idle(u) = ct in (:learn3, :bin3, :donly) && b.kind[u] == 'M' && b.patch[u] <= 2 && st.lastM !== nothing && now - st.lastM[u] > FORGET
    stale = [explore && b.kind[u] != 'R' && !isempty(b.ins[u]) &&
             (idle(u) || all(k -> st.q[k] == 0 && (!mem || st.sg[k] == 0), b.ins[u])) for u in 1:n]
    total = zeros(Int, n); conf = zeros(Int, n); habit = zeros(Int, n); drove = falses(ne)
    for (k, (a, c, w)) in enumerate(b.edges)
        if (st.q[k] >= 1 || (mem && st.sg[k] >= 1) || stale[c] || (onset[a] && st.q[k] == 0 && st.sg[k] == 0 && st.h[k] == 0)) && old[a] && !(a in sil)
            total[c] += w
            if st.q[k] >= 1; conf[c] += w; elseif mem && st.sg[k] >= 1; habit[c] += w; end
            drove[k] = true
        end
    end
    nw = Vector{Bool}(undef, n)
    for u in 1:n
        nw[u] = b.kind[u] == 'R' ? feature(b.perm, b.feat[u])(ys, now, noise) : total[u] >= b.theta[u]
    end
    motors = [u for u in 1:n if b.kind[u] == 'M']
    cand = [m for m in motors if nw[m] && b.patch[m] <= 2]
    # idle_first (item 72, opt-in; formal/LabCircuit.lean IdleFirst): among the candidates, a motor that has not acted
    # for longer than FORGET steps is preferred; the old ranking decides among the preferred ones (or all, if none is idle).
    idle_first && st.lastM === nothing && (st.lastM = zeros(Int, n))
    choice = nothing   # read-only record of the choice (for the comparison with Lean's IdleFirst.pick)
    if length(cand) > 1
        key(m) = conf[m] * 1_000_000 + habit[m] * 1_000 + total[m]
        function rank(cs)
            best = maximum(key, cs); tied = [m for m in cs if key(m) == best]; pv = [m for m in tied if old[m]]
            pool = isempty(pv) ? tied : pv
            return pool[argmin([b.patch[m] for m in pool])]
        end
        win = rank(cand)
        if idle_first
            pref = win; idl = [m for m in cand if now - st.lastM[m] > FORGET]
            isempty(idl) || (win = rank(idl))
            choice = (now = now, cand = copy(cand), last = [st.lastM[m] for m in cand], pref = pref, win = win)
        end
        for m in cand; m != win && (nw[m] = false); end
    end
    acting = [m for m in motors if nw[m] && !(m in sil)]
    onPatch = [m for m in acting if b.patch[m] <= 2]
    ci = findfirst(m -> b.patch[m] == 3, acting); call = ci === nothing ? 0 : acting[ci]
    offer = [0.0, 0.0]; for m in onPatch; offer[b.patch[m]] = y[b.patch[m]]; end
    d = allocate(offer)
    answered = Dict{Int,Bool}(m => d[b.patch[m]] > 0 for m in onPatch)
    gate = d[1] + d[2] > 0 && all(values(answered))
    ok(u) = b.kind[u] != 'M' || get(answered, u, false) == true
    confirmed = [drove[k] && nw[c] && gate && ok(a) && ok(c) for (k, (a, c, _)) in enumerate(b.edges)]
    rm(k) = b.kind[b.edges[k][1]] == 'R' && b.kind[b.edges[k][2]] == 'M' && b.patch[b.edges[k][2]] <= 2
    STATS = ct !== nothing && ct != :donly
    if STATS
        if st.cOn === nothing; st.cOn = fill(NaN, ne); st.cOff = fill(NaN, ne); end
        for m in onPatch
            dm = d[b.patch[m]]
            for (k, (a, c, _)) in enumerate(b.edges)
                (c != m || b.kind[a] != 'R') && continue
                arr = old[a] ? st.cOn : st.cOff; v = ct == :bin3 ? (dm > 0 ? 1.0 : 0.0) : dm
                arr[k] = isnan(arr[k]) ? v : arr[k] + ALPHA * (v - arr[k])
            end
        end
    end
    L2 = ct in L2RULES
    if idle_first && !(L2 || ct == :donly)   # the rules that do not keep lastM keep it when idle_first is on
        for m in onPatch; st.lastM[m] = now; end
    end
    if L2 || ct == :donly
        st.lastM === nothing && (st.lastM = zeros(Int, n))
        for m in motors
            b.patch[m] <= 2 || continue
            if m in onPatch
                st.lastM[m] = now
            elseif L2 && now - st.lastM[m] == FORGET
                for (k, (a, c, _)) in enumerate(b.edges); if c == m && b.kind[a] == 'R'; st.cOn[k] = NaN; st.cOff[k] = NaN; end; end
            end
        end
    end
    function passes(k)
        (!STATS || !rm(k)) && return true
        cc = st.cOn[k] - st.cOff[k]
        return L2 && isnan(cc) ? true : cc > (ct == :bin3 ? THETA_B : THETA_C)
    end
    if L2; for k in 1:ne; confirmed[k] && !passes(k) && (confirmed[k] = false); end; end
    function grow(k)
        ((ct == :learn || L2) && !passes(k)) && return
        if st.q[k] < P_SMAX
            st.q[k] = min(P_SMAX, st.q[k] + 1 + (mem ? st.sg[k] : 0))
            if mem && st.q[k] == P_SMAX && (ct != :sed || passes(k)); st.sg[k] = min(P_SMAX, st.sg[k] + 1); end
        end
    end
    function weaken(k)
        (st.q[k] == 0 && st.sg[k] == 0) && (st.h[k] = min(P_SMAX, st.h[k] + 1))
        if st.q[k] > 0 || !mem; st.q[k] = max(st.q[k] - 1, 0); else st.sg[k] = max(st.sg[k] - 1, 0); end
    end
    for k in 1:ne; confirmed[k] && grow(k); end
    confirmed_patch = copy(confirmed)   # read-only record (formal/LabCircuit.lean Window): edges confirmed with the patch acts
    if fail
        for m in onPatch
            answered[m] && continue
            for (k, (a, c, _)) in enumerate(b.edges)
                (c == m && b.kind[a] == 'R' && drove[k] && !confirmed[k]) && weaken(k)
            end
        end
    end
    # The partner's answer: a fresh gesture answers the oldest call still pending (made at an earlier step, within W).
    callAnswered = false; callFailed = 0; answered_call = nothing; call_confirmed = Int[]
    gi = Int(g)
    if gi > 0 && st.fresh[gi] >= 1
        i = findfirst(p -> p.t < now && now - p.t <= P_W, st.pend)
        if i !== nothing
            st.fresh[gi] = 0; callAnswered = true; answered_call = st.pend[i]
            for k in st.pend[i].E; if !confirmed[k]; grow(k); confirmed[k] = true; push!(call_confirmed, k); end; end
            deleteat!(st.pend, i)
        end
    end
    keep = Pend[]
    for p in st.pend
        if now - p.t >= P_W
            callFailed += 1
            if fail; for k in p.R; !confirmed[k] && weaken(k); end; end
        else
            push!(keep, p)
        end
    end
    st.pend = keep
    if call != 0
        okc(u) = b.kind[u] != 'M' || u == call
        push!(st.pend, Pend(now, [k for (k, (a, c, _)) in enumerate(b.edges) if drove[k] && nw[c] && okc(a) && okc(c)],
                            [k for (k, (a, c, _)) in enumerate(b.edges) if c == call && b.kind[a] == 'R' && drove[k]]))
    end
    for u in 1:n
        if b.kind[u] == 'R' && b.feat[u] >= 10
            nw[u] = feature(b.perm, b.feat[u])(Float64[0, 0, 0, isempty(st.pend) ? 0 : 1], now, noise)
        end
    end
    now % P_FRESH == 0 && (st.fresh = [min(5, f + 1) for f in st.fresh])
    if now % P_DECAY == 0; for k in 1:ne; !confirmed[k] && (st.q[k] = max(st.q[k] - 1, 0)); end; end
    for u in 1:n
        b.kind[u] == 'R' || continue
        st.off[u] = nw[u] ? 0 : st.off[u] + 1
        if st.off[u] > 0 && st.off[u] % P_DECAY == 0
            for (k, (a, _, _)) in enumerate(b.edges); (a == u && st.h[k] > 0) && (st.h[k] -= 1); end
        end
    end
    st.prev = old; st.active = nw; st.t = now
    return (acting = acting, d = d, gate = gate, answered = answered, call = call != 0,
            callWhileWaiting = call != 0 && ys[4] > 0, callAnswered = callAnswered, callFailed = callFailed,
            # read-only record for the DC windows (dc.jl); nothing below feeds back into the dynamics
            drove = drove, confirmed_patch = confirmed_patch, answered_call = answered_call, call_confirmed = call_confirmed,
            choice = choice)
end

# Form: a directed cycle of confident contingencies among the non-receptor units active within the window.
function form(win, b::Circuit)
    U = falses(length(b.names))
    for w in win, (u, a) in enumerate(w.active); (a && b.kind[u] != 'R') && (U[u] = true); end
    q = win[end].q
    adj = [Int[] for _ in b.names]
    for (k, (a, c, _)) in enumerate(b.edges); (U[a] && U[c] && q[k] >= 1) && push!(adj[a], c); end
    col = zeros(Int, length(b.names))
    function dfs(u)
        col[u] = 1
        for v in adj[u]
            col[v] == 1 && return true
            (col[v] == 0 && dfs(v)) && return true
        end
        col[u] = 2; return false
    end
    for u in eachindex(U); (U[u] && col[u] == 0 && dfs(u)) && return true; end
    return false
end
