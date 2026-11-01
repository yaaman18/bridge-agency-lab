using AgencySubstrate
const AS = AgencySubstrate
for f in ("variant_freq.jl", "variant_digest.jl", "variant_digest_repair.jl", "variant_tracking_sets.jl", "variant_direction.jl")
    include(joinpath(@__DIR__, f))
end
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
include(joinpath(@__DIR__, "env_digest_cap.jl"))
EV(s, set) = Base.invokelatest(evaluate, s, set)
function main()
    set = load_templates(joinpath(@__DIR__, "templates-digest.toml")); a = 0; n = 0
    for t in set.templates
        r = EV(t.substrate, set); want = (t.L2, t.L3, t.L3R); got = (r.agency, r.self_producing, r.self_repairing)
        a += count(i -> got[i] == want[i], 1:3); n += 3
        println("   ", rpad(t.name, 24), got == want ? "agree   " : "DISAGREE", " directed=", r.directed, " L2 w/o direction=", r.agency_without_direction)
    end
    println("R1 templates-digest: ", a, "/", n)
    base = load_templates(); state = Ref(UInt64(20261009)); nb = 0; nd = 0; ncap = 0; nunc = 0; bad = String[]
    uncval(x, sch, A) = sum((AS.yield_of(sch, x.motors[m], 0) for m in A); init=0)
    for k in 1:20000
        x = random_substrate(state); r = EV(x, base)
        r.agency_without_direction || continue
        nb += 1
        A = [Base.invokelatest(AS.choice, x, base.choice_params, c, base.choice_window) for c in base.choice]
        r.directed && (ncap += 1)
        (uncval(x, base.choice[1], A[1]) > uncval(x, base.choice[1], A[2]) && uncval(x, base.choice[2], A[2]) > uncval(x, base.choice[2], A[1])) && (nunc += 1)
        if r.agency
            nd += 1
            p1 = Set(x.motors[m] for m in A[1]); p2 = Set(x.motors[m] for m in A[2])
            ((1 in p1) && p1 != Set([2]) && (2 in p2) && p2 != Set([1])) || push!(bad, "k=$k $(r.choices)")
        end
    end
    println("R2 random: agents with direction ", nd, " (of ", nb, " without direction); not following the better patch: ", isempty(bad) ? "none" : bad)
    println("R3 directed share among the ", nb, ": capped ", ncap, ", uncapped ", nunc)
    p = base.params
    mine = load_templates(joinpath(@__DIR__, "templates-digest.toml"))
    for nm in ("selfloop-pair-agent", "agent", "omnivore", "alternator", "reflex")
        s = only(t for t in mine.templates if t.name == nm).substrate
        log = run_world(s, p, 1000)
        println("R4 world ", rpad(nm, 22), "form ", count(t -> formed(s, log, t, p.alive_window), 1:1000), "/1000")
    end
end
main()
