using AgencySubstrate, Random
const AS = AgencySubstrate
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
aged(s, st) = AS.Substrate(s.names, s.theta, [e for (k, e) in enumerate(s.edges) if st.strength[k] > 0], s.motors, s.patch_sensors, s.resource_sensors, s.maintain, s.initial)
EV(s, set) = Base.invokelatest(evaluate, s, set)
ad = load_templates(joinpath(@__DIR__, "designs-adapt.toml")); println("designs-adapt sha256 ", ad.sha256)
pool = vcat([(t.name, t.substrate) for t in ad.templates],
            [(t.name, t.substrate) for t in load_templates(joinpath(@__DIR__, "designs-opt1.toml")).templates],
            [(t.name, t.substrate) for t in load_templates(joinpath(@__DIR__, "designs.toml")).templates if t.name == "selfloop-pair-agent"])
r0 = EV(pool[1][2], ad); println("frozen criteria satiety-rehearsal: L2/L3/L3R=", (r0.agency, r0.self_producing, r0.self_repairing), " choices=", r0.choices)
include(joinpath(@__DIR__, "variant_freq.jl"))
for (n, s) in pool
    r = EV(s, ad); sens = Set(u for u in 1:AS.nunits(s) if haskey(s.patch_sensors, u))
    println("\n", n, "  variant L2/L3/L3R=", (r.agency, r.self_producing, r.self_repairing), " choices=", r.choices, " tracking=", r.value_tracking, " needed=", r.value_needed)
    for (en, e) in envs
        ok, st, poor = run_env(s, ad.params, e)
        println("   ", rpad(en, 15), ok ? "live" : "dead", "  poor-motor share=", round(poor; digits=2),
            "  no-sens=", run_env(s, ad.params, e; silenced=sens)[1] ? "live" : "dead",
            "  agent-after=", ok ? EV(aged(s, st), ad).agency : "-")
    end
end
