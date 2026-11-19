# Memory transfer pilot: the gate. Checks the freeze, every frozen prediction against the results file, the controls,
# and two negative controls (a planted leak and a corrupted row) that the same checks must reject.
# Usage (from experiments/): julia --project=.. memory-transfer-pilot/check.jl [results.tsv]
using TOML, SHA
include(joinpath(@__DIR__, "mt_core.jl"))

const DIR = @__DIR__
path = length(ARGS) >= 1 ? ARGS[1] : joinpath(DIR, "results.tsv")

# freeze: the line in experiments/freeze-memory-transfer-pilot.txt is the hash of predictions.toml now
frozen = split(read(joinpath(DIR, "..", "freeze-memory-transfer-pilot.txt"), String))[1]
now_hash = bytes2hex(open(sha256, joinpath(DIR, "predictions.toml")))
println("FILE: predictions.toml sha256 $now_hash")
println("GATE: freeze ", frozen == now_hash ? "PASS" : "FAIL")
pred = TOML.parsefile(joinpath(DIR, "predictions.toml"))["prediction"]

load(p) = [split(l, '\t') for l in readlines(p)[2:end]]
pick(rows, m, c, a, cond, set) = [r for r in rows if r[1] == m && r[2] == c && r[3] == a && r[4] == cond && r[5] == set]
answers(rows, m, c, a, cond; set = "test") = String.(getindex.(pick(rows, m, c, a, cond, set), 8))

# every check returns (name, ok)
function checks(rows)
    out = Tuple{String,Bool}[]
    want(m, c) = m == "LP" ? pred["LP_$c"] : pred[m]
    for m in ("ADD", "P", "LP"), c in ("H4", "O8"), a in ("SX", "SY")
        p = want(m, c)[a]
        got = answers(rows, m, c, a, "TRANS")
        push!(out, ("prediction $m $c $a $(join(got, ","))", got == p["responses"] && count(==("true"), getindex.(pick(rows, m, c, a, "TRANS", "test"), 9)) == p["correct"]))
    end
    for c in ("H4", "O8")   # ADD fails the training pairs too
        push!(out, ("ADD $c train all ties", all(a -> all(==("tie"), answers(rows, "ADD", c, a, "TRANS"; set = "train")), ("SX", "SY"))))
    end
    for m in ("ADD", "P", "LP"), c in ("H4", "O8")
        for cond in ("INIT", "FROZEN")
            sx = answers(rows, m, c, "SX", cond); sy = answers(rows, m, c, "SY", cond)
            push!(out, ("control $cond $m $c all ties and assignment-independent", sx == sy && all(==("tie"), sx)))
        end
        for a in ("SX", "SY")   # SELF: the scores themselves (not only the answers) equal the transplant's
            sc(cond) = getindex.(vcat(pick(rows, m, c, a, cond, "test"), pick(rows, m, c, a, cond, "train")), 7)
            push!(out, ("control SELF == TRANS $m $c $a", sc("SELF") == sc("TRANS")))
        end
        flip(x) = x == "X" ? "Y" : x == "Y" ? "X" : x
        sx = answers(rows, m, c, "SX", "TRANS"); sy = answers(rows, m, c, "SY", "TRANS")
        push!(out, ("label inversion $m $c", flip.(sx) == sy))
    end
    out
end

report(cs) = (for (n, ok) in cs; println("  ", ok ? "ok  " : "FAIL", " ", n); end; all(last, cs))

println("== results: $path")
ok_main = report(checks(load(path)))
println("GATE: predictions and controls ", ok_main ? "PASS" : "FAIL")

for c in (:H4, :O8)
    f = CODINGS[c]
    println("GATE: C/D discriminated by features ($c, without X/Y) ", f[:C] != f[:D] ? "PASS" : "FAIL")
end

# negative control N1: a leaky readout that also reads the transient teacher signal, on an individual that was not
# transplanted (SELF). The FROZEN control then answers with the last teacher's label, which depends on the assignment.
leaky(ind, L, R) = score(ind, L, R) + ind.teacher / 1000
function rows_with(readout)
    rows = Vector{Vector{String}}()
    for m in (:ADD, :P, :LP), c in (:H4, :O8), a in (:SX, :SY), cond in (:TRANS, :INIT, :FROZEN, :SELF)
        ind = fresh(m, c)
        cond === :INIT || train!(ind, a; eta = cond === :FROZEN ? Q(0) : ETA)
        subj = cond in (:SELF, :FROZEN) ? ind : transplant(ind)   # the leak: FROZEN is read without the transplant
        for (set, prs) in (("test", TEST), ("train", TRAIN)), (L, R) in prs
            s = readout(deepcopy(subj), L, R)
            push!(rows, string.([m, c, a, cond, set, "$L$R", s, answer(s), answer(s) == (target(a, L, R) > 0 ? "X" : "Y")]))
        end
    end
    rows
end
n1 = checks(rows_with(leaky))
println("GATE: negative control N1 (planted leak) rejected ", !all(last, n1) ? "PASS" : "FAIL",
        "  (", count(!last, n1), " checks fail: ", join(first.(filter(!last, n1))[1:min(end, 2)], "; "), " ...)")

# negative control N2: one answer of LP H4 SY flipped in the real results
rows2 = load(path)
i = findfirst(r -> r[1:6] == ["LP", "H4", "SY", "TRANS", "test", "CD"], rows2)
rows2[i] = vcat(rows2[i][1:7], ["Y", "false"])
n2 = checks(rows2)
println("GATE: negative control N2 (one flipped answer) rejected ", !all(last, n2) ? "PASS" : "FAIL",
        "  (", join(first.(filter(!last, n2)), "; "), ")")
