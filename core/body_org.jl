# The organization layer on the material body (canonical version). Port of matter/body_org.js (stages 42-55), whose
# header is the specification. Options are the JavaScript ones, as a Dict or NamedTuple with the same names:
#   U, MCOST, STEPS (required); CONTRAST ("sed" | "learn" | "learn2" | "learn3" | "bin3" | "donly"; else turn.js);
#   REV, REVR, KC, FEED, RAISE ("pre" | "body"), PER, DROPR (receptor names), PHASE.
# Conditions: "ORG", "REPLAY" (replay_acts = the acts of an ORG run), "NONE", "GREEDY".
# S47 lab options (all off by default; with none of them every step is as before): SCHED may be a function (s, k) ->
# yield of patch k at world time s; REVRK (cross! at T0 + K, T0 + 2K, ...; T0 = 800); FIXAT (from that step the
# learning state q, sg, h, cOn, cOff, lastC is put back after each circuit step); SILAT (from that step the patch motors
# are silenced with step!'s sil); REPLAYX = (acts, kept) for ORG or (acts,) for GREEDY (from T0 the circuit / rule is
# not run; the acts and the kept counts are given); KCBILL (GREEDY: the kept counts billed per step instead of 4);
# records KEPTS (keptSeries, billSeries), COUNTAT (counts at the given times), REPORT (sums from T0), SNAPAT (the
# learning state at the start of that step), LSTRACE (hash of the learning state at the end of each step), TRACE.
# The result has the keys of the JavaScript result; acts hold patch numbers (1, 2), death is nothing or the step.

bo_season(t) = (c = (t % 1000) + 1; c <= 300 ? [3.0, 2.0] : c <= 600 ? [0.0, 5.0] : [5.0, 0.0])
const BO_CUR = vcat([((i ÷ 50) % 2 == 0 ? [5.0, 0.0] : [0.0, 5.0]) for i in 0:399], [((i ÷ 15) % 2 == 0 ? [5.0, 2.0] : [2.0, 5.0]) for i in 0:399])
_opt(o, k, default = nothing) = o isa AbstractDict ? get(o, String(k), default) : get(o, k, default)
# Item 78 (lab option SCHED, world variation; the default is the frozen seasons): "heldout" = the seasons of
# sense/heldout.js ((2,4) (4,0) (0,4) (3,3) per 250 steps); "random" = 300-step blocks whose yields are drawn from 0..5
# for each patch by Mulberry(7919 * SCHEDSEED + block), drawn again while both are 0 (a block with no food at all would
# decide survival by the world alone).
function bo_world(t, o)
    sc = _opt(o, :SCHED)
    sc === nothing && return bo_season(t)
    sc isa Function && return [Float64(sc(t, 1)), Float64(sc(t, 2))]   # S47 (lab option): the synthetic world
    if sc == "heldout"
        c = (t % 1000) + 1
        return c <= 250 ? [2.0, 4.0] : c <= 500 ? [4.0, 0.0] : c <= 750 ? [0.0, 4.0] : [3.0, 3.0]
    elseif sc == "random"
        r = Mulberry(7919 * Int(_opt(o, :SCHEDSEED, 1)) + t ÷ 300)
        while true
            g = [floor(6 * r()), floor(6 * r())]
            g[1] + g[2] > 0 && return g
        end
    end
    error("unknown SCHED $sc")
end
function bo_season_at(t, o)
    ph = _opt(o, :PHASE, 0)
    g = _opt(o, :FEED, false) == true ? (t < 800 ? BO_CUR[t+1] : bo_world(t - 800 + ph, o)) : bo_world(t + ph, o)
    rev = _opt(o, :REV)
    return rev !== nothing && t >= rev ? [g[2], g[1]] : g
end

# The capacity of stage 46 (PER): at most `cap` kept contingencies (confidence >= 1 or sediment >= 1). Over it, the ones
# newly kept this step are undone (in edge order), then the weakest (confidence + sediment, the last of equals) are lost.
# Returns (blocked, lost). Shared with experiments/variant_horizon.jl (item 81).
function enforce_capacity!(circuit, was, q0, s0, cap)
    keptK(k) = circuit.q[k] >= 1 || circuit.sg[k] >= 1
    blocked = 0; lost = 0; nk = count(keptK, eachindex(circuit.q))
    k = 1
    while k <= length(circuit.q) && nk > cap
        if keptK(k) && !was[k]; circuit.q[k] = q0[k]; circuit.sg[k] = s0[k]; nk -= 1; blocked += 1; end
        k += 1
    end
    while nk > cap
        wk = 0
        for k in eachindex(circuit.q)
            (keptK(k) && (wk == 0 || circuit.q[k] + circuit.sg[k] <= circuit.q[wk] + circuit.sg[wk])) && (wk = k)
        end
        circuit.q[wk] = 0; circuit.sg[wk] = 0; nk -= 1; lost += 1
    end
    return blocked, lost
end

function body_org_run(cond::String, seed::Integer, o, replay_acts = nothing)
    U = Float64(_opt(o, :U)); MCOST = Float64(_opt(o, :MCOST)); STEPS = Int(_opt(o, :STEPS))
    ctr = _opt(o, :CONTRAST); contrast = ctr === nothing ? nothing : Symbol(ctr)
    idle_first = _opt(o, :IDLE, false) == true   # item 72 (lab option, not in matter/body_org.js)
    core_gate = _opt(o, :GATE, false) == true   # item 76 (lab option)
    seen_both = _opt(o, :SEENBOTH, false) == true   # item 79 (lab option)
    sed_fade = _opt(o, :SEDFADE, false) == true   # item 84 (lab option)
    READCUR = _opt(o, :READCUR, false) == true && _opt(o, :FEED, false) == true   # item 82: during the fed raising the circuit reads the scripted yields
    REVR = _opt(o, :REVR); KC = _opt(o, :KC, 0); PER = _opt(o, :PER); RAISE = _opt(o, :RAISE, "pre"); DROPR = _opt(o, :DROPR)
    # S47 lab options (off by default)
    ST0 = 800; REVRK = _opt(o, :REVRK); FIXAT = _opt(o, :FIXAT); SILAT = _opt(o, :SILAT); REPLAYX = _opt(o, :REPLAYX)
    KCBILL = _opt(o, :KCBILL); KEPTS = _opt(o, :KEPTS, false) == true; COUNTAT = _opt(o, :COUNTAT); REPORT = _opt(o, :REPORT, false) == true
    SNAPAT = _opt(o, :SNAPAT); LSTRACE = _opt(o, :LSTRACE, false) == true; TRACE = _opt(o, :TRACE, false) == true
    lstate(c) = (copy(c.q), copy(c.sg), copy(c.h), c.cOn === nothing ? nothing : copy(c.cOn), c.cOff === nothing ? nothing : copy(c.cOff), c.lastC === nothing ? nothing : copy(c.lastC))
    fixed = nothing; snap = nothing; silset = Set{Int}()
    keptS = Int[]; billS = Float64[]; lsH = UInt64[]; trace = Any[]; countAt = Int[]
    rYield = [0.0, 0.0]; rN = 0; rCap = 0; rActs = 0; rAns = 0; rMoved = 0.0; rSpent = 0.0; rUpkeep = 0.0
    w = make_world(; reservoir = 300.0); seed!(w, 12, 12, 1)
    pool = [0.0, 0.0]; T0 = total(w) + 0
    perm = collect(1:length(FEATURES))   # the run's receptor features (crossed at REVR for the circuit and the rule alike)
    b = nothing; circuit = nothing; noise = nothing
    if cond == "ORG"
        b = newborn(false; perm = perm, extra = _opt(o, :EXTRA, false) == true ? collect(EXTRA_FEATURES) : Int[])   # item 78 B
        DROPR === nothing || drop_sources!(b, DROPR)
        circuit = init(b); noise = Mulberry(seed)
        if RAISE != "body"; for y in BO_CUR; step!(circuit, b, [y[1], y[2], 0.0]; noise = noise, contrast = contrast, idle_first = idle_first, core_gate = core_gate, seen_both = seen_both, sed_fade = sed_fade); end; end
    end
    keptK(k) = circuit.q[k] >= 1 || circuit.sg[k] >= 1
    lost = 0; blocked = 0
    ON_STEP = _opt(o, :ON_STEP)   # lab option (item 80): a read-only observer called after each step; it must not change anything
    SEEN = _opt(o, :SEEN, false) == true; seen = Vector{Vector{Float64}}()   # item 78: the yields the circuit read (lab option)
    acts = Vector{Vector{Int}}(); logv = Any[]; alive = true; death = nothing; maxErr = 0.0; nActs = 0; nAns = 0
    moved = 0.0; spent = 0.0; sumCount = 0; sumLate = 0; nform = 0; kept = 0; upkeep = 0.0; win = Any[]
    for t in 0:STEPS-1
        (REVR !== nothing && t == REVR) && cross!(perm)
        (REVRK !== nothing && t > ST0 && (t - ST0) % REVRK == 0) && cross!(perm)
        (SNAPAT !== nothing && t == SNAPAT && circuit !== nothing) && (snap = lstate(circuit))
        if FIXAT !== nothing && t == FIXAT && circuit !== nothing; fixed = lstate(circuit); end
        if SILAT !== nothing && t == SILAT && b !== nothing; silset = Set{Int}(m for m in eachindex(b.names) if b.kind[m] == 'M' && b.patch[m] <= 2); end
        replaying = REPLAYX !== nothing && t >= ST0
        tSpent = 0.0; tUpkeep = 0.0; tBill = 0.0; tKept = 0
        y = [min(5.0, floor(r / U + 1e-9)) for r in pool]
        SEEN && push!(seen, y)
        body = [i for i in eachindex(w.C) if w.C[i] != 0]
        if alive && isempty(body); alive = false; death = t; end
        acting = Int[]; d = [0.0, 0.0]
        if alive && cond == "ORG" && replaying
            acting = copy(_opt(REPLAYX, :acts)[t+1])
            offer = [0.0, 0.0]; for p in acting; offer[p] = y[p]; end; d = allocate(offer)
        end
        if alive && cond == "ORG" && !replaying
            was = [keptK(k) for k in eachindex(circuit.q)]; q0 = copy(circuit.q); s0 = copy(circuit.sg)
            yin = READCUR && t < 800 ? BO_CUR[t+1] : y   # item 82 (lab option); the harvest still comes from the pools
            out = step!(circuit, b, [yin[1], yin[2], 0.0]; noise = noise, contrast = contrast, idle_first = idle_first, core_gate = core_gate, seen_both = seen_both, sed_fade = sed_fade, sil = silset)
            if fixed !== nothing   # S47 FIXAT: the learning state is put back; the activity record goes on
                circuit.q = copy(fixed[1]); circuit.sg = copy(fixed[2]); circuit.h = copy(fixed[3])
                circuit.cOn = fixed[4] === nothing ? nothing : copy(fixed[4]); circuit.cOff = fixed[5] === nothing ? nothing : copy(fixed[5])
                circuit.lastC = fixed[6] === nothing ? nothing : copy(fixed[6])
            end
            if PER !== nothing
                bl, lo = enforce_capacity!(circuit, was, q0, s0, floor(Int, length(body) / PER)); blocked += bl; lost += lo
            end
            acting = [b.patch[m] for m in out.acting if b.patch[m] <= 2]; d = out.d
            push!(win, (active = copy(circuit.active), q = copy(circuit.q))); length(win) > 5 && popfirst!(win)
            form(win, b) && (nform += 1)
        end
        if alive && cond == "REPLAY"
            idx = (t + (STEPS >> 1) + 500) % STEPS + 1
            acting = idx <= length(replay_acts) ? copy(replay_acts[idx]) : Int[]
            offer = [0.0, 0.0]; for p in acting; offer[p] = y[p]; end; d = allocate(offer)
        end
        if alive && cond == "GREEDY" && replaying
            acting = copy(_opt(REPLAYX, :acts)[t+1])
            offer = [0.0, 0.0]; for q in acting; offer[q] = y[q]; end; d = allocate(offer)
        end
        if alive && cond == "GREEDY" && !replaying
            ys = [y[1], y[2], 0.0, 0.0]; r(k) = feature(perm, k)(ys, t + 1, () -> 0.0)
            p = r(7) ? 1 : r(8) ? 2 : r(1) ? 1 : r(2) ? 2 : 0
            acting = p != 0 ? [p] : Int[]; offer = [0.0, 0.0]; for q in acting; offer[q] = y[q]; end; d = allocate(offer)
        end
        push!(acts, acting)
        if alive && cond == "GREEDY" && KC != 0
            nb = KCBILL === nothing ? 4 : KCBILL[t+1]   # S47 KCBILL (lab option): the billed kept counts
            kept += nb; cost = KC * nb; paid = 0.0
            for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
            port_give!(w.port, paid); upkeep += paid
            tKept = nb; tBill = cost; tUpkeep = paid
        end
        if alive && cond == "ORG" && KC != 0
            nk = replaying ? _opt(REPLAYX, :kept)[t+1] : count(k -> circuit.q[k] >= 1 || circuit.sg[k] >= 1, eachindex(circuit.q)); kept += nk
            cost = KC * nk; paid = 0.0
            for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
            port_give!(w.port, paid); upkeep += paid
            tKept = nk; tBill = cost; tUpkeep = paid
        end
        if alive && !isempty(acting)
            for k in 1:2
                if d[k] > 0
                    take = min(pool[k], d[k] * U); pool[k] -= take
                    for i in body; w.A[i] += take / length(body); end
                    moved += take; t >= ST0 && (rMoved += take)
                end
            end
            cost = MCOST * length(acting); paid = 0.0
            for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
            port_give!(w.port, paid); spent += paid
            nActs += length(acting); nAns += count(p -> d[p] > 0, acting)
            tSpent = paid
            if t >= ST0; rActs += length(acting); rAns += count(p -> d[p] > 0, acting); end
        end
        g = bo_season_at(t, o)
        capped = false
        for k in 1:2
            tk = port_take!(w.port, g[k] * U); tk < g[k] * U && (capped = true)
            pool[k] += tk; over = pool[k] - 50 * U
            if over > 0; pool[k] -= over; port_give!(w.port, over); end
        end
        step!(w, ())
        ON_STEP === nothing || ON_STEP((t = t, w = w, circuit = circuit, b = b, noise = noise, y = y, acting = acting, d = d, pool = pool, g = g, alive = alive))   # read-only observer (viewer/export_body.jl)
        c = nconstituents(w); sumCount += c; t >= STEPS / 2 && (sumLate += c)
        # S47 records (read-only)
        if KEPTS; push!(keptS, tKept); push!(billS, tBill); end
        (COUNTAT !== nothing && (t + 1) in COUNTAT) && push!(countAt, c)
        LSTRACE && push!(lsH, circuit === nothing ? UInt64(0) : hash(lstate(circuit)))
        TRACE && push!(trace, (copy(acting), tSpent, tUpkeep, pool[1], pool[2], hash((w.A, w.B, w.C, w.port.reservoir, w.port.inflow, w.port.outflow))))
        if REPORT && t >= ST0
            rYield .+= g; rN += 1; capped && (rCap += 1); rSpent += tSpent; rUpkeep += tUpkeep
        end
        if (t + 1) % 500 == 0
            maxErr = max(maxErr, abs(total(w) + pool[1] + pool[2] - T0))
            push!(logv, Any[t + 1, c, tofixed(count_matter(w).bound, 2)])
        end
    end
    return Dict{String,Any}("cond" => cond, "seed" => seed, "maxErr" => maxErr, "death" => death, "meanCount" => sumCount / STEPS,
        "lost" => lost, "blocked" => blocked, "keptEnd" => cond == "ORG" ? count(keptK, eachindex(circuit.q)) : nothing,
        "meanLate" => sumLate / (STEPS / 2), "kept" => kept / STEPS, "upkeep" => upkeep, "final" => count_matter(w).constituents,
        "nActs" => nActs, "answered" => nAns / max(1, nActs), "moved" => moved, "spent" => spent, "form" => nform / STEPS,
        "log" => logv, "acts" => acts, (SEEN ? ("seen" => seen,) : ())...,
        (KEPTS ? ("keptSeries" => keptS, "billSeries" => billS) : ())..., (COUNTAT !== nothing ? ("countAt" => countAt,) : ())...,
        (SNAPAT !== nothing ? ("snap" => snap,) : ())..., (LSTRACE ? ("lsHash" => lsH,) : ())..., (TRACE ? ("trace" => trace,) : ())...,
        (REPORT ? ("rep" => Dict{String,Any}("yieldMean" => rYield ./ max(1, rN), "capSteps" => rCap, "nActs" => rActs,
            "answered" => rAns / max(1, rActs), "moved" => rMoved, "spent" => rSpent, "upkeep" => rUpkeep),) : ())...)
end
