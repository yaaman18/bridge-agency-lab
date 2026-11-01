# The check scenarios of js_scenarios.js, run on the canonical Julia rules; writes core/check/out/jl-<name>.json with
# 0-based indices like the JavaScript side. Usage: julia --project=. core/check/jl_scenarios.jl [name ...]
include(joinpath(@__DIR__, "..", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
const LAB = normpath(joinpath(@__DIR__, "..", ".."))
const OUT = joinpath(@__DIR__, "out"); mkpath(OUT)
parsej(s) = JSON.parse(s; dicttype = Dict{String,Any})
rt(x) = parsej(JSON.json(jsonable(x)))
function load_being(f)
    d = parsej(read(joinpath(LAB, "memory", "backup", f), String)); haskey(d, "data") ? d["data"] : d
end
writeout(name, x) = write(joinpath(OUT, "jl-$name.json"), JSON.json(jsonable(x)))
z(v) = [i - 1 for i in v]   # 1-based -> 0-based

# ---- circuit ----
function circuit_run(partner, contrast, variant, steps; scarce = false)
    b = newborn(partner); st = init(b); noise = Mulberry(7); gr = Mulberry(99); m1 = LC.unit(b, "m1")
    R = [50.0, 50.0]; wt = 0; trace = Any[]; win = Any[]
    for t in 0:steps-1
        t == 3000 && cross!(b.perm)
        sil = 2000 <= t < 2100 ? Set([5, m1]) : Set{Int}()
        y = t < 400 ? ((t ÷ 50) % 2 == 0 ? [5.0, 0.0] : [0.0, 5.0]) : t < 800 ? (((t - 400) ÷ 15) % 2 == 0 ? [5.0, 2.0] : [2.0, 5.0]) :
            [min(R[1], 5.0), min(R[2], 5.0)]
        g = partner ? (gr() < 0.1 ? 1 + floor(Int, gr() * 4) : 0) : 0
        o = step!(st, b, [y; g]; noise = noise, contrast = contrast, sil = sil, variant...)
        if t >= 800; wt += 1; s = scarce && wt % 3 != 0 ? [0.0, 0.0] : LC.life_season(wt); R = [min(50.0, R[k] - o.d[k] + s[k]) for k in 1:2]; end
        push!(win, (active = copy(st.active), q = copy(st.q))); length(win) > 5 && popfirst!(win)
        push!(trace, Any[z(o.acting), o.d, Int(o.gate), Int(o.call), Int(o.callAnswered), o.callFailed, Int(o.callWhileWaiting),
                         sum(st.q), sum(st.sg), sum(st.h), Int(form(win, b))])
    end
    Dict("trace" => trace, "final" => Dict("q" => st.q, "sg" => st.sg, "h" => st.h, "off" => st.off, "active" => st.active, "prev" => st.prev,
         "pend" => [LC.pend_to(p) for p in st.pend], "fresh" => st.fresh, "cOn" => st.cOn, "cOff" => st.cOff,
         "lastM" => st.lastM, "t" => st.t))
end
const SC = Dict{String,Function}()
for c in (nothing, :sed, :learn, :learn2, :learn3, :bin3, :donly)
    SC["circuit-$(c === nothing ? "null" : c)-p"] = () -> circuit_run(true, c, (;), 6000)
end
for c in (nothing, :bin3); SC["circuit-$(c === nothing ? "null" : c)-np"] = () -> circuit_run(false, c, (;), 6000); end
for v in (:memory, :orient, :explore, :fail); SC["circuit-null-no$v"] = () -> circuit_run(true, nothing, NamedTuple{(v,)}((false,)), 6000); end
SC["circuit-bin3-nomemory"] = () -> circuit_run(true, :bin3, (memory = false,), 6000)
for c in (nothing, :bin3); SC["circuit-$(c === nothing ? "null" : c)-idle-p"] = () -> circuit_run(true, c, (idle_first = true,), 6000); end
SC["circuit-bin3-idle-np"] = () -> circuit_run(false, :bin3, (idle_first = true,), 6000)
SC["circuit-bin3-idle-scarce"] = () -> circuit_run(true, :bin3, (idle_first = true,), 6000; scarce = true)
for c in (:bin3, :learn3, :learn2, :sed, :learn); SC["circuit-$c-scarce"] = () -> circuit_run(true, c, (;), 6000; scarce = true); end

# ---- life ----
function life_run(start, steps, script; rule = "bin3")
    l = start === nothing ? makelife(LC.freshlife(born = 0); rule) : makelife(start; rule)
    set_counting!(l, true); trace = Any[]
    for i in 1:steps
        for (at, f) in script
            at == i || continue
            if f == :reload; l = makelife(rt(l.L); rule); set_counting!(l, true); else f(l); end
        end
        live!(l, 1); push!(trace, l.last)
    end
    Dict("trace" => trace, "L" => l.L)
end
const SCRIPT = Any[]
for i in 37:37:6000; push!(SCRIPT, (i, l -> gesture!(l, 1 + (i % 4)))); end
append!(SCRIPT, [(300, start_auto!), (2000, reverse_world!), (2500, l -> stasis!(l, 150)), (3000, :reload),
                 (4600, stop_auto!), (4700, l -> set_mode!(l, "blind")), (5200, l -> mark!(l, "x")), (5500, clear_stats!)])
SC["life-age86642"] = () -> life_run(rt(load_being("being-state-pre-learn3-age86642.json")), 6000, SCRIPT)
SC["life-v513"] = () -> life_run(rt(load_being("being-state-session2-v513.json")), 3000, SCRIPT)
SC["life-v438-blind"] = () -> life_run(rt(load_being("being-state-session-v438.json")), 3000, SCRIPT)
SC["life-fresh"] = () -> life_run(nothing, 3000, SCRIPT)
SC["life-from-v34"] = () -> life_run(parsej(read(joinpath(OUT, "state-v34-after3000.json"), String)), 2000, SCRIPT)
# the app's rule since v3.7 (bin3+idle, item 73): compared with the Rust copy only (the JavaScript copies are v3.5)
const IR = LC.RULE_NAME
SC["life-age86642-idle"] = () -> life_run(rt(load_being("being-state-pre-learn3-age86642.json")), 6000, SCRIPT; rule = IR)
SC["life-v513-idle"] = () -> life_run(rt(load_being("being-state-session2-v513.json")), 3000, SCRIPT; rule = IR)
SC["life-v438-blind-idle"] = () -> life_run(rt(load_being("being-state-session-v438.json")), 3000, SCRIPT; rule = IR)
SC["life-fresh-idle"] = () -> life_run(nothing, 3000, SCRIPT; rule = IR)
SC["life-from-v34-idle"] = () -> life_run(parsej(read(joinpath(OUT, "state-v34-after3000.json"), String)), 2000, SCRIPT; rule = IR)
SC["life-v528-idle"] = () -> life_run(rt(parsej(read(joinpath(LAB, "audit", "in", "state-v528.json"), String))), 3000, SCRIPT; rule = IR)

# ---- matter ----
world_out(w) = Dict("A" => w.A, "B" => w.B, "C" => Int.(w.C), "K" => [Any[k...] for k in w.K], "reservoir" => w.port.reservoir,
                    "inflow" => w.port.inflow, "outflow" => w.port.outflow, "born" => w.born, "died" => w.died, "t" => w.t)
net_out(c) = c === nothing ? nothing : Dict("Wz" => c.Wz, "Wx" => c.Wx, "Wn" => c.Wn, "b" => c.b, "Wy" => c.Wy, "wa" => c.wa, "ba" => c.ba,
    "wp" => c.wp, "z" => c.z, "y" => c.y, "err" => c.err, "line" => c.line)
function matter32(spont)
    w = make_world(; spontaneous = spont); seed!(w, 12, 12, 1); logv = Any[]
    for t in 0:1999
        src = (spont && 300 <= t < 900) ? Tuple{Int,Float64}[] : LC.evo_sources(w, t)
        LC.step!(w, src)
        t % 100 == 99 && push!(logv, Any[total(w), count_matter(w).constituents, count_matter(w).bound])
    end
    Dict("log" => logv, "world" => world_out(w))
end
function evo_run(mode, seed, steps, srcf; stats = true, hooks = false, kw...)
    divs = Any[]; deaths = Any[]
    hk = hooks ? (divide = (i, j) -> push!(divs, [i - 1, j - 1]), death = i -> push!(deaths, i - 1)) : (;)
    L = make_evo(mode, seed; hooks = hk, kw...); logv = Any[]
    for t in 0:steps-1
        LC.step!(L, srcf(L.w, t)); (stats && t % 100 == 99) && push!(logv, evo_stats(L))
    end
    Dict("log" => logv, "world" => world_out(L.w), "act" => L.act, "net" => [net_out(c) for c in L.net], "divs" => divs, "deaths" => deaths)
end
const S48 = [(8, 12), (24, 12), (40, 12), (8, 36), (24, 36), (40, 36), (8, 4), (24, 4), (40, 44)]
const P48 = [(8, 8), (24, 8), (40, 8), (8, 40), (24, 40), (40, 40)]
function src48(w, t)
    rich = (t ÷ 500) % 2 == 0
    [((cy + dy) * 48 + cx + dx + 1, (rich ? 1.0 : 0.3) * w.p.SRC * 0.5) for (cx, cy) in P48 for dy in -1:1 for dx in -1:1]
end
fsrc(scale, starve = nothing) = (w, t) -> evo_sources(w, t; scale = scale, starve = starve)
SC["matter32"] = () -> matter32(false); SC["matter32-spont"] = () -> matter32(true)
SC["trm33"] = () -> evo_run("trm", 2, 1000, fsrc(1.0); stats = false, wp = false, lineage = false)
SC["trm35-predact"] = () -> evo_run("predact", 2, 1000, fsrc(1.0); stats = false, lineage = false)
SC["evo-48-trm"] = () -> evo_run("trm", 1, 600, src48; hooks = true, W = 48, H = 48, reservoir = 1200, seeds = S48)
SC["evo-48-predact"] = () -> evo_run("predact", 1, 600, src48; W = 48, H = 48, reservoir = 1200, seeds = S48)
SC["evo-nogate-actgate0-bind"] = () -> evo_run("nogate", 4, 1500, fsrc(1.0); hooks = true, actGate = 0, bindConst = 0.5)
SC["evo-trm-starve"] = () -> evo_run("trm", 5, 1500, fsrc(2.0, (300, 700)))
for m in ("fixed", "trm", "nogate", "noinherit", "predact", "frozen"); SC["evo-$m"] = () -> evo_run(m, 3, 1500, fsrc(1.0)); end

# ---- body_org ----
function body_runs(list)
    out = Any[]
    for (cond, seed, o, rep) in list
        push!(out, body_org_run(cond, seed, o, rep === nothing ? nothing : out[rep+1]["acts"]))
    end
    out
end
const BASE = (U = 0.02, MCOST = 0.004, STEPS = 3000)
SC["body-base"] = () -> body_runs([("ORG", 1, BASE, nothing), ("REPLAY", 1, BASE, 0), ("NONE", 1, BASE, nothing), ("GREEDY", 1, BASE, nothing),
                                   ("ORG", 2, merge(BASE, (REV = 1500,)), nothing)])
SC["body-bin3-full"] = () -> body_runs([("ORG", 3, merge(BASE, (CONTRAST = "bin3", FEED = true, RAISE = "body", PER = 4, KC = 0.0005, PHASE = 37, REV = 1500, REVR = 2000)), nothing),
                                        ("GREEDY", 3, merge(BASE, (KC = 0.0005, REVR = 2000, FEED = true)), nothing)])
SC["body-learn3-drop"] = () -> body_runs([("ORG", 4, merge(BASE, (CONTRAST = "learn3", FEED = true, DROPR = ["r5", "r6"], PHASE = 11)), nothing)])
SC["body-rules"] = () -> body_runs([("ORG", 5, merge(BASE, (STEPS = 2000, CONTRAST = c, KC = 0.0002)), nothing) for c in ("learn2", "sed", "learn", "donly")])

names = isempty(ARGS) ? sort(collect(keys(SC))) : ARGS
for n in names
    t0 = time(); writeout(n, SC[n]()); println(n, " ", round(Int, (time() - t0) * 1000), " ms")
end
