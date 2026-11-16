# S60 gate E (diagnostic, not a pass condition): ulp error of exp_det against Float32(exp(Float64(x))).
# Usage: julia exp_check.jl grid   (2^20 points in [-87, 88]; allowed during development)
#        julia exp_check.jl all    (grid + every exp_det argument of the six bundles; main run only)
# Writes experiments/results-trm-det-E.out (mode all) or prints (mode grid).
include(joinpath(@__DIR__, "TrmDet.jl"))
using .TrmDet

ulps(a::Float32, b::Float32) = a == b ? 0 : (isfinite(a) && isfinite(b) ? abs(Int64(reinterpret(Int32, a)) - Int64(reinterpret(Int32, b))) : typemax(Int64))

function summarize(io, label, xs)
    hist = Dict{Int64,Int}()
    worst, wx = Int64(0), 0f0
    nout = 0
    for x in xs
        if x < -87f0 || x > 88f0
            nout += 1
            continue
        end
        u = ulps(TrmDet.exp_det(x), Float32(exp(Float64(x))))
        hist[u] = get(hist, u, 0) + 1
        u > worst && ((worst, wx) = (u, x))
    end
    n = length(xs) - nout
    println(io, label, ": points ", length(xs), " in [-87,88] ", n, " outside ", nout, " max_ulp ", worst, " at x=", wx,
            " histogram ", join([string(k, "ulp:", hist[k]) for k in sort!(collect(keys(hist)))], " "))
end

function main(mode)
    grid = Float32[Float32(-87 + 175 * j / (2^20 - 1)) for j in 0:(2^20 - 1)]
    if mode == "grid"
        summarize(stdout, "E grid", grid)
        return 0
    end
    mode == "all" || return 2
    path = joinpath(@__DIR__, "..", "..", "results-trm-det-E.out")
    open(path, "w") do io
        println(io, "S60 E (diagnostic): exp_det vs Float32(exp(Float64(x))), ulp distance")
        summarize(io, "E grid", grid)
        for c in ("a", "b", "e"), w in ("W0", "W1")
            recs = TrmDet.read_recs(joinpath(@__DIR__, "bundles", string(c, "_", w, ".bin")), TrmDet.MAGIC_BUNDLE)
            m = TrmDet.Model(recs)
            log = Float32[]
            TrmDet.EXP_LOG[] = log
            try
                TrmDet.run_bundle(m, recs)
            finally
                TrmDet.EXP_LOG[] = nothing
            end
            summarize(io, string("E args ", c, "_", w), log)
        end
    end
    print(read(path, String))
    return 0
end
exit(main(isempty(ARGS) ? "grid" : ARGS[1]))
