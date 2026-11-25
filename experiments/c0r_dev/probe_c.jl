# S71 dev experiment C: the proposed G1 criterion (max |p| difference at the question positions <= 1e-4, between TrmC0 and TrmPort
# in Float32, and TrmC0 in Float64) on the saved S64 weights, over many distinct inputs of one eval-family stream (not a gate; reads out/ only).
# Usage: julia --project=. -t 1 experiments/c0r_dev/probe_c.jl
include(joinpath(@__DIR__, "lib.jl"))
const C = TrmC0
function loadp(f)
    b = read(f); p = C.Params{Float32}(); o = 0
    for a in C.plist(p); n = length(a); a .= reshape(reinterpret(Float32, b[o+1:o+4n]), size(a)); o += 4n; end
    o == length(b) || error("size"); return p
end
function final(p, cfg, tok, T)
    q = C.convert_params(T, p); w = C.Work{T}(size(tok, 2), 0, ROPE...)
    zH, _ = C.final_state!(w, q, cfg, tok); lg = Float64.(q.lm) * Float64.(zH)
    return [C.p2(lg[9, (b-1)*S+c], lg[8, (b-1)*S+c]) for c in (46, 47), b in 1:size(tok, 2)]
end
function port(p, cfg, tok)
    B = size(tok, 2)
    names = [:hidden_size, :num_heads, :puzzle_emb_ndim, :seq_len, :puzzle_emb_len, :mlp_t, :expansion, :rms_norm_eps, :vocab_size,
             :pos_encodings, :rope_theta, :L_layers, :H_cycles, :L_cycles, :halt_max_steps, :batch_size, :num_puzzle_identifiers]
    vals = Any[H, NH, 0, S, 0, false, 4.0, 1e-5, V, "rope", 10000.0, NL, cfg.Hc, cfg.Lc, cfg.hmax, B, 1]
    model = TrmPort.ACTModel((names = names, values = vals), C.official_state(p))
    batch = Dict{String,Any}("inputs" => Int.(permutedims(tok)), "puzzle_identifiers" => zeros(Int, B))
    carry = TrmPort.initial_carry(model, batch); out = nothing
    for _ in 1:cfg.hmax; carry, out = TrmPort.act_forward(model, carry, batch); end
    lg = out["logits"]   # (B, S, V)
    return [C.p2(Float64(lg[b, c, 9]), Float64(lg[b, c, 8])) for c in (46, 47), b in 1:B]
end
const NIN = 64
for fam in ("stat", "rev"), (mname, cfg) in (("TRM", CFG_TRM), ("TRM-1x1", CFG_1X1))
    f = joinpath(EXP, "c0_trm", "out", "weights", "obs-full_$(fam)_$(mname).bin")
    isfile(f) || (println("missing ", f); continue)
    p = loadp(f); st = obs_stream(1074, fam); es = exset(st, true)
    cols = unique(c -> es.tok[:, c], 1:size(es.tok, 2))[1:NIN]
    tok = es.tok[:, cols]
    p32 = final(p, cfg, tok, Float32); p64 = final(p, cfg, tok, Float64); pp = port(p, cfg, tok)
    println(fam, " ", mname, ": ", NIN, " distinct inputs; max|p C0(f32)-Port(f32)| ", @sprintf("%.2e", maximum(abs.(p32 .- pp))),
            "; max|p C0(f32)-C0(f64)| ", @sprintf("%.2e", maximum(abs.(p32 .- p64))),
            "; max|p Port(f32)-C0(f64)| ", @sprintf("%.2e", maximum(abs.(pp .- p64))), "; proposed criterion (<= 1e-4) ",
            maximum(abs.(p32 .- pp)) <= 1e-4)
end
