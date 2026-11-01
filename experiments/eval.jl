using AgencySubstrate, Random
const AS = AgencySubstrate
const FX = "/Users/yamaguchimitsuyuki/bridge-protocol/tools/AgencySubstrate/fixtures"

println("== A: Claude designs vs pre-frozen predictions ==")
set = load_templates(joinpath(@__DIR__, "designs.toml"))
println("sha256 ", set.sha256)
for t in set.templates
    r = evaluate(t.substrate, set)
    ok = (r.agency, r.self_producing, r.self_repairing) == (t.L2, t.L3, t.L3R)
    println(rpad(t.name, 24), " pred L2/L3/L3R=", (t.L2, t.L3, t.L3R), " got=", (r.agency, r.self_producing, r.self_repairing),
            ok ? "  MATCH" : "  MISMATCH", "  core=", r.core, " tracking=", r.value_tracking, " alive=", r.alive_somewhere)
end

println("\n== B: held-out environments (not in the frozen schedules), horizon 200 ==")
# per-step yields; a Schedule with switch=0 always returns `second`, so step! is driven step by step
function survive_env(s, p, yields; silenced=Set{Int}())
    st = AS.initial_state(s, p); tail = Bool[]
    for (t, y) in enumerate(yields)
        AS.step!(st, s, p, AS.Schedule("env", y, y, 0), silenced)
        push!(tail, !st.dead && any(u -> st.active[u] && !AS.is_sensor(s, u), 1:AS.nunits(s)))
    end
    !st.dead && all(tail[end-4:end])
end
flip(k, a, b, H) = [isodd(div(t - 1, k)) ? b : a for t in 1:H]
rng = MersenneTwister(20261029)
randenv(H) = (g = [rand(rng, 1:2) for _ in 1:cld(H, 10)]; [g[cld(t, 10)] == 1 ? (5, 0) : (0, 5) for t in 1:H])
H = 200
envs = [("flip7", flip(7, (5, 0), (0, 5), H)), ("flip13", flip(13, (5, 0), (0, 5), H)),
        ("random10", randenv(H)), ("flip7-weak4", flip(7, (4, 0), (0, 4), H)), ("both3", fill((3, 3), H))]
base = load_templates(); rep = load_templates(joinpath(FX, "templates-repair.toml"))
pool = [(t.name, t.substrate) for t in vcat(set.templates, base.templates, rep.templates)
        if t.name in ("selfloop-pair-agent", "hub-agent", "redundant-sensor-agent", "repairing-agent", "agent", "reflex", "thermostat", "alternator", "no-loop")]
p = base.params
println(rpad("", 24), join(rpad.(first.(envs), 12)))
for (n, s) in pool
    sensors = Set(u for u in 1:AS.nunits(s) if haskey(s.patch_sensors, u))
    row = [string(survive_env(s, p, e) ? "live" : "dead", isempty(sensors) ? "" : survive_env(s, p, e; silenced=sensors) ? "/S:live" : "/S:dead") for (_, e) in envs]
    println(rpad(n, 24), join(rpad.(row, 12)))
end
println("(x/S:y = intact x, with patch sensors silenced y)")
