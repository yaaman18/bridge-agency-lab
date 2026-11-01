using AgencySubstrate, Random
const AS = AgencySubstrate
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
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
# Behavioural agency after aging: continue from the aged state (its own connection strengths) with
# abundant resource under the two choice schedules; differentiated if the modal motors differ.
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
include(joinpath(@__DIR__, "variant_freq.jl"))
ad = load_templates(joinpath(@__DIR__, "designs-adapt2.toml")); println("designs-adapt2 sha256 ", ad.sha256)
s = ad.templates[1].substrate
ad_frozen_choice = nothing
r = EV(s, ad); sens = Set(u for u in 1:AS.nunits(s) if haskey(s.patch_sensors, u))
println("variant L2/L3/L3R=", (r.agency, r.self_producing, r.self_repairing), " core=", r.core, " hinge=", r.core_enables_action,
    " choices=", r.choices, " tracking=", r.value_tracking, " needed=", r.value_needed, " surv=", r.survival)
for (en, e) in envs
    ok, st, poor = run_env(s, ad.params, e)
    println("   ", rpad(en, 15), ok ? "live" : "dead", "  poor-motor share=", round(poor; digits=2),
        "  no-sens=", run_env(s, ad.params, e; silenced=sens)[1] ? "live" : "dead",
        "  differentiated-after=", ok ? aged_differentiated(s, st, ad) : "-")
end
println("\nre-check of earlier claims with the behavioural test (variant):")
for (f, n) in [("designs.toml", "selfloop-pair-agent"), ("designs-opt1.toml", "alternating-rehearsal")]
    set = load_templates(joinpath(@__DIR__, f)); x = only(t for t in set.templates if t.name == n).substrate
    println(n, ": ", join([en * "=" * (begin ok, st, _ = run_env(x, set.params, e); ok ? string(aged_differentiated(x, st, set)) : "-" end) for (en, e) in envs], " "))
end
base = load_templates(); state = Ref(UInt64(20261009)); n = Dict(:agency => 0, :robust => 0, :robust_still => 0); k3123 = ""
for k in 1:20000
    x = random_substrate(state); rr = EV(x, base); rr.agency || continue
    n[:agency] += 1; res = [run_env(x, base.params, e) for (_, e) in envs[1:7]]
    all(first, res) || continue
    n[:robust] += 1; still = all(q -> aged_differentiated(x, q[2], base), res); still && (n[:robust_still] += 1)
end
println("random (variant, 7 held-out envs): ", n)
state = Ref(UInt64(20261009)); x = nothing; for k in 1:3123; global x = random_substrate(state); end
println("random k=3123 (frozen-criteria robust agent): ", join([en * "=" * (begin ok, st, _ = run_env(x, base.params, e); ok ? string(aged_differentiated(x, st, base)) : "-" end) for (en, e) in envs[1:7]], " "))
