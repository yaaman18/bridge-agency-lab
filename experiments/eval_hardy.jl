using AgencySubstrate, TOML
const AS = AgencySubstrate
const FX = "/Users/yamaguchimitsuyuki/bridge-protocol/tools/AgencySubstrate/fixtures"
include(joinpath(@__DIR__, "variant_freq.jl"))
ENV["WORLD_VARIANT"] = get(ENV, "WORLD_VARIANT", "variant_hardy.jl")
include(joinpath(@__DIR__, "fragility.jl"))
EV(s, set) = Base.invokelatest(evaluate, s, set)
withr(P, r) = AS.Params(P.smax, P.decay_period, P.grow_cost, P.resource0, r, P.horizon, P.alive_window, P.strength0)
l3r = merge(TOML.parsefile(joinpath(FX, "labels-repair.toml"))["L3R"], TOML.parsefile(joinpath(@__DIR__, "labels-precision.toml"))["L3R"])
s = only(t for t in load_templates(joinpath(@__DIR__, "designs.toml")).templates if t.name == "selfloop-pair-agent").substrate
println("sensor variant: ", ENV["WORLD_VARIANT"])
for r in (30, 60, 100, 200)
    agree = 0; total = 0
    for f in ("templates.toml", "templates-adversarial.toml", "templates-adversarial-2.toml", "templates-adversarial-3.toml", "templates-adversarial-4.toml", "templates-repair.toml")
        set = load_templates(joinpath(FX, f)); set = merge(set, (; params=withr(set.params, r)))
        for t in set.templates
            x = EV(t.substrate, set); L3R = haskey(l3r, t.name) ? l3r[t.name] : t.L3R
            want = (t.L2, t.L3, L3R); got = (x.agency, x.self_producing, x.self_repairing)
            agree += count(i -> got[i] == want[i], 1:3); total += 3
            got == want && continue
            println("   DISAGREE rmax=$r ", t.name, " ", want, " ", got)
        end
    end
    p = withr(load_templates().params, r)
    println("\n== rmax $r: labels ", agree, "/", total, "  unperturbed world: ", run_world(s, p, 1000))
    for (k, v) in battery(s, p); v > 0 && println("   ", rpad(k, 20), v, "/11 dead"); end
end
