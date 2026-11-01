using AgencySubstrate, TOML, Printf
const AS = AgencySubstrate
const FX = "/Users/yamaguchimitsuyuki/bridge-protocol/tools/AgencySubstrate/fixtures"
include(joinpath(@__DIR__, "variant_freq.jl"))
include(joinpath(@__DIR__, get(ENV, "WORLD_VARIANT", "variant_precision.jl")))
include(joinpath(@__DIR__, "env_deplete.jl"))
EV(s, set) = Base.invokelatest(evaluate, s, set)

# W0
l3r = merge(TOML.parsefile(joinpath(FX, "labels-repair.toml"))["L3R"], TOML.parsefile(joinpath(@__DIR__, "labels-precision.toml"))["L3R"])
agree = 0; total = 0
for f in ("templates.toml", "templates-adversarial.toml", "templates-adversarial-2.toml", "templates-adversarial-3.toml", "templates-adversarial-4.toml", "templates-repair.toml")
    set = load_templates(joinpath(FX, f))
    for t in set.templates
        r = EV(t.substrate, set); L3R = haskey(l3r, t.name) ? l3r[t.name] : t.L3R
        want = (t.L2, t.L3, L3R); got = (r.agency, r.self_producing, r.self_repairing)
        global total += 3; global agree += count(i -> got[i] == want[i], 1:3)
        got == want || println("  DISAGREE ", t.name, " ", want, " ", got)
    end
end
println("W0 frozen templates with relabel: ", agree, "/", total)

base = load_templates(); p = base.params
mine = load_templates(joinpath(@__DIR__, "designs.toml"))
pool = vcat([(t.name, t.substrate) for t in mine.templates if t.name == "selfloop-pair-agent"],
            [(t.name, t.substrate) for t in base.templates if t.name in ("agent", "static-agent", "reflex", "thermostat", "alternator")])
patch_of(s, m) = s.motors[m]
for explore in (true, false), (n, s) in pool
    AS.EXPLORE[] = explore
    (!explore && n != "selfloop-pair-agent") && continue
    log = live_in_world(s, p, 1000)
    last_t = last(log).t; died = last(log).dead
    # which patch is harvested at each step (0 none, 1, 2, 3 both)
    hp = [(any(m -> l.active[m] && s.motors[m] == 1, keys(s.motors)) ? 1 : 0) + (any(m -> l.active[m] && s.motors[m] == 2, keys(s.motors)) ? 2 : 0) for l in log]
    L = length(hp)
    sw(r) = (x = filter(h -> h in (1, 2), hp[r]); count(i -> x[i] != x[i - 1], 2:length(x)))
    stale = [(l.t, s.names[m]) for l in log for m in keys(s.motors)
             if l.active[m] && (ins = [k for (k, (_, d, _)) in enumerate(s.edges) if d == m]; !isempty(ins) && all(k -> l.before[k] == 0, ins))]
    res = [l.resource for l in log]
    seg(a, b) = (r = filter(l -> a <= l.t <= b, log); isempty(r) ? "-" : @sprintf("%.1f", sum(l -> l.resource, r) / length(r)))
    println(rpad(n * (explore ? "" : " [EXPLORE off]"), 34), died ? "DIED at $last_t" : "alive at $last_t",
        "  mean store s1/s2/s3=", seg(1, 300), "/", seg(301, 600), "/", seg(601, 1000),
        "  switches s1/s2/s3=", sw(1:min(300, L)), "/", L > 300 ? sw(301:min(600, L)) : "-", "/", L > 600 ? sw(601:L) : "-",
        "  stale-firing=", isempty(stale) ? "none" : string(stale[1:min(6, end)]), length(stale) > 6 ? " ...($(length(stale)))" : "")
end

# W7: sensitivity of sensing to action, season 1 only (steps 1-300), source silencing of each motor
AS.EXPLORE[] = true
println("\nW7 sensitivity (change in sensor firing rate, steps 1-300, when a motor is silenced for the whole run)")
for (n, s) in pool
    sensors = sort([u for u in keys(s.patch_sensors)]); isempty(sensors) && (println(rpad(n, 22), "no patch sensors"); continue)
    rate(log, u) = (r = filter(l -> l.t <= 300 && !l.dead, log); isempty(r) ? NaN : count(l -> l.active[u], r) / length(r))
    intact = live_in_world(s, p, 300)
    row = String[]
    for m in sort(collect(keys(s.motors)))
        sil = live_in_world(s, p, 300; silenced=Set([m]))
        for u in sensors
            push!(row, @sprintf("%s|%s: %+.2f (alive %d)", s.names[u], s.names[m], rate(sil, u) - rate(intact, u), last(sil).dead ? last(sil).t : 300))
        end
    end
    println(rpad(n, 22), join(row, "   "))
end
