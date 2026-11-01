using AgencySubstrate
const AS = AgencySubstrate
for f in ("variant_freq.jl", "variant_digest.jl", "variant_digest_repair.jl", "variant_tracking_sets.jl", "variant_direction.jl", "variant_attention.jl", "variant_select.jl")
    include(joinpath(@__DIR__, f))
end
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
include(joinpath(@__DIR__, "env_digest_wta.jl"))
EV(s, set) = Base.invokelatest(evaluate, s, set)
function main()
    println("ATTN_MODE = ", AS.ATTN_MODE[])
    set = load_templates(joinpath(@__DIR__, "templates-digest.toml")); base = load_templates(); p = base.params
    a = 0; n = 0
    for t in set.templates
        r = EV(t.substrate, set); want = (t.L2, t.L3, t.L3R); got = (r.agency, r.self_producing, r.self_repairing)
        a += count(i -> got[i] == want[i], 1:3); n += 3
        got == want || println("   DISAGREE ", rpad(t.name, 24), " label=", want, " got=", got, " choices=", r.choices)
    end
    println("X1 templates-digest: ", a, "/", n)
    for nm in ("selfloop-pair-agent", "agent", "triangle-agent", "hub-agent", "omnivore", "alternator", "reflex")
        s = only(t for t in set.templates if t.name == nm).substrate
        log = run_world(s, p, 1000)
        m1 = findfirst(==("m1"), s.names)
        sf = m1 === nothing ? Int[] : [t for t in 2:1000 if log[t].active[m1] && all(k -> log[t-1].strength[k] == 0, [k for (k, (_, d, _)) in enumerate(s.edges) if d == m1])]
        println("X2/X4 world ", rpad(nm, 22), "form ", count(t -> formed(s, log, t, p.alive_window), 1:1000), "/1000  stale m1 firing: ", isempty(sf) ? "none" : sf[1:min(3, end)])
    end
    state = Ref(UInt64(20261009)); na = 0
    for k in 1:20000; x = random_substrate(state); EV(x, base).agency && (na += 1); end
    println("X3 random agents with direction: ", na)
    s = only(t for t in set.templates if t.name == "selfloop-pair-agent").substrate
    T0S = [50, 100, 150, 200, 250, 350, 450, 550, 650, 750, 850]; worst = 0
    for u in 1:AS.nunits(s), k in (1, 3, 10, 30)
        dead = count(t0 -> !formed(s, run_world(s, p, 1000; sil=t -> t0 <= t < t0 + k ? Set([u]) : Set{Int}()), 1000, p.alive_window), T0S)
        dead > 0 && println("   X5 silence ", s.names[u], " ", k, ": no form at 1000 in ", dead, "/11")
        worst = max(worst, dead)
    end
    println("X5 worst: ", worst, "/11")
end
main()
