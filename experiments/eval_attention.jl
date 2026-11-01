using AgencySubstrate
const AS = AgencySubstrate
for f in ("variant_freq.jl", "variant_digest.jl", "variant_digest_repair.jl", "variant_tracking_sets.jl", "variant_direction.jl", "variant_attention.jl")
    include(joinpath(@__DIR__, f))
end
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
include(joinpath(@__DIR__, "env_digest_wta.jl"))
EV(s, set) = Base.invokelatest(evaluate, s, set)
function main()
    set = load_templates(joinpath(@__DIR__, "templates-digest.toml")); base = load_templates(); p = base.params
    for mode in (:credit, :consolidate)
        AS.ATTN_MODE[] = mode
        println("\n======== ", mode, " ========")
        a = 0; n = 0
        for t in set.templates
            r = EV(t.substrate, set); want = (t.L2, t.L3, t.L3R); got = (r.agency, r.self_producing, r.self_repairing)
            a += count(i -> got[i] == want[i], 1:3); n += 3
            got == want || println("   DISAGREE ", rpad(t.name, 24), " label=", want, " got=", got)
        end
        println("templates-digest: ", a, "/", n)
        for nm in ("selfloop-pair-agent", "agent", "triangle-agent", "omnivore", "alternator", "reflex", "stimulus-response")
            s = only(t for t in set.templates if t.name == nm).substrate
            log = run_world(s, p, 1000)
            println("   world ", rpad(nm, 22), "form ", count(t -> formed(s, log, t, p.alive_window), 1:1000), "/1000")
        end
        state = Ref(UInt64(20261009)); na = 0
        for k in 1:20000
            x = random_substrate(state); EV(x, base).agency && (na += 1)
        end
        println("random agents with direction: ", na)
    end
end
main()
