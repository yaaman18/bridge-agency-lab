# S61b r2 (discussion/specs/S61b-nesting-cpc-bounded.md): S61 r3 (experiments/nesting_cpc/NestingCPC.jl) with the
# three differences of S61b §1 only: (1) the harvest EMA h_ema in the body, updated right after h_t; (2) the normal
# split of every configuration except Runaway-Cancer gated by the marginal upkeep of one more module;
# (3) the shared-rule diagnostic of G4 (judge_e3(...; shared = true)). Everything else is S61 r3 unchanged.
# Only the rule of §3 is the dynamics; the probes read deep copies of the state and never write back into a run.
# phi_rich and the interpreter string are forbidden inputs: step! accepts them and does not read them (E2).
module NestingCPCB

using Random

export CONFIGS, NAMES, T, DELTA, make_tape, init_system, step!, run_config, r2_violations, judge_e3,
       write_state, write_events, inventory

const T = 120
const R0 = 20.0
const RMAX = 40.0
const D0 = 0.0
const D_LETHAL = 12.0
const M0 = 4
const U0 = 4.0
const ETA_SELF = 0.35
const ETA_CPC = 0.45
const C_MOD = 0.55
const C_SPLIT = 1.5
const SPLIT_R = 14.0           # S61 r3, still the Runaway-Cancer reference; no longer read by the normal split
const H_EMA0 = 3.0             # S61b §1.1
const H_EMA_KEEP = 0.75
const H_EMA_GAIN = 0.25
const SPLIT_H_MARGIN = 1.25    # S61b §1.2: h̄ > 1.25·c_mod·(|M_t|+1)
const SPLIT_R_MARGIN = 6.0     # S61b §1.2: R > 6.0·c_mod·(|M_t|+1)
const SPLIT_U = 5.5
const MERGE_U = 1.2
const MERGE_EPS = 0.05
const BONUS_MAX = 1.6
const BONUS_RATE = 0.25
const NOISE = 0.05
const HB = 3.0
const HB_LEAN = 1.2
const HIDDEN_T = 15
const RUNAWAY_EVERY = 4
const CHILD_PERT = 0.05
const DELTA = 2
const THETA_INIT_SCALE = 0.1   # detail not fixed by the spec (§3.2 says only "decided from the seed")

const CONFIGS = (:CPC, :Runaway, :Fixed, :RotFO, :RotRed, :Hidden, :Omitted)
const NAMES = Dict(:CPC => "CPC-Prolif", :Runaway => "Runaway-Cancer", :Fixed => "Fixed-Core",
                   :RotFO => "Rotating-Mediator-Failover", :RotRed => "Rotating-Mediator-Redundant",
                   :Hidden => "Hidden-Age-Control", :Omitted => "Omitted-Cache-Control")
const LINK_CONFIGS = (:CPC, :Runaway, :Hidden)

# ---------------------------------------------------------------- tape (§3.1)

struct TapeStep
    x::Int
    h::Float64
    r::UInt64
end

"Replay tape of length T and the initial logit tables, both from Xoshiro(seed). Period 12 is three steps per symbol."
function make_tape(seed::Integer)
    rng = Xoshiro(seed)
    tape = Vector{TapeStep}(undef, T)
    for k in 1:T
        base = ((k - 1) ÷ 3) % 4 + 1
        shift = k >= 81 ? 2 : (k >= 41 ? 1 : 0)
        x = mod1(base + shift, 4)
        if rand(rng) < NOISE
            x = rand(rng, 1:4)
        end
        h = (45 <= k <= 65) ? HB_LEAN : HB
        tape[k] = TapeStep(x, h, rand(rng, UInt64))
    end
    thetas = [THETA_INIT_SCALE .* randn(rng, 4, 4) for _ in 1:M0]
    tape, thetas
end

# ---------------------------------------------------------------- state

mutable struct Mod
    id::Int
    theta::Matrix{Float64}
    u::Float64
    born::Int
end

mutable struct System
    config::Symbol
    alive::Bool
    R::Float64
    D::Float64
    h_ema::Float64             # S61b: exponential moving average of the harvest (M1 body state)
    mods::Vector{Mod}          # kept in increasing id order
    next_id::Int
    ctx::Int
    step::Int                  # completed steps (the rotation phase reads this, never the absolute clock)
    grant_cache::Vector{Float64}   # one-step grant cache (written only by the two redundant configurations)
end

init_system(config::Symbol, thetas) =
    System(config, true, R0, D0, H_EMA0, [Mod(i, copy(thetas[i]), U0, 0) for i in 1:M0], M0 + 1, 1, 0, Float64[])

"The inventory each configuration declares: state fields, module fields and the fields holding copies of grants."
struct GrantInventory
    system_fields::Vector{Symbol}
    module_fields::Vector{Symbol}
    caches::Vector{Symbol}
end

function inventory(config::Symbol)
    sysf = [:config, :alive, :R, :D, :h_ema, :mods, :next_id, :ctx, :step, :grant_cache]
    config == :Omitted && (sysf = filter(!=(:grant_cache), sysf))   # the deliberate omission
    GrantInventory(sysf, [:id, :theta, :u, :born], config == :RotRed ? [:grant_cache] : Symbol[])
end

struct Event
    kind::Symbol          # :persist :split :absorption :fusion :death
    srcs::Vector{Int}
    outs::Vector{Int}
end

struct StepRec
    t::Int
    alive_pre::Bool
    alive_post::Bool
    body::Symbol          # :persist, :death, :absent
    events::Vector{Event}
    pre_objs::Vector{Mod}
    post_objs::Vector{Mod}
    next_id_pre::Int
    next_id_post::Int
    births::Int           # split children issued in this step
    deficit::Float64
    D::Float64
    h_ema::Float64
end

# ---------------------------------------------------------------- control of the probes

const RuleKey = Tuple{Symbol,Int,Int}

Base.@kwdef struct Ctl
    pert_id::Int = 0
    pert_delta::Float64 = 0.0
    pert_all::Bool = false
    disabled_rules::Vector{RuleKey} = RuleKey[]
    disabled_hosts::Vector{Int} = Int[]
    failover::Bool = true
    disabled_caches::Vector{Symbol} = Symbol[]
    override::Dict{RuleKey,Vector{Float64}} = Dict{RuleKey,Vector{Float64}}()
end
const DEFAULT = Ctl()

# ---------------------------------------------------------------- wiring (§3.2 step 4)

"Undirected neighbours by position 1..n: ring and opposite chord for n ≥ 4, complete otherwise."
function neighbor_table(n::Int)
    nb = [Int[] for _ in 1:n]
    add!(a, b) = (a != b && !(b in nb[a])) && (push!(nb[a], b); push!(nb[b], a))
    if n >= 4
        for j in 0:n-1
            add!(j + 1, (j + 1) % n + 1)
            add!(j + 1, (j + n ÷ 2) % n + 1)
        end
    else
        for a in 1:n, b in a+1:n
            add!(a, b)
        end
    end
    foreach(sort!, nb)
    nb
end

function softmax(v)
    m = maximum(v)
    p = exp.(v .- m)
    p ./ sum(p)
end

meanvec(e) = sum(e) ./ length(e)

function predictions(sys::System)
    [softmax(m.theta[sys.ctx, :]) for m in sys.mods]
end

function residuals(sys::System, x::Int, ctl::Ctl = DEFAULT)
    P = predictions(sys)
    e = [[(s == x ? 1.0 : 0.0) - P[i][s] for s in 1:4] for i in eachindex(P)]
    for i in eachindex(e)
        if ctl.pert_all || sys.mods[i].id == ctl.pert_id
            e[i][x] += ctl.pert_delta
        end
    end
    P, e
end

"Hosts of the mediator rule at the current phase (the rotating index reads the completed-step counter)."
function phase_hosts(sys::System)
    ids = [m.id for m in sys.mods]
    n = length(ids)
    c = sys.config
    c == :Fixed && return [ids[1]]
    c == :RotFO && return [ids[(sys.step % n) + 1]]
    c in (:RotRed, :Omitted) && return unique([ids[(sys.step % n) + 1], ids[((sys.step + 1) % n) + 1]])
    Int[]
end

function candidate_rules(sys::System)
    c = sys.config
    if c in LINK_CONFIGS
        ids = [m.id for m in sys.mods]
        nb = neighbor_table(length(ids))
        return [(:local_link, ids[k], ids[i]) for i in eachindex(ids) for k in nb[i]]
    end
    c == :Fixed && return [(:R_fixed, 0, 0)]
    c == :RotFO && return [(:R_rot_fo, 0, 0)]
    [(:R_rot_red, 0, 0)]
end

"Cross-module corrections η_cpc·(…) per module and the fresh grant (empty when none was issued)."
function cross_terms(sys::System, e, ctl::Ctl = DEFAULT)
    ids = [m.id for m in sys.mods]
    n = length(ids)
    cross = [zeros(4) for _ in 1:n]
    fresh = Float64[]
    c = sys.config
    if c in LINK_CONFIGS
        nb = neighbor_table(n)
        for i in 1:n
            isempty(nb[i]) && continue
            acc = zeros(4)
            for k in nb[i]
                key = (:local_link, ids[k], ids[i])
                (key in ctl.disabled_rules || ids[k] in ctl.disabled_hosts) && continue
                acc .+= get(ctl.override, key, e[k])
            end
            cross[i] = ETA_CPC .* (acc ./ length(nb[i]))
        end
    elseif c == :Fixed
        key = (:R_fixed, 0, 0)
        if !(key in ctl.disabled_rules) && !(ids[1] in ctl.disabled_hosts)
            z = get(ctl.override, key, meanvec(e))
            for i in 1:n
                cross[i] = ETA_CPC .* z
            end
        end
    elseif c == :RotFO
        key = (:R_rot_fo, 0, 0)
        if !(key in ctl.disabled_rules)
            order = [ids[((sys.step + r) % n) + 1] for r in 0:(ctl.failover ? n - 1 : 0)]
            if any(h -> !(h in ctl.disabled_hosts), order)
                z = get(ctl.override, key, meanvec(e))
                for i in 1:n
                    cross[i] = ETA_CPC .* z
                end
            end
        end
    else   # :RotRed, :Omitted: two hosts, two redundant links, one-step cache with fallback read
        key = (:R_rot_red, 0, 0)
        hosts = phase_hosts(sys)
        if !(key in ctl.disabled_rules) && any(h -> !(h in ctl.disabled_hosts), hosts)
            z = get(ctl.override, key, meanvec(e))
            fresh = copy(z)
            for i in 1:n
                cross[i] = ETA_CPC .* z
            end
        elseif !isempty(sys.grant_cache) && !(:grant_cache in ctl.disabled_caches)
            for i in 1:n
                cross[i] = ETA_CPC .* sys.grant_cache
            end
        end
    end
    cross, fresh
end

# ---------------------------------------------------------------- one step (§3.2)

function split_one!(sys::System, m::Mod, t::Int, rng, events; runaway::Bool = false)
    up = m.u
    child_theta = m.theta .+ CHILD_PERT .* rand(rng, (-1.0, 1.0), 4, 4)
    if runaway
        sys.D += max(C_SPLIT - up, 0.0)
        rest = max(up - C_SPLIT, 0.0)
    else
        rest = up - C_SPLIT
    end
    m.u = 0.55 * rest
    child = Mod(sys.next_id, child_theta, 0.45 * rest, t)
    sys.next_id += 1
    push!(sys.mods, child)
    push!(events, Event(:split, [m.id], [m.id, child.id]))
    child.id
end

function highest_u(mods, exclude)
    best = nothing
    for m in mods
        m.id in exclude && continue
        if best === nothing || m.u > best.u
            best = m
        end
    end
    best
end

"One step. `t_abs` is the absolute clock (only Hidden-Age-Control reads it); phi_rich and interp are not read."
function step!(sys::System, ts::TapeStep, t_abs::Int; ctl::Ctl = DEFAULT, phi_rich = 0.0, interp = "")
    t = sys.step + 1
    pre_objs = copy(sys.mods)
    next_pre = sys.next_id
    if !sys.alive
        return StepRec(t, false, false, :absent, Event[], pre_objs, copy(sys.mods), next_pre, sys.next_id, 0, 0.0, sys.D,
                       sys.h_ema)
    end
    rng = Xoshiro(ts.r)
    n = length(sys.mods)
    # 2. predictions and the coalition act
    P, e = residuals(sys, ts.x, ctl)
    w = [max(m.u, 0.1) for m in sys.mods]
    w = w ./ sum(w)
    pc = sum(w[i] .* P[i] for i in 1:n)
    a = argmax(pc)
    # 3. harvest
    h = ts.h * (1.0 + 1.5 * (a == ts.x ? 1.0 : 0.0))
    sys.h_ema = H_EMA_KEEP * sys.h_ema + H_EMA_GAIN * h   # S61b §1.1: right after h_t
    # 4. residuals and the CPC update of the context row
    acc = [P[i][ts.x] for i in 1:n]
    cross, fresh = cross_terms(sys, e, ctl)
    c = sys.ctx
    for i in 1:n
        sys.mods[i].theta[c, :] .+= ETA_SELF .* e[i] .+ cross[i]
    end
    if sys.config in (:RotRed, :Omitted)
        sys.grant_cache = fresh
    end
    # 5. upkeep, debt and the local traces
    Ravail = min(RMAX, sys.R + h)
    B = C_MOD * n
    def = max(0.0, B - Ravail)
    if Ravail >= B
        Rrem = Ravail - B
        rep = min(sys.D, Rrem)
        D1 = sys.D - rep
        S = Rrem - rep
        bonus = min(BONUS_MAX, BONUS_RATE * S)
        R1 = S - bonus
        paid = B + bonus
    else
        R1 = 0.0
        D1 = sys.D + def
        paid = Ravail
    end
    denom = sum(acc .+ 0.1)
    for i in 1:n
        m = sys.mods[i]
        m.u = m.u + paid * (acc[i] + 0.1) / denom - C_MOD
    end
    sys.R = R1
    sys.D = D1
    # 6. turnover
    events = Event[]
    births = 0
    # (i) death
    for m in sys.mods
        m.u <= 0.0 && push!(events, Event(:death, [m.id], Int[]))
    end
    filter!(m -> m.u > 0.0, sys.mods)
    isempty(sys.mods) && (sys.alive = false)
    # (ii) merge
    touched = Set{Int}()
    if length(sys.mods) >= 4
        nb = neighbor_table(length(sys.mods))
        best = nothing
        for p in eachindex(sys.mods), q in nb[p]
            q > p || continue
            mp, mq = sys.mods[p], sys.mods[q]
            (mp.u < MERGE_U && mq.u < MERGE_U) || continue
            key = (mp.u + mq.u, min(mp.id, mq.id), max(mp.id, mq.id))
            if best === nothing || key < best[1]
                best = (key, mp, mq)
            end
        end
        if best !== nothing
            _, mp, mq = best
            lo, hi = mp.id < mq.id ? (mp, mq) : (mq, mp)
            if abs(mp.u - mq.u) > MERGE_EPS
                win, lose = mp.u > mq.u ? (mp, mq) : (mq, mp)
                win.u = win.u + lose.u
                filter!(m -> m !== lose, sys.mods)
                push!(events, Event(:absorption, [lo.id, hi.id], [win.id]))
                push!(touched, lo.id, hi.id)
            else
                fused = Mod(sys.next_id, (mp.theta .+ mq.theta) ./ 2, mp.u + mq.u, t)
                sys.next_id += 1
                filter!(m -> m !== mp && m !== mq, sys.mods)
                push!(sys.mods, fused)
                push!(events, Event(:fusion, [lo.id, hi.id], [fused.id]))
                push!(touched, lo.id, hi.id, fused.id)
            end
        end
    end
    # (iii) split
    if sys.alive
        cfg = sys.config
        if cfg == :Runaway
            if t % RUNAWAY_EVERY == 0
                for m in [m for m in sys.mods if !(m.id in touched)]
                    split_one!(sys, m, t, rng, events; runaway = true)
                    births += 1
                end
            end
        else
            # S61b §1.2: the marginal upkeep of one more module, |M_t| = n modules at the start of the step
            marg = C_MOD * (n + 1)
            if sys.h_ema > SPLIT_H_MARGIN * marg && sys.R > SPLIT_R_MARGIN * marg && sys.D == 0.0
                m = highest_u(sys.mods, touched)
                if m !== nothing && m.u > SPLIT_U
                    cid = split_one!(sys, m, t, rng, events)
                    births += 1
                    push!(touched, m.id, cid)
                end
            end
            if cfg == :Hidden && t_abs == HIDDEN_T
                m = highest_u(sys.mods, touched)
                if m !== nothing
                    split_one!(sys, m, t, rng, events)
                    births += 1
                end
            end
        end
    end
    # (iv) lethality
    if sys.D > D_LETHAL || isempty(sys.mods)
        sys.alive = false
    end
    # persist edges and the body edge
    inevent = Set(s for ev in events for s in ev.srcs)
    postids = Set(m.id for m in sys.mods)
    for m in pre_objs
        (!(m.id in inevent) && m.id in postids) && push!(events, Event(:persist, [m.id], [m.id]))
    end
    # (v) the context; the wiring is a function of the sorted ids and is rebuilt on every read
    sys.ctx = ts.x
    sys.step = t
    StepRec(t, true, sys.alive, sys.alive ? :persist : :death, events, pre_objs, copy(sys.mods), next_pre,
            sys.next_id, births, def, sys.D, sys.h_ema)
end

function run_config(config::Symbol, seed::Integer; t_start::Int = 0, phi_rich = 0.0, interp = "",
                    snapshots::Bool = false)
    tape, thetas = make_tape(seed)
    sys = init_system(config, thetas)
    recs = StepRec[]
    snaps = System[]
    for k in 1:T
        snapshots && push!(snaps, deepcopy(sys))
        push!(recs, step!(sys, tape[k], t_start + k; phi_rich = phi_rich, interp = interp))
    end
    (sys = sys, recs = recs, snaps = snaps, tape = tape)
end

# ---------------------------------------------------------------- serialization (bit comparison)

function write_state(io::IO, sys::System)
    write(io, sys.alive, sys.R, sys.D, sys.h_ema, Int64(sys.next_id), Int64(sys.ctx), Int64(sys.step), Int64(length(sys.mods)))
    for m in sys.mods
        write(io, Int64(m.id), m.u, Int64(m.born))
        write(io, vec(m.theta))
    end
    write(io, Int64(length(sys.grant_cache)), sys.grant_cache)
end

function write_events(io::IO, rec::StepRec)
    write(io, Int64(rec.t), rec.alive_post, string(rec.body), Int64(length(rec.events)))
    for ev in rec.events
        write(io, string(ev.kind), Int64(length(ev.srcs)), Int64.(ev.srcs), Int64(length(ev.outs)), Int64.(ev.outs))
    end
end

# ---------------------------------------------------------------- R2 checker

"Violations of R2 in one transition. `issued` holds every carrier id issued before the step and is updated."
function r2_violations(rec::StepRec, issued::Set{Int})
    v = String[]
    t = rec.t
    if !rec.alive_pre
        isempty(rec.events) || push!(v, "t=$t events after the end of function")
        rec.alive_post && push!(v, "t=$t body reconnected after death")
        rec.body == :absent || push!(v, "t=$t body edge after death")
        return v
    end
    rec.body == (rec.alive_post ? :persist : :death) || push!(v, "t=$t body edge does not match alive")
    pre = Dict(m.id => m for m in rec.pre_objs)
    postids = [m.id for m in rec.post_objs]
    allunique(postids) || push!(v, "t=$t duplicate carrier id in V_{t+1}")
    post = Dict{Int,Vector{Mod}}()
    for m in rec.post_objs
        push!(get!(post, m.id, Mod[]), m)
    end
    nsrc = Dict{Int,Int}()
    nout = Dict{Int,Int}()
    for ev in rec.events
        for s in ev.srcs
            nsrc[s] = get(nsrc, s, 0) + 1
        end
        for o in ev.outs
            nout[o] = get(nout, o, 0) + 1
        end
    end
    for id in keys(pre)
        get(nsrc, id, 0) == 1 || push!(v, "t=$t source $id is in $(get(nsrc, id, 0)) events")
    end
    for id in keys(nsrc)
        haskey(pre, id) || push!(v, "t=$t event source $id not in V_t")
    end
    for id in unique(postids)
        get(nout, id, 0) == 1 || push!(v, "t=$t target $id is the output of $(get(nout, id, 0)) events")
    end
    for id in keys(nout)
        haskey(post, id) || push!(v, "t=$t event output $id not in V_{t+1}")
    end
    same_carrier(id) = haskey(pre, id) && haskey(post, id) && length(post[id]) == 1 && post[id][1] === pre[id] &&
                       pre[id].born < t
    fresh_ids = Int[]
    function fresh!(o)
        ok = o >= rec.next_id_pre && !(o in issued) && haskey(post, o) && all(m -> m.born == t, post[o])
        ok || push!(v, "t=$t output $o is not a freshly issued carrier")
        push!(fresh_ids, o)
    end
    for ev in rec.events
        if ev.kind == :persist
            (length(ev.srcs) == 1 && ev.outs == ev.srcs) || push!(v, "t=$t malformed persist")
            same_carrier(ev.srcs[1]) || push!(v, "t=$t persist $(ev.srcs[1]): carrier interrupted")
        elseif ev.kind == :split
            p = ev.srcs[1]
            length(ev.srcs) == 1 && length(ev.outs) >= 2 || push!(v, "t=$t malformed split")
            ncont = count(==(p), ev.outs) + max(length(get(post, p, Mod[])) - 1, 0)
            ncont <= 1 || push!(v, "t=$t split $p has $ncont continuant outputs")
            if p in ev.outs
                same_carrier(p) || push!(v, "t=$t split $p: continuant carrier interrupted")
            end
            foreach(fresh!, filter(!=(p), ev.outs))
        elseif ev.kind == :absorption
            (length(ev.srcs) == 2 && length(ev.outs) == 1 && ev.outs[1] in ev.srcs) ||
                push!(v, "t=$t malformed absorption")
            same_carrier(ev.outs[1]) || push!(v, "t=$t absorption $(ev.outs[1]): carrier interrupted")
        elseif ev.kind == :fusion
            (length(ev.srcs) == 2 && length(ev.outs) == 1 && !(ev.outs[1] in ev.srcs)) ||
                push!(v, "t=$t malformed fusion")
            fresh!(ev.outs[1])
        elseif ev.kind == :death
            (length(ev.srcs) == 1 && isempty(ev.outs) && !haskey(post, ev.srcs[1])) ||
                push!(v, "t=$t malformed death")
        else
            push!(v, "t=$t unknown event $(ev.kind)")
        end
    end
    sort(fresh_ids) == fresh_ids || push!(v, "t=$t fresh ids not issued in increasing order")
    rec.next_id_post == rec.next_id_pre + length(fresh_ids) || push!(v, "t=$t allocator does not match the births")
    for id in postids
        (haskey(pre, id) || id in fresh_ids) || push!(v, "t=$t carrier $id appears without an issuing event")
    end
    union!(issued, fresh_ids)
    v
end

# ---------------------------------------------------------------- E3′ (§4 G4)

nonzero(cross) = any(c -> any(!=(0.0), c), cross)

"Largest |Δp̂_j| (j ≠ source, all context rows) within DELTA steps with the body held equal."
function propagation(snap::System, tape, s::Int, src::Int, delta::Float64)
    base = deepcopy(snap)
    pert = deepcopy(snap)
    best = 0.0
    for lag in 1:DELTA
        k = s + lag - 1
        k > T && break
        step!(base, tape[k], k)
        step!(pert, tape[k], k; ctl = lag == 1 ? Ctl(pert_id = src, pert_delta = delta) : DEFAULT)
        pert.R = base.R
        pert.D = base.D
        pert.h_ema = base.h_ema   # S61b: h̄ is body state and is isolated with (R, D)
        pert.alive = base.alive
        bmods = Dict(m.id => m for m in base.mods)
        for mj in pert.mods
            (mj.id == src || !haskey(bmods, mj.id)) && continue
            mb = bmods[mj.id]
            for c in 1:4
                best = max(best, maximum(abs.(softmax(mj.theta[c, :]) .- softmax(mb.theta[c, :]))))
            end
        end
    end
    best
end

function find_tstar(run)
    for t in 1:T
        rec = run.recs[t]
        rec.alive_pre || break
        any(ev -> ev.kind in (:split, :death, :absorption, :fusion), rec.events) || continue
        lo, hi = t - DELTA - 1, t + DELTA + 1
        (lo >= 1 && hi <= T) || continue
        all(s -> run.snaps[s].alive && length(run.snaps[s].mods) >= 3, [lo:t-1; t+1:hi]) && return t
    end
    0
end

const SHARED = (:shared_link, 0, 0)

"Rules the judge tests: the per-edge rules, or (shared = true, S61b §1.3 diagnostic) every local_link as one rule."
judged_rules(snap::System, shared::Bool) = (shared && snap.config in LINK_CONFIGS) ? [SHARED] : candidate_rules(snap)
expand_rule(snap::System, R) = R == SHARED ? candidate_rules(snap) : [R]

"E3′ with the priority unresolved > core_present > no_core_witnessed. Returns the verdict and the evidence."
function judge_e3(config::Symbol, seed::Integer; shared::Bool = false)
    run = run_config(config, seed; snapshots = true)
    ts = find_tstar(run)
    ts == 0 && return (verdict = :no_tstar, tstar = 0, info = Dict{Symbol,Any}())
    pre = collect(ts-DELTA-1:ts-1)
    post = collect(ts+1:ts+DELTA+1)
    steps = [pre; post]
    inv = inventory(config)
    info = Dict{Symbol,Any}()
    # calibration (δ = 0) and propagation (δ = 0.8) for every source at every probe step
    calib = 0.0
    prop = Dict{Int,Bool}()
    for s in steps
        snap = run.snaps[s]
        ok = true
        for m in snap.mods
            calib = max(calib, propagation(snap, run.tape, s, m.id, 0.0))
            ok &= propagation(snap, run.tape, s, m.id, 0.8) > 1e-9
        end
        prop[s] = ok
    end
    info[:calib] = calib
    info[:prop_pre] = all(prop[s] for s in pre)
    info[:prop_post] = all(prop[s] for s in post)
    info[:phases_pre] = sort(unique(vcat([phase_hosts(run.snaps[s]) for s in pre]...)))
    info[:phases_post] = sort(unique(vcat([phase_hosts(run.snaps[s]) for s in post]...)))
    # priority 1: reflective inventory audit and the cache-penetration probe
    omitted = [setdiff(collect(fieldnames(System)), inv.system_fields);
               setdiff(collect(fieldnames(Mod)), inv.module_fields)]
    info[:omitted] = omitted
    residual = false
    unexplained = false
    for s in steps
        snap = run.snaps[s]
        _, e = residuals(snap, run.tape[s].x)
        stopped, _ = cross_terms(snap, e, Ctl(disabled_rules = candidate_rules(snap)))
        if nonzero(stopped)
            residual = true
            alsocache, _ = cross_terms(snap, e, Ctl(disabled_rules = candidate_rules(snap), disabled_caches = inv.caches))
            nonzero(alsocache) && (unexplained = true)
        end
    end
    info[:residual] = residual
    info[:unexplained] = unexplained
    if !isempty(omitted) || unexplained
        return (verdict = :unresolved, tstar = ts, info = info)
    end
    # priority 2: bulk disabling, interchange, time-fixed ablation, cuts and bypass witnesses
    stops = Dict{RuleKey,Vector{Bool}}()
    follows = Dict{RuleKey,Vector{Bool}}()
    allbypass = true
    hostcut1 = false
    rulecut1 = false
    ablation = Bool[]
    restored = true
    for (si, s) in enumerate(steps)
        snap = run.snaps[s]
        x = run.tape[s].x
        _, e = residuals(snap, x)
        _, e2 = residuals(snap, x, Ctl(pert_all = true, pert_delta = 0.8))   # the other execution
        base, _ = cross_terms(snap, e)
        restored &= nonzero(base)
        n = length(snap.mods)
        for R in judged_rules(snap, shared)
            off, _ = cross_terms(snap, e, Ctl(disabled_rules = expand_rule(snap, R), disabled_caches = inv.caches))
            st = !nonzero(off)
            st && (rulecut1 = true)
            st && (allbypass = false)
            v = get!(stops, R, fill(false, length(steps)))
            v[si] = st
            other(Rk) = Rk[1] == :local_link ? e2[findfirst(m -> m.id == Rk[2], snap.mods)] : meanvec(e2)
            sw, _ = cross_terms(snap, e, Ctl(override = Dict(Rk => other(Rk) for Rk in expand_rule(snap, R))))
            f = get!(follows, R, fill(false, length(steps)))
            f[si] = all(j -> sw[j] != base[j], 1:n)
        end
        for hst in [m.id for m in snap.mods]
            off, _ = cross_terms(snap, e, Ctl(disabled_hosts = [hst]))
            !nonzero(off) && (hostcut1 = true)
        end
        hs = phase_hosts(snap)
        if !isempty(hs)
            off, _ = cross_terms(snap, e, Ctl(disabled_hosts = hs, failover = false))
            push!(ablation, !nonzero(off))
        end
    end
    core_bulk = [R for (R, v) in stops if all(v)]
    core_inter = [R for (R, v) in follows if all(v)]
    info[:restored] = restored
    info[:core_bulk] = core_bulk
    info[:core_inter] = core_inter
    info[:ablation_stops] = isempty(ablation) ? missing : all(ablation)
    info[:bypass_all] = allbypass
    info[:hostcut_ge2] = !hostcut1
    info[:rulecut_ge2] = !rulecut1
    info[:nrules] = length(stops)
    if restored && (!isempty(core_bulk) || !isempty(core_inter))
        return (verdict = :core_present, tstar = ts, info = info)
    end
    if allbypass && !hostcut1 && !rulecut1 && info[:prop_pre] && info[:prop_post] && calib == 0.0
        return (verdict = :no_core_witnessed, tstar = ts, info = info)
    end
    (verdict = :unresolved, tstar = ts, info = info)
end

end # module
