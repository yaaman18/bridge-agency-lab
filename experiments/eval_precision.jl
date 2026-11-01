# Usage: julia --project=.. eval_precision.jl [freq|set]   (choice measured by frequency variant or frozen set)
using AgencySubstrate, Random, TOML
const AS = AgencySubstrate
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
const FX = "/Users/yamaguchimitsuyuki/bridge-protocol/tools/AgencySubstrate/fixtures"
mode = get(ARGS, 1, "freq")
mode == "freq" && include(joinpath(@__DIR__, "variant_freq.jl"))
include(joinpath(@__DIR__, "variant_precision.jl"))
println("choice=", mode)
H = 200
function run_env(s, p, yields; silenced=Set{Int}())
    st = AS.initial_state(s, p); tail = Bool[]; poor = 0; steps = 0
    for y in yields
        AS.step!(st, s, p, AS.Schedule("env", y, y, 0), silenced)
        st.dead || (steps += 1; poor += count(m -> st.active[m] && y[s.motors[m]] < y[3 - s.motors[m]], keys(s.motors)))
        push!(tail, !st.dead && any(u -> st.active[u] && !AS.is_sensor(s, u), 1:AS.nunits(s)))
    end
    (!st.dead && all(tail[end-4:end]), st, poor / max(steps, 1))
end
flip(k, n=H) = [isodd(div(t - 1, k)) ? (0, 5) : (5, 0) for t in 1:n]
function randenv(seed); r = MersenneTwister(seed); g = [rand(r, 1:2) for _ in 1:cld(H, 10)]; [g[cld(t, 10)] == 1 ? (5, 0) : (0, 5) for t in 1:H]; end
envs = vcat([("flip7", flip(7)), ("flip13", flip(13))], [("rand$s", randenv(s)) for s in 1:5],
            [("fast-then-slow", vcat(flip(7, 70), flip(60, 130))), ("const-p1", fill((5, 0), H))])
EV(s, set) = Base.invokelatest(evaluate, s, set)
function aged_differentiated(s, st, set)
    modal = map(set.choice) do sch
        x = deepcopy(st); x.resource = set.choice_params.resource0; x.t = 0
        cnt = Dict(m => 0 for m in keys(s.motors))
        for t in 1:last(set.choice_window)
            AS.step!(x, s, set.choice_params, sch, Set{Int}())
            t in set.choice_window && for m in keys(s.motors); x.active[m] && (cnt[m] += 1); end
        end
        b = maximum(values(cnt)); b == 0 ? Set{Int}() : Set(m for (m, c) in cnt if c == b)
    end
    modal[1] != modal[2]
end
sets = Dict(f => load_templates(joinpath(FX, f)) for f in ("templates.toml", "templates-adversarial.toml", "templates-adversarial-2.toml",
            "templates-adversarial-3.toml", "templates-adversarial-4.toml", "templates-repair.toml"))
l3r = TOML.parsefile(joinpath(FX, "labels-repair.toml"))["L3R"]
for explore in (true, false)
    AS.EXPLORE[] = explore
    println("\n======== EXPLORE = ", explore, " ========")
    agree = 0; total = 0
    for (f, set) in sort(collect(sets); by=first), t in set.templates
        r = EV(t.substrate, set); want = (t.L2, t.L3, something(t.L3R, get(l3r, t.name, missing)))
        got = (r.agency, r.self_producing, r.self_repairing); total += 3; agree += count(i -> got[i] == want[i], 1:3)
        got == want || println("  DISAGREE ", f, " ", t.name, " label=", want, " got=", got)
    end
    println("(V1) frozen templates agree ", agree, "/", total)
    mine = load_templates(joinpath(@__DIR__, "designs.toml"))
    pool = vcat([(t.name, t.substrate, mine) for t in mine.templates if t.name == "selfloop-pair-agent"],
                [(t.name, t.substrate, sets["templates.toml"]) for t in sets["templates.toml"].templates],
                [(t.name, t.substrate, sets["templates-repair.toml"]) for t in sets["templates-repair.toml"].templates if t.name == "repairing-agent"])
    for (n, s, set) in pool
        r = EV(s, set); sens = Set(u for u in 1:AS.nunits(s) if haskey(s.patch_sensors, u))
        println(n, "  L2/L3/L3R=", (r.agency, r.self_producing, r.self_repairing), " choices=", r.choices)
        mode == "freq" || continue
        for (en, e) in envs
            ok, st, poor = run_env(s, set.params, e)
            println("   ", rpad(en, 15), ok ? "live" : "dead", "  poor=", round(poor; digits=2),
                isempty(sens) ? "" : "  no-sens=" * (run_env(s, set.params, e; silenced=sens)[1] ? "live" : "dead"),
                "  diff-after=", ok ? aged_differentiated(s, st, set) : "-")
        end
    end
    mode == "freq" || continue
    base = load_templates(); state = Ref(UInt64(20261009)); c = Dict(:agency => 0, :robust => 0, :robust_still => 0)
    for k in 1:20000
        x = random_substrate(state); rr = EV(x, base); rr.agency || continue
        c[:agency] += 1; res = [run_env(x, base.params, e) for (_, e) in envs[1:7]]
        all(first, res) || continue
        c[:robust] += 1; all(q -> aged_differentiated(x, q[2], base), res) && (c[:robust_still] += 1)
    end
    println("(V7) random: ", c)
end
