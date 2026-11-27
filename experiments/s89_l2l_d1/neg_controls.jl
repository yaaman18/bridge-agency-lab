# S89 negative controls NC1-NC3 (spec r2 §4.2): each altered D1 must fail its intended gate; any pass is an error exit.
# Includes l2l_d1.jl unchanged and redefines only d1!; the other capacities keep d1_fifo!.
# usage: julia --project=. experiments/s89_l2l_d1/neg_controls.jl
include(joinpath(@__DIR__, "l2l_d1.jl"))
const NCX = lives83()[1]; const NCT = 12000; const NCIO = IOBuffer(); NCBAD = Ref(0)
function nc(name, want)
    msg = try; life89(NCX; tmax = NCT); nothing; catch e; sprint(showerror, e); end
    ok = msg !== nothing && any(w -> startswith(msg, w), want)
    ok || (NCBAD[] += 1)
    println(NCIO, "$name: ", msg === nothing ? "PASSED ALL GATES (control failed)" : "failed with \"$(first(msg, 120))\"",
            " -> ", ok ? "ok (expected $(join(want, " or ")))" : "NOT OK (expected $(join(want, " or ")))")
end

# NC1: C=2 drops the tail (newest) instead of the head when full
d1!(M::Mem, C, kp, t, k, a, y) = C != 2 ? d1_fifo!(M, C, kp, t, k, a, y) :
    (!kp ? 0 : (ev = 0; if length(M.list) == C; (t0, k0, a0, y0) = pop!(M.list); M.m[k0] -= 1; M.m1[k0] -= y0; M.ma[a0] -= 1; M.ma1[a0] -= y0; ev = 1; end; remember!(M, t, k, a, y); ev))
nc("NC1 (C=2 LIFO)", ("G6",))

# NC2: C=1 evicts the head when full also on steps R1 does not keep
d1!(M::Mem, C, kp, t, k, a, y) = C != 1 ? d1_fifo!(M, C, kp, t, k, a, y) :
    (!kp ? (length(M.list) == C ? (forget_first!(M); 1) : 0) : d1_fifo!(M, C, kp, t, k, a, y))
nc("NC2 (C=1 evict without keep)", ("G6(b)",))

# NC3: C=0 gets one fragment forced in (the first example)
d1!(M::Mem, C, kp, t, k, a, y) = C != 0 ? d1_fifo!(M, C, kp, t, k, a, y) : (isempty(M.list) && remember!(M, t, k, a, y); 0)
nc("NC3 (C=0 one fragment injected)", ("G2", "G9"))

println(NCIO, NCBAD[] == 0 ? "negative controls: all 3 failed at their intended gates" : "negative controls: $(NCBAD[]) NOT OK")
s = String(take!(NCIO)); print(s); write(joinpath(OUT89, "neg_controls.out"), s)
NCBAD[] == 0 || exit(1)
