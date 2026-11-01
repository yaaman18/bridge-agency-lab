# Checks core/jsmath.jl against V8 (out/math-v8.txt from math.js). Usage: julia --project=. core/check/math.jl
include(joinpath(@__DIR__, "..", "LabCore.jl"))
using .LabCore
const LC = LabCore
h(s) = reinterpret(Float64, parse(UInt64, s; base = 16))
function main()
    bad = zeros(Int, 5); base = zeros(Int, 4); n = 0
    for l in eachline(joinpath(@__DIR__, "out", "math-v8.txt"))
        v = h.(split(l)); n += 1
        bad[1] += LC.jsexp(v[1]) != v[2]; bad[2] += LC.jstanh(v[3]) != v[4]; bad[3] += LC.jslog(v[5]) != v[6]
        bad[4] += LC.jscos(v[7]) != v[8]; bad[5] += LC.jshypot(v[9], v[10]) != v[11]
        base[1] += exp(v[1]) != v[2]; base[2] += tanh(v[3]) != v[4]; base[3] += log(v[5]) != v[6]; base[4] += cos(v[7]) != v[8]
    end
    println("inputs $n; mismatches of jsmath.jl  exp $(bad[1]) tanh $(bad[2]) log $(bad[3]) cos $(bad[4]) hypot $(bad[5])")
    println("(Julia Base for comparison: exp $(base[1]) tanh $(base[2]) log $(base[3]) cos $(base[4]))")
end
main()
