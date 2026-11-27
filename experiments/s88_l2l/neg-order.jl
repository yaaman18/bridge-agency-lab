# negative control (codex I-R P2): kstep! as add-then-decay must fail G1 against the official update2!
include(joinpath(@__DIR__, "l2l.jl"))
function kstep!(c::Cn, k, a, y, lam)
    c.n[a] += 1; c.n1[a] += y; c.rn[k] += 1; c.rn1[k] += y
    if lam < 1; c.n .*= lam; c.n1 .*= lam; c.rn .*= lam; c.rn1 .*= lam; end; return c
end
try; life88(lives83()[1]; tmax = 3000); println("NEG CONTROL FAILED: add-then-decay passed"); catch e; println("neg control ok: ", sprint(showerror, e)[1:min(end, 80)]); end
