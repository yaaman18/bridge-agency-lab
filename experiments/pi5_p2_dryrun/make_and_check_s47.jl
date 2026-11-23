# Phase 2 dry-run: synthetic seq_len=47, vocab=12, config a TRMDET1 bundle + 1-ulp negative control.
# Verifies Julia TrmDet.jl vs Mac rust/trm-det bit-exactness BEFORE S64 weights finish, and stages bundles
# for Pi 5 P2-BIT + P2-TIME pre-calibration (real Phase 2 re-verifies with frozen S64 trained weights).
# Strictly read-only against experiments/trm/det/TrmDet.jl and rust/trm-det/.

using Random
using SHA
using Printf

const ROOT = abspath(joinpath(@__DIR__, "..", ".."))
include(joinpath(ROOT, "experiments", "trm", "det", "TrmDet.jl"))
using .TrmDet: Rec, RecF, RecI, write_recs, read_recs, Model, run_bundle, MAGIC_BUNDLE, MAGIC_OUT, F32, to_rm

const OUT_DIR = joinpath(@__DIR__, "out")
mkpath(OUT_DIR)

function make_s47_bundle(seed::Integer; mutate_1ulp::Bool = false)
    rng = Xoshiro(seed)
    B = 1; S = 47; V = 12; H = 32; nh = 4; hd = H ÷ nh; I = 256
    H_cycles = 3; L_cycles = 6; L_layers = 2; halt_max = 3; pos = 1; nsteps = 4
    eps = F32(1e-5)

    cfgv = Int32[B, S, V, H, nh, I, H_cycles, L_cycles, L_layers, halt_max, pos, 0, nsteps]
    recs = Rec[
        RecI("cfg", (13,), cfgv),
        RecF("const", (3,), F32[eps, F32(0.707106781), sqrt(F32(H))]),
    ]

    rvec(dims) = F32.(0.05 .* randn(rng, dims...))
    add_mat!(name, dims) = push!(recs, RecF(name, dims, vec(F32.(to_rm(rvec(dims))))))

    # Build weights matching S60 config a (sorted name order)
    state = Dict{String,Array{Float32}}(
        "inner.H_init" => rvec((H,)),
        "inner.L_init" => rvec((H,)),
        "inner.embed_tokens.embedding_weight" => rvec((V, H)),
        "inner.lm_head.weight" => rvec((V, H)),
        "inner.q_head.weight" => rvec((2, H)),
        "inner.q_head.bias" => F32[-2.0f0, -2.0f0], # negative bias so ACT runs all halt_max=3 steps (worst-case 9 H-cycles!)
    )
    for l in 0:(L_layers - 1)
        p = "inner.L_level.layers.$(l)"
        state["$(p).self_attn.qkv_proj.weight"] = rvec((3 * H, H))
        state["$(p).self_attn.o_proj.weight"] = rvec((H, H))
        state["$(p).mlp.gate_up_proj.weight"] = rvec((2 * I, H))
        state["$(p).mlp.down_proj.weight"] = rvec((H, I))
    end
    if mutate_1ulp
        w = state["inner.L_level.layers.0.self_attn.qkv_proj.weight"]
        w[1] = nextfloat(w[1])
    end

    for name in sort!(collect(keys(state)))
        a = state[name]
        push!(recs, RecF(name, size(a), F32.(to_rm(a))))
    end

    # RoPE tables (S, hd) = (47, 8)
    inv_freq = [1.0 / (10000.0^(2 * (j - 1) / hd)) for j in 1:(hd ÷ 2)]
    cs = Matrix{F32}(undef, S, hd)
    sn = Matrix{F32}(undef, S, hd)
    for s in 1:S
        for j in 1:(hd ÷ 2)
            ang = (s - 1) * inv_freq[j]
            c = F32(cos(ang)); snv = F32(sin(ang))
            cs[s, j] = c; cs[s, j + hd ÷ 2] = c
            sn[s, j] = snv; sn[s, j + hd ÷ 2] = snv
        end
    end
    push!(recs, RecF("rope.cos", size(cs), F32.(to_rm(cs))), RecF("rope.sin", size(sn), F32.(to_rm(sn))))

    for k in 1:3
        toks = Int32.(rand(rng, 0:(V - 1), B, S))
        push!(recs, RecI("x$(k).inputs", (B, S), Int32.(to_rm(toks))), RecI("x$(k).pid", (B,), Int32[0]))
    end
    push!(recs, RecI("steps.input", (4,), Int32[1, 2, 3, 1]))
    push!(recs, RecI("mixed.input", (1,), Int32[2]), RecI("mixed.start_halted", (B,), Int32[0]))
    recs
end

b_ok = joinpath(OUT_DIR, "s47_dryrun.bin")
b_1ulp = joinpath(OUT_DIR, "s47_dryrun_1ulp.bin")
write_recs(b_ok, MAGIC_BUNDLE, make_s47_bundle(660001; mutate_1ulp = false))
write_recs(b_1ulp, MAGIC_BUNDLE, make_s47_bundle(660001; mutate_1ulp = true))

# Run Julia canonical TrmDet.jl
out_jl_ok = joinpath(OUT_DIR, "out_julia_ok.bin")
out_jl_1ulp = joinpath(OUT_DIR, "out_julia_1ulp.bin")
for (bp, op) in ((b_ok, out_jl_ok), (b_1ulp, out_jl_1ulp))
    recs = read_recs(bp, MAGIC_BUNDLE)
    m = Model(recs)
    t = @elapsed out, _, _ = run_bundle(m, recs)
    write_recs(op, MAGIC_OUT, out)
    @printf("julia %-20s %.3f s  sha=%s\n", basename(bp), t, bytes2hex(sha256(read(op))))
end

sha_ok = bytes2hex(sha256(read(out_jl_ok)))
sha_1ulp = bytes2hex(sha256(read(out_jl_1ulp)))
@assert sha_ok != sha_1ulp "1-ulp mutation must change output SHA!"

# Compare against Mac rust/trm-det if release binary exists
mac_bin = joinpath(ROOT, "rust", "trm-det", "target", "release", "trm-det")
if isfile(mac_bin)
    out_mac_ok = joinpath(OUT_DIR, "out_mac_ok.bin")
    out_mac_1ulp = joinpath(OUT_DIR, "out_mac_1ulp.bin")
    run(`$mac_bin $b_ok $out_mac_ok`)
    run(`$mac_bin $b_1ulp $out_mac_1ulp`)
    sha_mac_ok = bytes2hex(sha256(read(out_mac_ok)))
    sha_mac_1ulp = bytes2hex(sha256(read(out_mac_1ulp)))
    println("mac_ok   sha=", sha_mac_ok)
    println("mac_1ulp sha=", sha_mac_1ulp)
    @assert sha_mac_ok == sha_ok "Mac Rust vs Julia mismatch on s47_dryrun!"
    @assert sha_mac_1ulp == sha_1ulp "Mac Rust vs Julia mismatch on s47_dryrun_1ulp!"
    println("PASS: Julia == Mac Rust bit-exact on seq_len=47 (and 1-ulp neg control caught)!")
else
    println("NOTE: Mac release binary not found at ", mac_bin)
end
