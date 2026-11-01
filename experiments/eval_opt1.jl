using AgencySubstrate, Random, TOML
const AS = AgencySubstrate
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
const FX = "/Users/yamaguchimitsuyuki/bridge-protocol/tools/AgencySubstrate/fixtures"
H = 200
function run_env(s, p, yields; silenced=Set{Int}())
    st = AS.initial_state(s, p); tail = Bool[]
    for y in yields
        AS.step!(st, s, p, AS.Schedule("env", y, y, 0), silenced)
        push!(tail, !st.dead && any(u -> st.active[u] && !AS.is_sensor(s, u), 1:AS.nunits(s)))
    end
    (!st.dead && all(tail[end-4:end]), st)
end
flip(k) = [isodd(div(t - 1, k)) ? (0, 5) : (5, 0) for t in 1:H]
function randenv(seed); r = MersenneTwister(seed); g = [rand(r, 1:2) for _ in 1:cld(H, 10)]; [g[cld(t, 10)] == 1 ? (5, 0) : (0, 5) for t in 1:H]; end
envs = vcat([("flip7", flip(7)), ("flip13", flip(13))], [("rand$s", randenv(s)) for s in 1:5])
EV(s, set) = Base.invokelatest(evaluate, s, set)
aged(s, st) = AS.Substrate(s.names, s.theta, [e for (k, e) in enumerate(s.edges) if st.strength[k] > 0], s.motors, s.patch_sensors, s.resource_sensors, s.maintain, s.initial)
opt = load_templates(joinpath(@__DIR__, "designs-opt1.toml")); println("designs-opt1 sha256 ", opt.sha256)
B = load_templates(joinpath(@__DIR__, "designs-b.toml"))
mine = [(t.name, t.substrate) for t in vcat(opt.templates, B.templates)]

r0 = Dict(n => EV(s, opt) for (n, s) in mine)
println("frozen criteria: ", join([n * " L2=" * string(r0[n].agency) * " choices=" * string(r0[n].choices) for (n, _) in mine], " | "))

include(joinpath(@__DIR__, "variant_freq.jl"))
println("\n(P1) frozen templates under the frequency variant")
l3r = TOML.parsefile(joinpath(FX, "labels-repair.toml"))["L3R"]; agree = 0; total = 0
for f in ("templates.toml", "templates-adversarial.toml", "templates-adversarial-2.toml", "templates-adversarial-3.toml", "templates-adversarial-4.toml", "templates-repair.toml")
    set = load_templates(joinpath(FX, f))
    for t in set.templates
        r = EV(t.substrate, set); want = (t.L2, t.L3, something(t.L3R, get(l3r, t.name, missing)))
        got = (r.agency, r.self_producing, r.self_repairing); global total += 3; global agree += count(i -> got[i] == want[i], 1:3)
        got == want || println("  DISAGREE ", f, " ", t.name, " label=", want, " variant=", got)
    end
end
println("  agree ", agree, "/", total)

println("\n(P2-P5) my designs under the variant")
for (n, s) in mine
    r = EV(s, opt); sens = Set(u for u in 1:AS.nunits(s) if haskey(s.patch_sensors, u))
    println(n, " L2/L3/L3R=", (r.agency, r.self_producing, r.self_repairing), " differentiated=", r.differentiated, " choices=", r.choices,
        " tracking=", r.value_tracking, " needed=", r.value_needed, " hinge=", r.core_enables_action)
    res = [(en, run_env(s, opt.params, e)) for (en, e) in envs]
    println("   held-out intact:  ", join([en * "=" * (ok ? "live" : "dead") for (en, (ok, _)) in res], " "))
    println("   held-out no-sens: ", join([en * "=" * (run_env(s, opt.params, e; silenced=sens)[1] ? "live" : "dead") for (en, e) in envs], " "))
    println("   agent after 200 steps (variant, surviving edges): ", join([en * "=" * (ok ? string(EV(aged(s, st), opt).agency) : "-") for (en, (ok, st)) in res], " "))
end

println("\nrandom circuits (seed 20261009, 20,000) under the variant")
base = load_templates(); state = Ref(UInt64(20261009)); n = Dict(:agency => 0, :robust => 0, :robust_still_agent => 0)
for k in 1:20000
    s = random_substrate(state); r = EV(s, base); r.agency || continue
    n[:agency] += 1
    res = [run_env(s, base.params, e) for (_, e) in envs]
    all(first, res) || continue
    n[:robust] += 1
    all(x -> EV(aged(s, x[2]), base).agency, res) && (n[:robust_still_agent] += 1)
end
println(n)
