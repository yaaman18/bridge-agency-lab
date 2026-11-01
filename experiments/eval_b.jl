using AgencySubstrate, Random
const AS = AgencySubstrate
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
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

set = load_templates(joinpath(@__DIR__, "designs-b.toml")); p = set.params
println("sha256 ", set.sha256)
for t in set.templates
    r = evaluate(t.substrate, set)
    println(t.name, " pred=", (t.L2, t.L3, t.L3R), " got=", (r.agency, r.self_producing, r.self_repairing),
        (r.agency, r.self_producing, r.self_repairing) == (t.L2, t.L3, t.L3R) ? " MATCH" : " MISMATCH")
    println("   core=", r.core, " hinge=", r.core_enables_action, " differentiated=", r.differentiated, " choices=", r.choices,
        " tracking=", r.value_tracking, " needed=", r.value_needed, " surv=", r.survival, " surv_wo=", r.survival_without_tracking)
    s = t.substrate; sens = Set(u for u in 1:AS.nunits(s) if haskey(s.patch_sensors, u))
    println("   held-out intact:  ", join([n * "=" * (run_env(s, p, e)[1] ? "live" : "dead") for (n, e) in envs], " "))
    println("   held-out no-sens: ", join([n * "=" * (run_env(s, p, e; silenced=sens)[1] ? "live" : "dead") for (n, e) in envs], " "))
end

println("\n== the one random circuit that was both agent and robust (k=3123): does it stay an agent? ==")
state = Ref(UInt64(20261009)); s = nothing
for k in 1:3123; global s = random_substrate(state); end
base = load_templates()
for (n, e) in envs[3:4]
    ok, st = run_env(s, base.params, e)
    println(n, " alive=", ok, " final strengths=", [string(s.names[a], "->", s.names[b], "(", w, ")=", st.strength[k]) for (k, (a, b, w)) in enumerate(s.edges)])
    # rebuild the circuit with the structure it has after 200 steps (edges at 0 removed) and re-evaluate
    s2 = AS.Substrate(s.names, s.theta, [e for (k, e) in enumerate(s.edges) if st.strength[k] > 0], s.motors, s.patch_sensors, s.resource_sensors, s.maintain, s.initial)
    r = evaluate(s2, base)
    println("   re-evaluated with surviving edges: agency=", r.agency, " differentiated=", r.differentiated, " choices=", r.choices, " needed=", r.value_needed)
end
