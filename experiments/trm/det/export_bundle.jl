# S60 §2: bundles (binary records) from the frozen S56 fixtures (official Python values). Read-only use of TrmPort's loader.
# Usage: julia --project=../../.. export_bundle.jl   (writes bundles/<c>_<w>.bin for a,b,e x W0,W1 and bundles/SHA256SUMS)
include(joinpath(@__DIR__, "..", "TrmPort.jl"))
include(joinpath(@__DIR__, "TrmDet.jl"))
using .TrmDet: Rec, RecF, RecI, write_recs, MAGIC_BUNDLE, to_rm, F32

attr(cfg, key) = (i = findfirst(==(key), cfg.names); i === nothing ? nothing : cfg.values[i])

function bundle(c, w)
    fx = TrmPort.load_fixture(joinpath(@__DIR__, "..", "fixtures", string(c, "_", w, ".json")))
    cfg = fx.config
    attr(cfg, :mlp_t) == false || error("mlp_t not supported")
    attr(cfg, :puzzle_emb_ndim) == 0 && attr(cfg, :puzzle_emb_len) == 0 || error("puzzle_emb not supported")
    B, S, V, H, nh = (Int(attr(cfg, k)) for k in (:batch_size, :seq_len, :vocab_size, :hidden_size, :num_heads))
    I = size(fx.state["inner.L_level.layers.0.mlp.gate_up_proj.weight"], 1) ÷ 2
    posname = attr(cfg, :pos_encodings)
    pos = posname == "rope" ? 1 : posname == "learned" ? 2 : error("pos_encodings")
    eps = attr(cfg, :rms_norm_eps); eps === nothing && (eps = 1e-5)
    nsteps = length(fx.steps)
    nsteps == 4 || error("expected 4 steps")
    cfgv = Int32[B, S, V, H, nh, I, attr(cfg, :H_cycles), attr(cfg, :L_cycles), attr(cfg, :L_layers),
                 attr(cfg, :halt_max_steps), pos, 0, nsteps]
    recs = Rec[RecI("cfg", (13,), cfgv), RecF("const", (3,), F32[F32(eps), F32(0.707106781), sqrt(F32(H))])]
    for name in sort!(collect(keys(fx.state)))
        a = fx.state[name]
        push!(recs, RecF(name, size(a), F32.(to_rm(a))))
    end
    if pos == 1
        cs, sn = fx.rope["cos_cached"], fx.rope["sin_cached"]
        size(cs) == (S, H ÷ nh) && size(sn) == (S, H ÷ nh) || error("rope table shape")
        push!(recs, RecF("rope.cos", size(cs), F32.(to_rm(cs))), RecF("rope.sin", size(sn), F32.(to_rm(sn))))
    end
    for k in 1:3
        x = fx.inputs[string("x", k)]
        push!(recs, RecI(string("x", k, ".inputs"), size(x["inputs"]), Int32.(to_rm(x["inputs"]))),
              RecI(string("x", k, ".pid"), size(x["puzzle_identifiers"]), Int32.(vec(x["puzzle_identifiers"]))))
    end
    xid(s) = (s in ("x1", "x2", "x3")) ? Int32(parse(Int, s[2:end])) : error("input name")
    push!(recs, RecI("steps.input", (4,), Int32[xid(fx.steps[string("step", k)]["passed_input"]) for k in 1:4]))
    mr = fx.mixed_reset
    push!(recs, RecI("mixed.input", (1,), Int32[xid(mr["input"])]),
          RecI("mixed.start_halted", (B,), Int32[x ? 1 : 0 for x in Bool.(mr["start_halted"])]))
    return recs
end

for c in ("a", "b", "e"), w in ("W0", "W1")
    p = joinpath(@__DIR__, "bundles", string(c, "_", w, ".bin"))
    write_recs(p, MAGIC_BUNDLE, bundle(c, w))
    println("wrote ", p)
end
