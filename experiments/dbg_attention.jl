using AgencySubstrate
const AS = AgencySubstrate
for f in ("variant_freq.jl", "variant_digest.jl", "variant_digest_repair.jl", "variant_tracking_sets.jl", "variant_direction.jl", "variant_attention.jl")
    include(joinpath(@__DIR__, f))
end
include(joinpath(@__DIR__, "env_digest_wta.jl"))
AS.ATTN_MODE[] = :consolidate
set = load_templates(joinpath(@__DIR__, "templates-digest.toml")); p = set.params
s = only(t for t in set.templates if t.name == "agent").substrate
log = run_world(s, p, 1000)
for (a, b) in ((1, 300), (301, 600), (601, 1000))
    println("steps $a-$b form ", count(t -> formed(s, log, t, p.alive_window), a:b), "/", b - a + 1,
        "  both motors active ", count(t -> log[t].active[findfirst(==("m1"), s.names)] && log[t].active[findfirst(==("m2"), s.names)], a:b))
end
