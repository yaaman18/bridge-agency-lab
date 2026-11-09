# Item 79 (user 2026-11-02 "じゃあ1の規則変更を試してみて"): seen both before growing (core/circuit.jl step!(...;
# seen_both = true), formal/LabCircuit.lean SeenBoth) on body_org's circuit with L2's rule (bin3 + idle_first + core gate),
# with and without the extra receptors of item 78 B. The raising: the confident receptor inputs at the end, and the check
# that no receptor->motor contingency grew while its contrast was undefined. Predictions: predictions-seenboth.md.
# Usage: julia --project=. experiments/eval_seenboth.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
fname(b, u) = b.names[u] * "(" * LC.FEATURES[b.perm[b.feat[u]]][1] * ")"
res = Dict{String,Any}()
for extra in (false, true), sb in (false, true), seed in 1:10
    b = LC.newborn(false; extra = extra ? collect(LC.EXTRA_FEATURES) : Int[]); c = LC.init(b); nz = LC.Mulberry(seed)
    rm = [b.kind[a] == 'R' && b.kind[m] == 'M' && b.patch[m] <= 2 for (a, m, _) in b.edges]
    grew_undefined = 0
    for y in LC.BO_CUR
        q0 = copy(c.q)
        LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = :bin3, idle_first = true, core_gate = true, seen_both = sb)
        for k in eachindex(c.q)
            (rm[k] && c.q[k] > q0[k] && (isnan(c.cOn[k]) || isnan(c.cOff[k]))) && (grew_undefined += 1)
        end
    end
    conf(m) = [fname(b, a) for (k, (a, cc, _)) in enumerate(b.edges) if cc == LC.unit(b, m) && b.kind[a] == 'R' && c.q[k] >= 1]
    tag = "$(extra ? "extra" : "base") $(sb ? "seenboth" : "bin3")"
    r = Dict("conf_m1" => conf("m1"), "conf_m2" => conf("m2"), "grew_while_undefined" => grew_undefined)
    res["$tag seed$seed"] = r
    println(rpad(tag, 15), " seed ", lpad(seed, 2), "  grew while undefined ", lpad(grew_undefined, 3), "  m1 <- ", join(r["conf_m1"], " "), "   m2 <- ", join(r["conf_m2"], " "))
end
write(joinpath(@__DIR__, "results-seenboth.json"), JSON.json(res, 2))
