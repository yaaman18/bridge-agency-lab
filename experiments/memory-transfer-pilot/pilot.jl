# Memory transfer pilot: run every model × coding × assignment × condition and write the results (TSV, exact scores).
# Usage (from experiments/): julia --project=.. memory-transfer-pilot/pilot.jl [out.tsv]
include(joinpath(@__DIR__, "mt_core.jl"))

out = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "results.tsv")
open(out, "w") do io
    println(io, "model\tcoding\tassign\tcond\tset\tpair\tscore\tanswer\tcorrect")
    for model in (:ADD, :P, :LP), coding in (:H4, :O8), assign in (:SX, :SY), cond in (:TRANS, :INIT, :FROZEN, :SELF)
        r = run_one(model, coding, assign, cond)
        for (set, rows) in (("test", r.test), ("train", r.train)), ((L, R), (s, a)) in rows
            ok = a == (target(assign, L, R) > 0 ? "X" : "Y")
            println(io, join((model, coding, assign, cond, set, "$L$R", s, a, ok), '\t'))
        end
    end
end
for model in (:ADD, :P, :LP), coding in (:H4, :O8), assign in (:SX, :SY)
    r = run_one(model, coding, assign, :TRANS)
    println("$model $coding $assign  test $(ncorrect(r.test, assign))/4 ", join(last.(last.(r.test)), ","),
            "   train $(ncorrect(r.train, assign))/4")
end
println("wrote $out")
