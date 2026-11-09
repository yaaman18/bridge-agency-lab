# S26 (T3-d): the state condition "q >= 1 and the bin3 contrast undefined" on receptor -> patch-motor edges at the end of
# the raising (SF default). Labels frozen in predictions-t3diag.md (no predictions). Writes results-t3diag.json.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
su = LBA.setup_with(392); out = Any[]
for seed in 311:320, cur in (:std, :swap)
    s = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
    c = s.raised
    ks = [k for (k, (a, m, _)) in enumerate(s.edges) if s.b.kind[a] == 'R' && s.b.kind[m] == 'M' && s.b.patch[m] <= 2]
    und(k) = (c.cOn === nothing ? true : isnan(c.cOn[k]), c.cOff === nothing ? true : isnan(c.cOff[k]))
    q = [k for k in ks if c.q[k] >= 1]; qu = [k for k in q if any(und(k))]
    nm(k) = s.names[s.edges[k][1]] * "->" * s.names[s.edges[k][2]]
    row = Dict("seed" => seed, "arm" => String(cur), "N_all" => length(ks), "N_q" => length(q), "N_q_undef" => length(qu),
               "cOn_only" => count(k -> und(k) == (true, false), qu), "cOff_only" => count(k -> und(k) == (false, true), qu), "both" => count(k -> und(k) == (true, true), qu),
               "q_undef_edges" => [nm(k) * (und(k)[2] && !und(k)[1] ? " (cOff undef)" : und(k)[1] && !und(k)[2] ? " (cOn undef)" : " (both)") for k in qu], "q_edges" => [nm(k) for k in q])
    push!(out, row); println("seed=$seed $cur N_all $(row["N_all"]) N_q $(row["N_q"]) N_q_undef $(row["N_q_undef"]) ", row["q_undef_edges"])
end
write(joinpath(LAB, "experiments", "results-t3diag.json"), JSON.json(Dict("spec" => "notes/T3.md T3-d, predictions-t3diag.md", "rows" => out), 2))
