using AgencySubstrate
const AS = AgencySubstrate
include(joinpath(@__DIR__, "variant_freq.jl"))
include(joinpath(@__DIR__, "variant_digest.jl"))
set = load_templates(joinpath(@__DIR__, "templates-digest.toml"))
s = only(t for t in set.templates if t.name == "redundant-sensor-agent").substrate
id(n) = findfirst(==(n), s.names)
ch(sch, sil) = sort([s.names[m] for m in Base.invokelatest(AS.choice, s, set.choice_params, sch, set.choice_window; silenced=Set{Int}(id.(sil)))])
for sil in ([], ["s1a"], ["s1b"], ["s2a"], ["s2b"], ["c1"], ["s1a", "s1b"], ["s1a", "s1b", "s2a", "s2b"])
    println(rpad(string(sil), 34), "c1-better=", ch(set.choice[1], sil), "  c2-better=", ch(set.choice[2], sil))
end
surv(sil) = Dict(x.name => Base.invokelatest(AS.survives, s, set.params, x; silenced=Set{Int}(id.(sil))) for x in set.survival)
println("form kept, intact:          ", surv([]))
println("form kept, s1a only off:    ", surv(["s1a"]))
println("form kept, all sensors off: ", surv(["s1a", "s1b", "s2a", "s2b"]))
