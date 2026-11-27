include(joinpath(@__DIR__, "l2l.jl"))
r1(p, y) = (y == 1 && p > 0.5) || (y == 0 && p < 0.5)     # reversed R1: G5 must fail
x = lives83()[1]
try; life88(x; tmax = 3000); println("NEG CONTROL FAILED: reversed R1 passed"); catch e; println("neg control ok: ", sprint(showerror, e)[1:min(end, 80)]); end
