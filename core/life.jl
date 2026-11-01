# The world and life loop of the app (canonical version). Port of memory/life_turn.js v3.5 (rule bin3), and since v3.7
# (item 73) the rule "bin3+idle" (bin3 with the idle-first choice of item 72; the page runs the Rust copy, rust/being-core).
# The rule "bin3" is kept for the JavaScript copies (core/check) and for the earlier trials. The saved being L is kept as the JSON record the app stores
# (Dict, JavaScript conventions: unit and edge indices 0-based, NaN saved as null), so that a being can move between the
# app and Julia. Not ported: migration of v1/v2 records (life_turn.js migrate; the being in the app has been v3 since
# 2026-10-30) and the page's snapshot.

# The app's rules by the name saved in the record (L["rule"]): the contrast rule and the idle-first choice.
const RULES = Dict("bin3" => (contrast = :bin3, idle_first = false), "bin3+idle" => (contrast = :bin3, idle_first = true))
const RULE_NAME = "bin3+idle"   # the app since v3.7 (item 73)
const RULE = RULES[RULE_NAME].contrast
const AUTO_SEG = 1500
const NURSERY = 400; const SCHOOL = 400; const BLOCK = 300; const MAXGAP = 200
life_season(t) = (c = ((t - 1) % 1000) + 1; c <= 300 ? [3.0, 2.0] : c <= 600 ? [0.0, 5.0] : [5.0, 0.0])
function apply_reversal!(perm::Vector{Int}, rev::Integer)
    perm .= 1:length(perm)
    isodd(rev) && cross!(perm)
    return perm
end

emptystats() = Dict{String,Any}(c => Dict{String,Any}("steps" => 0, "calls" => 0, "answered" => 0, "gestures" => 0, "waiting" => 0) for c in ("live", "replay"))
freshpartner() = Dict{String,Any}("mode" => "live", "rec" => Any[], "rp" => nothing, "brng" => 777, "bcond" => "live", "bnext" => 0,
                                  "stats" => emptystats(), "ignored" => 0)
function freshlife(; born = round(Int, time() * 1000))
    b = newborn(true); st = init(b)
    Dict{String,Any}("v" => 3, "age" => 0, "wt" => 0, "R" => Any[P_CAP, P_CAP], "active" => copy(st.active), "q" => copy(st.q),
        "sg" => copy(st.sg), "h" => copy(st.h), "off" => copy(st.off), "prev" => copy(st.active), "rng" => 20261030, "reversals" => 0,
        "stasisUntil" => 0, "hist" => Dict{String,Any}("sediment" => Any[], "unans" => Any[], "savings" => Any[], "calls" => Any[]),
        "unansWindow" => 0, "callWindow" => Any[0, 0], "lastAct" => Dict{String,Any}(), "open" => nothing, "pend" => nothing,
        "fresh" => copy(st.fresh), "partner" => freshpartner(), "born" => born)
end

mutable struct Life
    L::Dict{String,Any}
    b::Circuit
    st::CState
    queue::Vector{Int}
    win::Vector{Any}
    counting::Bool
    counted::Int
    lastCond::Union{Nothing,String}
    last::Any
    rule::String
end

num(x) = x === nothing ? NaN : Float64(x)
pend_from(p) = Pend(Int(p["t"]), [Int(k) + 1 for k in p["E"]], [Int(k) + 1 for k in p["R"]])
pend_to(p::Pend) = Dict{String,Any}("t" => p.t, "E" => [k - 1 for k in p.E], "R" => [k - 1 for k in p.R])

function makelife(saved = nothing; rule::String = RULE_NAME)
    L = saved === nothing ? freshlife() : saved
    get(L, "v", 1) == 3 || error("records of v1/v2 need life_turn.js migrate(), which is not ported")
    b = newborn(true)
    prior = get(L, "rule", nothing)
    if prior != rule
        L["ruleHist"] = vcat(get(L, "ruleHist", nothing) === nothing ? Any[] : L["ruleHist"], Any[Any[L["age"], rule]])
        L["rule"] = rule
        # the contrast statistics and the last acts are kept when only the choice changes (bin3 -> bin3+idle, item 73);
        # otherwise they start empty (v3.4, v3.5)
        if !(prior isa String && haskey(RULES, prior) && RULES[prior].contrast == RULES[rule].contrast && get(L, "lastM", nothing) !== nothing)
            L["cOn"] = nothing; L["cOff"] = nothing; L["lastM"] = Any[L["age"] for _ in b.names]
        end
    end
    nanv(a) = a === nothing ? nothing : Float64[num(x) for x in a]
    st = CState(Bool.(L["active"]), Int.(L["q"]), Int.(L["sg"]), Int.(L["h"]), Int.(L["off"]), Int(L["age"]),
                Pend[pend_from(p) for p in (get(L, "pend", nothing) === nothing ? Any[] : L["pend"])], Int.(L["fresh"]), Bool.(L["prev"]),
                nanv(get(L, "cOn", nothing)), nanv(get(L, "cOff", nothing)),
                get(L, "lastM", nothing) === nothing ? fill(Int(L["age"]), length(b.names)) : Int.(L["lastM"]))
    apply_reversal!(b.perm, L["reversals"])
    haskey(L, "session") && L["session"] !== nothing || (L["session"] = Dict{String,Any}("marks" => Any[], "ev" => Any[]))
    return Life(L, b, st, Int[], Any[], false, 0, nothing, nothing, rule)
end

# The two generators of the record: the world's noise (L.rng) and the blind schedule (partner.brng), int32 states.
function _draw!(d::Dict, key)
    r = Mulberry(d[key]); x = r(); d[key] = state_int32(r); return x
end
phase(l::Life) = l.L["age"] < NURSERY ? "nursery" : l.L["age"] < NURSERY + SCHOOL ? "school" : "world"
function condition!(l::Life, now)
    p = l.L["partner"]
    p["mode"] != "blind" && return p["mode"]
    if now >= p["bnext"]
        p["bcond"] = _draw!(p, "brng") < 0.5 ? "live" : "replay"; p["bnext"] = now + BLOCK; p["rp"] = nothing
    end
    return p["bcond"]
end
function replay_gesture!(l::Life)
    p = l.L["partner"]; rec = p["rec"]
    length(rec) < 3 && return 0
    p["rp"] === nothing && (p["rp"] = Dict{String,Any}("j" => 0, "wait" => 1))
    p["rp"]["wait"] -= 1
    p["rp"]["wait"] > 0 && return 0
    j = p["rp"]["j"]; g = rec[j+1][2]; nj = (j + 1) % length(rec)
    p["rp"] = Dict{String,Any}("j" => nj, "wait" => nj == 0 ? 50 : max(1, min(MAXGAP, rec[nj+1][1] - rec[j+1][1])))
    return Int(g)
end
function _push_cap!(v, x, cap)
    push!(v, x); length(v) > cap && popfirst!(v); return v
end

function live!(l::Life, n::Integer = 1; on_step = nothing)
    L = l.L; b = l.b; st = l.st; S = L["session"]
    logev(e) = _push_cap!(S["ev"], e, 12000)
    recIn(m) = [k for (k, e) in enumerate(b.edges) if e[2] == m && b.kind[e[1]] == 'R']
    ek(a, c) = findfirst(e -> b.names[e[1]] == a && b.names[e[2]] == c, b.edges)
    noise = () -> _draw!(L, "rng"); rule = RULES[l.rule]
    for _ in 1:n
        ph = phase(l); now = L["age"] + 1; p = L["partner"]; inWorld = ph == "world"
        y = if ph == "nursery"
            ((L["age"] ÷ 50) % 2 == 0 ? [5.0, 0.0] : [0.0, 5.0])
        elseif ph == "school"
            (((L["age"] - NURSERY) ÷ 15) % 2 == 0 ? [5.0, 2.0] : [2.0, 5.0])
        else
            L["age"] < L["stasisUntil"] ? [0.0, 0.0] : [min(Float64(L["R"][1]), 5.0), min(Float64(L["R"][2]), 5.0)]
        end
        cond = condition!(l, now); g = 0
        if cond == "live"
            g = isempty(l.queue) ? 0 : popfirst!(l.queue)
            g != 0 && _push_cap!(p["rec"], Any[now, g], 2000)
        else
            if !isempty(l.queue)
                p["ignored"] += length(l.queue); l.counting && logev(Any["u", now, length(l.queue)]); empty!(l.queue)
            end
            g = replay_gesture!(l)
        end
        push!(y, g)
        before = copy(st.q)
        o = step!(st, b, y; noise = noise, contrast = rule.contrast, idle_first = rule.idle_first)
        on_step === nothing || on_step(o, st, cond, y, ph)   # read-only observer (dc.jl); it must not change anything
        L["age"] = st.t
        if inWorld
            L["wt"] += 1
            gr = L["age"] <= L["stasisUntil"] ? [0.0, 0.0] : life_season(L["wt"])
            L["R"] = Any[min(P_CAP, L["R"][k] - o.d[k] + gr[k]) for k in 1:2]
        end
        _push_cap!(l.win, (active = copy(st.active), q = copy(st.q)), P_WINDOW)
        for m in o.acting
            b.patch[m] > 2 && continue
            ans = o.answered[m]; ans || (L["unansWindow"] += 1)
            la = get(L["lastAct"], string(m - 1), nothing)
            gap = la === nothing ? Inf : L["age"] - la
            (ans && gap >= 32 && L["open"] === nothing) && (L["open"] = Dict{String,Any}("m" => m - 1, "conf" => 0, "age" => L["age"]))
            L["lastAct"][string(m - 1)] = L["age"]
        end
        if L["open"] !== nothing
            ks = recIn(L["open"]["m"] + 1)
            any(k -> st.q[k] > before[k], ks) && (L["open"]["conf"] += 1)
            if any(k -> st.q[k] >= P_SMAX, ks) || L["open"]["conf"] > 20
                _push_cap!(L["hist"]["savings"], Any[L["open"]["age"], L["open"]["conf"]], 300); L["open"] = nothing
            end
        end
        o.call && (L["callWindow"][1] += 1); o.callAnswered && (L["callWindow"][2] += 1)
        if l.counting
            s = p["stats"][cond]; s["steps"] += 1
            o.call && (s["calls"] += 1); o.callWhileWaiting && (s["waiting"] += 1); o.callAnswered && (s["answered"] += 1); g != 0 && (s["gestures"] += 1)
            c = cond == "live" ? 1 : 0
            if cond != l.lastCond; logev(Any["b", now, c]); l.lastCond = cond; end
            A = get(S, "auto", nothing)
            if A !== nothing && A["seg"] <= 3 && (A["n"] += 1; A["n"] % AUTO_SEG == 0)
                A["seg"] += 1; push!(S["marks"], Any[now, A["seg"] <= 3 ? string(A["seg"]) : "end"])
                p["mode"] = A["seg"] == 3 ? "blind" : "live"; p["rp"] = nothing; p["bnext"] = 0
            end
            g != 0 && logev(Any["g", now, g, c]); o.call && logev(Any["c", now, o.callWhileWaiting ? 1 : 0, c]); o.callAnswered && logev(Any["a", now, c])
            l.counted += 1
            if l.counted % 100 == 0
                qs(nm) = (k = ek(nm, "m3"); Any[st.q[k], st.sg[k]])
                logev(Any["s", now, sum(st.sg), qs("r9")..., qs("r10")..., qs("r11")..., qs("c3")..., form(l.win, b) ? 1 : 0])
            end
        end
        if L["age"] % 100 == 0
            _push_cap!(L["hist"]["sediment"], Any[L["age"], sum(st.sg)], 600)
            _push_cap!(L["hist"]["calls"], Any[L["age"], L["callWindow"][1], L["callWindow"][2]], 600); L["callWindow"] = Any[0, 0]
        end
        if L["age"] % 1000 == 0
            _push_cap!(L["hist"]["unans"], Any[L["age"], L["unansWindow"]], 300); L["unansWindow"] = 0
        end
        pa = [m for m in o.acting if b.patch[m] <= 2]
        l.last = (y = y, acting = [b.patch[m] for m in pa], answered = [o.answered[m] for m in pa], call = o.call,
                  callAnswered = o.callAnswered, callFailed = o.callFailed, callWhileWaiting = o.callWhileWaiting, gesture = g,
                  cond = cond, formed = form(l.win, b), phase = ph)
    end
    L["active"] = copy(st.active); L["q"] = copy(st.q); L["sg"] = copy(st.sg); L["h"] = copy(st.h); L["off"] = copy(st.off)
    L["prev"] = copy(st.prev); L["pend"] = Any[pend_to(p) for p in st.pend]; L["fresh"] = copy(st.fresh)
    L["cOn"] = st.cOn === nothing ? nothing : copy(st.cOn); L["cOff"] = st.cOff === nothing ? nothing : copy(st.cOff)
    L["lastM"] = copy(st.lastM)
    return l.last
end

# What the page's buttons do (life_turn.js makeLife's methods).
set_counting!(l::Life, on::Bool) = (l.counting = on)
gesture!(l::Life, k::Integer) = (1 <= k <= P_KINDS && length(l.queue) < 4 && push!(l.queue, k); nothing)
function set_mode!(l::Life, m::String)
    p = l.L["partner"]; p["mode"] == m && return
    p["mode"] = m; p["rp"] = nothing; p["bnext"] = 0
end
clear_stats!(l::Life) = (l.L["partner"]["stats"] = emptystats(); l.L["partner"]["ignored"] = 0)
mark!(l::Life, label) = push!(l.L["session"]["marks"], Any[l.L["age"], label])
function start_auto!(l::Life)
    S = l.L["session"]; S["auto"] = Dict{String,Any}("n" => 0, "seg" => 1); push!(S["marks"], Any[l.L["age"], "1"])
    p = l.L["partner"]; p["mode"] = "live"; p["rp"] = nothing; p["bnext"] = 0
end
function stop_auto!(l::Life)
    S = l.L["session"]; A = get(S, "auto", nothing)
    if A !== nothing && A["seg"] <= 3
        A["seg"] = 9; push!(S["marks"], Any[l.L["age"], "end"]); l.L["partner"]["mode"] = "live"
    end
end
reverse_world!(l::Life) = (l.L["reversals"] += 1; apply_reversal!(l.b.perm, l.L["reversals"]))
stasis!(l::Life, n::Integer) = (l.L["stasisUntil"] = l.L["age"] + n)

# JSON form of the record as the app saves it (NaN -> null, as JSON.stringify does).
jsonable(x::AbstractFloat) = isfinite(x) ? x : nothing
jsonable(x::AbstractDict) = Dict{String,Any}(string(k) => jsonable(v) for (k, v) in x)
jsonable(x::AbstractVector) = Any[jsonable(v) for v in x]
jsonable(x::NamedTuple) = Dict{String,Any}(string(k) => jsonable(v) for (k, v) in pairs(x))
jsonable(x) = x
