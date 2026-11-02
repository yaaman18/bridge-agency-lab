# The organization layer on the material body (canonical version). Port of matter/body_org.js (stages 42-55), whose
# header is the specification. Options are the JavaScript ones, as a Dict or NamedTuple with the same names:
#   U, MCOST, STEPS (required); CONTRAST ("sed" | "learn" | "learn2" | "learn3" | "bin3" | "donly"; else turn.js);
#   REV, REVR, KC, FEED, RAISE ("pre" | "body"), PER, DROPR (receptor names), PHASE.
# Conditions: "ORG", "REPLAY" (replay_acts = the acts of an ORG run), "NONE", "GREEDY".
# The result has the keys of the JavaScript result; acts hold patch numbers (1, 2), death is nothing or the step.

bo_season(t) = (c = (t % 1000) + 1; c <= 300 ? [3.0, 2.0] : c <= 600 ? [0.0, 5.0] : [5.0, 0.0])
const BO_CUR = vcat([((i ÷ 50) % 2 == 0 ? [5.0, 0.0] : [0.0, 5.0]) for i in 0:399], [((i ÷ 15) % 2 == 0 ? [5.0, 2.0] : [2.0, 5.0]) for i in 0:399])
_opt(o, k, default = nothing) = o isa AbstractDict ? get(o, String(k), default) : get(o, k, default)
function bo_season_at(t, o)
    ph = _opt(o, :PHASE, 0)
    g = _opt(o, :FEED, false) == true ? (t < 800 ? BO_CUR[t+1] : bo_season(t - 800 + ph)) : bo_season(t + ph)
    rev = _opt(o, :REV)
    return rev !== nothing && t >= rev ? [g[2], g[1]] : g
end

function body_org_run(cond::String, seed::Integer, o, replay_acts = nothing)
    U = Float64(_opt(o, :U)); MCOST = Float64(_opt(o, :MCOST)); STEPS = Int(_opt(o, :STEPS))
    ctr = _opt(o, :CONTRAST); contrast = ctr === nothing ? nothing : Symbol(ctr)
    idle_first = _opt(o, :IDLE, false) == true   # item 72 (lab option, not in matter/body_org.js)
    core_gate = _opt(o, :GATE, false) == true   # item 76 (lab option)
    REVR = _opt(o, :REVR); KC = _opt(o, :KC, 0); PER = _opt(o, :PER); RAISE = _opt(o, :RAISE, "pre"); DROPR = _opt(o, :DROPR)
    w = make_world(; reservoir = 300.0); seed!(w, 12, 12, 1)
    pool = [0.0, 0.0]; T0 = total(w) + 0
    perm = collect(1:length(FEATURES))   # the run's receptor features (crossed at REVR for the circuit and the rule alike)
    b = nothing; circuit = nothing; noise = nothing
    if cond == "ORG"
        b = newborn(false; perm = perm)
        DROPR === nothing || drop_sources!(b, DROPR)
        circuit = init(b); noise = Mulberry(seed)
        if RAISE != "body"; for y in BO_CUR; step!(circuit, b, [y[1], y[2], 0.0]; noise = noise, contrast = contrast, idle_first = idle_first, core_gate = core_gate); end; end
    end
    keptK(k) = circuit.q[k] >= 1 || circuit.sg[k] >= 1
    lost = 0; blocked = 0
    acts = Vector{Vector{Int}}(); logv = Any[]; alive = true; death = nothing; maxErr = 0.0; nActs = 0; nAns = 0
    moved = 0.0; spent = 0.0; sumCount = 0; sumLate = 0; nform = 0; kept = 0; upkeep = 0.0; win = Any[]
    for t in 0:STEPS-1
        (REVR !== nothing && t == REVR) && cross!(perm)
        y = [min(5.0, floor(r / U + 1e-9)) for r in pool]
        body = [i for i in eachindex(w.C) if w.C[i] != 0]
        if alive && isempty(body); alive = false; death = t; end
        acting = Int[]; d = [0.0, 0.0]
        if alive && cond == "ORG"
            was = [keptK(k) for k in eachindex(circuit.q)]; q0 = copy(circuit.q); s0 = copy(circuit.sg)
            out = step!(circuit, b, [y[1], y[2], 0.0]; noise = noise, contrast = contrast, idle_first = idle_first, core_gate = core_gate)
            if PER !== nothing
                cap = floor(Int, length(body) / PER); nk = count(keptK, eachindex(circuit.q))
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
        if alive && cond == "GREEDY"
            ys = [y[1], y[2], 0.0, 0.0]; r(k) = feature(perm, k)(ys, t + 1, () -> 0.0)
            p = r(7) ? 1 : r(8) ? 2 : r(1) ? 1 : r(2) ? 2 : 0
            acting = p != 0 ? [p] : Int[]; offer = [0.0, 0.0]; for q in acting; offer[q] = y[q]; end; d = allocate(offer)
        end
        push!(acts, acting)
        if alive && cond == "GREEDY" && KC != 0
            kept += 4; cost = KC * 4; paid = 0.0
            for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
            port_give!(w.port, paid); upkeep += paid
        end
        if alive && cond == "ORG" && KC != 0
            nk = count(k -> circuit.q[k] >= 1 || circuit.sg[k] >= 1, eachindex(circuit.q)); kept += nk
            cost = KC * nk; paid = 0.0
            for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
            port_give!(w.port, paid); upkeep += paid
        end
        if alive && !isempty(acting)
            for k in 1:2
                if d[k] > 0
                    take = min(pool[k], d[k] * U); pool[k] -= take
                    for i in body; w.A[i] += take / length(body); end
                    moved += take
                end
            end
            cost = MCOST * length(acting); paid = 0.0
            for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
            port_give!(w.port, paid); spent += paid
            nActs += length(acting); nAns += count(p -> d[p] > 0, acting)
        end
        g = bo_season_at(t, o)
        for k in 1:2
            pool[k] += port_take!(w.port, g[k] * U); over = pool[k] - 50 * U
            if over > 0; pool[k] -= over; port_give!(w.port, over); end
        end
        step!(w, ())
        c = nconstituents(w); sumCount += c; t >= STEPS / 2 && (sumLate += c)
        if (t + 1) % 500 == 0
            maxErr = max(maxErr, abs(total(w) + pool[1] + pool[2] - T0))
            push!(logv, Any[t + 1, c, tofixed(count_matter(w).bound, 2)])
        end
    end
    return Dict{String,Any}("cond" => cond, "seed" => seed, "maxErr" => maxErr, "death" => death, "meanCount" => sumCount / STEPS,
        "lost" => lost, "blocked" => blocked, "keptEnd" => cond == "ORG" ? count(keptK, eachindex(circuit.q)) : nothing,
        "meanLate" => sumLate / (STEPS / 2), "kept" => kept / STEPS, "upkeep" => upkeep, "final" => count_matter(w).constituents,
        "nActs" => nActs, "answered" => nAns / max(1, nActs), "moved" => moved, "spent" => spent, "form" => nform / STEPS,
        "log" => logv, "acts" => acts)
end
