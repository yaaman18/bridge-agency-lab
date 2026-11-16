# S60: canonical Julia run. Usage: julia run_det.jl BUNDLE OUT [BUNDLE OUT ...]  (exit 2 on a bad bundle)
include(joinpath(@__DIR__, "TrmDet.jl"))
using .TrmDet
function main(args)
    iseven(length(args)) && !isempty(args) || (println(stderr, "usage: run_det.jl BUNDLE OUT ..."); return 2)
    for j in 1:2:length(args)
        recs = try
            TrmDet.read_recs(args[j], TrmDet.MAGIC_BUNDLE)
        catch e
            println(stderr, "bad bundle ", args[j], ": ", sprint(showerror, e)); return 2
        end
        m = try
            TrmDet.Model(recs)
        catch e
            println(stderr, "bad bundle ", args[j], ": ", sprint(showerror, e)); return 2
        end
        t = @elapsed out, _, _ = TrmDet.run_bundle(m, recs)
        length(out) == 45 || (println(stderr, "internal: record count ", length(out)); return 1)
        TrmDet.write_recs(args[j+1], TrmDet.MAGIC_OUT, out)
        println(stderr, "julia ", basename(args[j]), " ", round(t; digits=3), " s (5 ACT steps, incl. compile on first)")
    end
    return 0
end
exit(main(ARGS))
