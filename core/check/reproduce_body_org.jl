# Reproduces matter/results-body-org.json (stage 42, written by matter/test_body_org.js on 2026-10-31) with the Julia
# rules and compares every value. Usage: julia --project=. core/check/reproduce_body_org.jl
include(joinpath(@__DIR__, "..", "LabCore.jl"))
using .LabCore, JSON
const LAB = normpath(joinpath(@__DIR__, "..", ".."))
old = JSON.parse(read(joinpath(LAB, "matter", "results-body-org.json"), String); dicttype = Dict{String,Any})
o = (U = 0.02, MCOST = 0.004, STEPS = 10000)
R = Dict{String,Any}()
for s in 1:10
    org = body_org_run("ORG", s, o)
    r = Dict("ORG" => org, "REPLAY" => body_org_run("REPLAY", s, o, org["acts"]), "NONE" => body_org_run("NONE", s, o),
             "REV" => body_org_run("ORG", s, merge(o, (REV = 5000,))))
    for c in values(r); delete!(c, "acts"); end
    R[string(s)] = r
end
new = JSON.parse(JSON.json(jsonable(R)); dicttype = Dict{String,Any})
function firstdiff(a, b, p)
    a isa AbstractDict && b isa AbstractDict || a isa AbstractVector && b isa AbstractVector || return a == b ? nothing : "$p: file $a julia $b"
    if a isa AbstractDict
        # The file was written by the stage 42 code; later stages added result keys (lost, blocked, keptEnd, meanLate, kept,
        # upkeep). Every key of the file must be reproduced; the added keys are listed.
        for k in keys(a)
            haskey(b, k) || return "$p.$k: missing in the Julia result"
            d = firstdiff(a[k], b[k], "$p.$k"); d === nothing || return d
        end
        for k in keys(b); haskey(a, k) || push!(ADDED, k); end
    else
        length(a) == length(b) || return "$p: length differs"
        for i in eachindex(a); d = firstdiff(a[i], b[i], "$p[$(i-1)]"); d === nothing || return d; end
    end
    return nothing
end
const ADDED = Set{String}()
d = firstdiff(old, new, "")
println(d === nothing ? "results-body-org.json reproduced exactly (10 seeds x 4 conditions x 10000 steps; keys added since stage 42: $(join(sort(collect(ADDED)), ", ")))" : "DIFFERENT $d")
