using AgencySubstrate
const AS = AgencySubstrate
include(joinpath(@__DIR__, "variant_freq.jl"))
include(joinpath(@__DIR__, "variant_digest.jl"))
include(joinpath(@__DIR__, "env_digest.jl"))
EV(s, set) = Base.invokelatest(evaluate, s, set)
base = load_templates(); p = base.params
mine = load_templates(joinpath(@__DIR__, "designs.toml"))
agent = only(t for t in mine.templates if t.name == "selfloop-pair-agent").substrate
println("== D1-D3 criteria under the digestion reading")
for (n, s, set) in vcat([("selfloop-pair-agent", agent, mine)], [(t.name, t.substrate, base) for t in base.templates])
    r = EV(s, set)
    println(rpad(n, 22), "L2=", r.agency, " L3=", r.self_producing, "  core=", r.core, " diff=", r.differentiated, " needed=", r.value_needed,
        " surv=", r.survival, " surv_wo=", r.survival_without_tracking)
end
mot(s, st) = (a = [s.motors[m] for m in keys(s.motors) if st.active[m]]; isempty(a) ? 0 : length(a) == 2 ? 3 : a[1])
switches(s, log, r) = (x = filter(h -> h in (1, 2), [mot(s, log[t]) for t in r]); count(i -> x[i] != x[i - 1], 2:length(x)))
stale_fire(s, log) = [(t, s.names[m]) for t in 2:length(log) for m in keys(s.motors)
    if log[t].active[m] && (ins = [k for (k, (_, d, _)) in enumerate(s.edges) if d == m]; all(k -> log[t - 1].strength[k] == 0, ins))]
println("\n== D4-D5 world, 1000 steps")
for (n, s) in [("selfloop-pair-agent", agent), [(t.name, t.substrate) for t in base.templates if t.name in ("agent", "static-agent", "reflex", "alternator", "no-loop")]...]
    for consume in (true, false)
        CONSUME[] = consume; (!consume && n != "selfloop-pair-agent") && continue
        log = run_world(s, p, 1000)
        f = count(t -> formed(s, log, t, p.alive_window), 1:1000)
        sf = stale_fire(s, log)
        println(rpad(n * (consume ? "" : " [CONSUME off]"), 34), "form ", f, "/1000  at1000=", formed(s, log, 1000, p.alive_window),
            "  switches s1/s2/s3=", switches(s, log, 1:300), "/", switches(s, log, 301:600), "/", switches(s, log, 601:1000),
            "  stale-firing=", isempty(sf) ? "none" : string(sf[1:min(4, end)]) * (length(sf) > 4 ? " ...($(length(sf)))" : ""))
    end
end
CONSUME[] = true
println("\n== D6 battery (dead = no form at step 1000; lost = form absent at some step after the perturbation)")
T0S = [50, 100, 150, 200, 250, 350, 450, 550, 650, 750, 850]
function judge(log, t0)
    (count(t -> !formed(agent, log, t, p.alive_window), t0:1000), formed(agent, log, 1000, p.alive_window))
end
rows = Tuple{String,Int,Int}[]
for u in 1:AS.nunits(agent), k in (1, 3, 10, 30)
    res = [judge(run_world(agent, p, 1000; sil=t -> t0 <= t < t0 + k ? Set([u]) : Set{Int}()), t0) for t0 in T0S]
    push!(rows, ("silence $(agent.names[u]) $k", count(r -> r[1] > 0, res), count(r -> !r[2], res)))
end
for k in (10, 30, 60)
    res = [judge(run_world(agent, p, 1000; stasis=t -> t0 <= t < t0 + k), t0) for t0 in T0S]
    push!(rows, ("stasis $k", count(r -> r[1] > 0, res), count(r -> !r[2], res)))
end
res = [judge(run_world(agent, p, 1000; wipe=t -> t == t0), t0) for t0 in T0S]
push!(rows, ("wipe", count(r -> r[1] > 0, res), count(r -> !r[2], res)))
for (k, lost, dead) in rows; (lost > 0 || dead > 0) && println("   ", rpad(k, 20), "form lost in ", lost, "/11, no form at 1000 in ", dead, "/11"); end
println("   (perturbations not listed: form never lost)")
println("\n== D7 ablations after stasis 60 (start times as above)")
for (lab, f) in [("EXPLORE off", () -> AS.EXPLORE[] = false), ("DIGEST_GATE off", () -> AS.DIGEST_GATE[] = false)]
    AS.EXPLORE[] = true; AS.DIGEST_GATE[] = true; f()
    res = [judge(run_world(agent, p, 1000; stasis=t -> t0 <= t < t0 + 60), t0) for t0 in T0S]
    println("   ", rpad(lab, 18), "form lost in ", count(r -> r[1] > 0, res), "/11, no form at 1000 in ", count(r -> !r[2], res), "/11")
end
AS.EXPLORE[] = true; AS.DIGEST_GATE[] = true
println("\n== D8 both patch sensors silenced for the whole run")
sens = Set(u for u in 1:AS.nunits(agent) if haskey(agent.patch_sensors, u))
log = run_world(agent, p, 1000; sil=t -> sens)
println("   form at 1000: ", formed(agent, log, 1000, p.alive_window), "   first step without form: ", something(findfirst(t -> !formed(agent, log, t, p.alive_window), 1:1000), "-"))
