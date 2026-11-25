# S64 diagnosis after the run (not a gate; written after G1 failed for obs-full rev TRM): reads out/weights and the G1 bundles
# in out/g1 only. The final ACT step of the selected obs-full TRMs in Float32 (TrmC0, TrmPort, TrmDet) against a Float64 forward
# of the same weights (TrmC0 generic), round by round, at all positions and at the question positions.
# Usage (from the lab root): julia --project=. -t 1 experiments/c0_trm/diag_g1.jl > experiments/c0_trm/out/diag_g1.out
using LinearAlgebra, Printf
BLAS.set_num_threads(1)
const D = normpath(joinpath(@__DIR__, ".."))
include(joinpath(D, "trm", "TrmPort.jl")); include(joinpath(D, "trm", "det", "TrmDet.jl")); include(joinpath(D, "c0_trm", "TrmC0.jl"))
const C = TrmC0; const ROPE = TrmPort.RotaryEmbedding(8, 47, 10000.0)
function loadp(f)
    b = read(f); p = C.Params{Float32}(); o = 0
    for a in C.plist(p); n = length(a); a .= reshape(reinterpret(Float32, b[o+1:o+4n]), size(a)); o += 4n; end
    o == length(b) || error("size"); return p
end
function tok8(bun)
    d = TrmDet.recdict(TrmDet.read_recs(bun, TrmDet.MAGIC_BUNDLE)); r = d["x1.inputs"]
    return UInt8.(permutedims(TrmDet.to_jl(Float64.(r.i), r.dims)))   # (S, B)
end
function rounds(p, cfg, tok, T)
    q = C.convert_params(T, p); w = C.Work{T}(size(tok, 2), 0, ROPE...)
    C.embed!(w, q, tok); C.init_carry!(w, q); out = Matrix{Float64}[]
    for k in 1:cfg.hmax, r in 1:cfg.Hc; C.h_round_ng!(w, q, cfg); push!(out, Float64.(w.zH)); end
    lg = Float64.(q.lm) * Float64.(w.zH)
    return out, lg
end
pq(lg, B) = [C.p2(lg[9, (b-1)*47+c], lg[8, (b-1)*47+c]) for c in (46, 47), b in 1:B]
for (lab, f) in (("rev TRM", "obs-full_rev_TRM"), ("stat TRM", "obs-full_stat_TRM"))
    p = loadp(joinpath(D, "c0_trm", "out", "weights", f * ".bin")); tk = tok8(joinpath(D, "c0_trm", "out", "g1", "sel_$(f).bin"))
    z32, l32 = rounds(p, C.CFG_TRM, tk, Float32); z64, l64 = rounds(p, C.CFG_TRM, tk, Float64)
    println(lab, ": max |z_H(Float32) - z_H(Float64)| after each H round: ", join([@sprintf("%.1e", maximum(abs.(a .- b))) for (a, b) in zip(z32, z64)], " "))
    println("   max |z_H| ", @sprintf("%.2f", maximum(abs, z64[end])), "; logits Float32 vs Float64 max diff ", @sprintf("%.2e", maximum(abs.(l32 .- l64))),
            "; p at the question positions Float32 vs Float64 max diff ", @sprintf("%.2e", maximum(abs.(pq(l32, 8) .- pq(l64, 8)))))
    println("   p (Float64) at Q1, Q2 of the 8 inputs: ", join([@sprintf("%.5f", x) for x in pq(l64, 8)], " "))
    # sensitivity: perturb one input embedding weight by 1 ulp (Float64 forward) and follow the difference
    q = C.copy_params(p); q.emb[1, 1] = nextfloat(q.emb[1, 1])
    zq, lq = rounds(q, C.CFG_TRM, tk, Float64)
    println("   1-ulp change of embed_tokens[0, 0] (Float64 forward): max |Δz_H| per round ", join([@sprintf("%.1e", maximum(abs.(a .- b))) for (a, b) in zip(zq, z64)], " "),
            "; max |Δp| ", @sprintf("%.2e", maximum(abs.(pq(lq, 8) .- pq(l64, 8)))))
    # TrmPort and TrmDet against Float64 at the final step
    d = TrmDet.recdict(TrmDet.read_recs(joinpath(D, "c0_trm", "out", "g1", "sel_$(f).jl.bin"), TrmDet.MAGIC_OUT))
    Ld = TrmDet.to_jl(d["step3.logits"].f, d["step3.logits"].dims)
    L64 = permutedims(reshape(l64, 12, 47, 8), (3, 2, 1))
    println("   final logits vs Float64: TrmC0-F32 ", @sprintf("%.2e", maximum(abs.(permutedims(reshape(l32, 12, 47, 8), (3, 2, 1)) .- L64))),
            ", TrmDet ", @sprintf("%.2e", maximum(abs.(Float64.(Ld) .- L64))))
end
println("---- the question positions only (tokens 7, 8 at positions 45, 46)")
for f in ("obs-full_rev_TRM", "obs-full_stat_TRM")
    p = loadp(joinpath(D, "c0_trm", "out", "weights", f * ".bin")); tk = tok8(joinpath(D, "c0_trm", "out", "g1", "sel_$(f).bin"))
    _, l32 = rounds(p, C.CFG_TRM, tk, Float32); _, l64 = rounds(p, C.CFG_TRM, tk, Float64)
    d = TrmDet.recdict(TrmDet.read_recs(joinpath(D, "c0_trm", "out", "g1", "sel_$(f).jl.bin"), TrmDet.MAGIC_OUT))
    Ld = Float64.(TrmDet.to_jl(d["step3.logits"].f, d["step3.logits"].dims))   # (B, S, V)
    st = Dict{String,Array{Float32}}(TrmC0.official_state(p))
    names = [:hidden_size, :num_heads, :puzzle_emb_ndim, :seq_len, :puzzle_emb_len, :mlp_t, :expansion, :rms_norm_eps, :vocab_size, :pos_encodings, :rope_theta, :L_layers, :H_cycles, :L_cycles, :halt_max_steps, :batch_size, :num_puzzle_identifiers]
    model = TrmPort.ACTModel((names = names, values = Any[32, 4, 0, 47, 0, false, 4.0, 1e-5, 12, "rope", 10000.0, 2, 3, 6, 3, 8, 1]), st)
    batch = Dict{String,Any}("inputs" => Int.(permutedims(tk)), "puzzle_identifiers" => zeros(Int, 8)); carry = TrmPort.initial_carry(model, batch); out = nothing
    for _ in 1:3; carry, out = TrmPort.act_forward(model, carry, batch); end
    Lp = Float64.(out["logits"])
    L64 = permutedims(reshape(l64, 12, 47, 8), (3, 2, 1)); L32 = permutedims(reshape(l32, 12, 47, 8), (3, 2, 1))
    q(L) = [C.p2(L[b, s, 9], L[b, s, 8]) for b in 1:8, s in (46, 47)]
    lq(L) = L[:, 46:47, 8:9]
    println(f, ": logits at Q, tokens 7/8: TrmC0 vs TrmPort ", @sprintf("%.2e", maximum(abs.(lq(L32) .- lq(Lp)))), ", TrmC0 vs TrmDet ", @sprintf("%.2e", maximum(abs.(lq(L32) .- lq(Ld)))),
            ", vs Float64: TrmC0 ", @sprintf("%.2e", maximum(abs.(lq(L32) .- lq(L64)))), " TrmPort ", @sprintf("%.2e", maximum(abs.(lq(Lp) .- lq(L64)))), " TrmDet ", @sprintf("%.2e", maximum(abs.(lq(Ld) .- lq(L64)))))
    println("   p at Q: TrmC0 vs TrmPort ", @sprintf("%.2e", maximum(abs.(q(L32) .- q(Lp)))), ", TrmC0 vs TrmDet ", @sprintf("%.2e", maximum(abs.(q(L32) .- q(Ld)))), ", TrmPort vs TrmDet ", @sprintf("%.2e", maximum(abs.(q(Lp) .- q(Ld)))))
    dd = abs.(L32 .- Lp); i = argmax(dd)
    println("   largest TrmC0-TrmPort logit difference at (example, position 0-based, token) = (", i[1], ", ", i[2] - 1, ", ", i[3] - 1, "): ", @sprintf("%.3f", dd[i]),
            "; max over positions 0..44 ", @sprintf("%.2e", maximum(dd[:, 1:45, :])), ", over 45..46 ", @sprintf("%.2e", maximum(dd[:, 46:47, :])))
end
