# Usage: julia --project=.. eval_tracking_sets.jl digest|adopted
using AgencySubstrate, TOML
const AS = AgencySubstrate
const FX = "/Users/yamaguchimitsuyuki/bridge-protocol/tools/AgencySubstrate/fixtures"
mode = ARGS[1]
if mode == "digest"
    include(joinpath(@__DIR__, "variant_freq.jl")); include(joinpath(@__DIR__, "variant_digest.jl")); include(joinpath(@__DIR__, "variant_digest_repair.jl"))
end
include(joinpath(@__DIR__, "variant_tracking_sets.jl"))
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
EV(s, set) = Base.invokelatest(evaluate, s, set)
function check(set, l3r=Dict())
    a = 0; n = 0
    for t in set.templates
        r = EV(t.substrate, set); L3R = something(t.L3R, get(l3r, t.name, missing))
        want = (t.L2, t.L3, L3R); got = (r.agency, r.self_producing, r.self_repairing); a += count(i -> got[i] == want[i], 1:3); n += 3
        (got != want || !isempty(r.tracking_sets)) && println("   ", rpad(t.name, 24), got == want ? "agree   " : "DISAGREE", " label=", want, " got=", got, " sets=", r.tracking_sets)
    end
    (a, n)
end
function main_digest()
    set = load_templates(joinpath(@__DIR__, "templates-digest.toml"))
    single = Dict(t.name => t.L2 for t in set.templates)
    println("S1/S2 templates-digest: ", check(set))
    # S4: random circuits, sets vs single units. Single-unit result = minimal sets of size 1 only.
    base = load_templates(); state = Ref(UInt64(20261009)); nsets = 0; nsingle = 0; newly = String[]
    for k in 1:20000
        x = random_substrate(state); r = EV(x, base)
        r.agency && (nsets += 1)
        T1 = sort!(unique(vcat(Int[], [S for S in r.tracking_sets if length(S) == 1]...)))
        idx = Dict(n => i for (i, n) in enumerate(x.names))
        T1i = [idx[only(S)] for S in r.tracking_sets if length(S) == 1]
        a1 = !isempty(r.core) && r.core_enables_action && r.alive_somewhere && r.differentiated && Base.invokelatest(AS.value_needed, x, base.params, base.survival, T1i)
        a1 && (nsingle += 1)
        (r.agency && !a1) && length(newly) < 5 && push!(newly, "k=$k sets=$(r.tracking_sets)")
    end
    println("S4 random agency: single units ", nsingle, ", minimal sets ", nsets)
    foreach(x -> println("   newly agent: ", x), newly)
end
function main_adopted()
    l3r = TOML.parsefile(joinpath(FX, "labels-repair.toml"))["L3R"]; a = 0; n = 0
    for f in ("templates.toml", "templates-adversarial.toml", "templates-adversarial-2.toml", "templates-adversarial-3.toml", "templates-adversarial-4.toml", "templates-repair.toml")
        x = check(load_templates(joinpath(FX, f)), l3r); a += x[1]; n += x[2]
    end
    println("S3 frozen templates, adopted dynamics: ", a, "/", n)
end
mode == "digest" ? main_digest() : main_adopted()
