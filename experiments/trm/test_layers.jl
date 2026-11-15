# S56 手 2: 層・ブロック・埋め込みの中間の量を fixtures（公式の出力）と照らす。
# 合格: 形は完全一致、全部有限、要素ごとに |得た値 − 正解| <= 1e-5 + 1e-5*|正解|。
# 走らせ方（ラボの根から）: julia --project=. experiments/trm/test_layers.jl
include(joinpath(@__DIR__, "TrmPort.jl"))
using .TrmPort
using Printf

const HERE = @__DIR__
const OUT = joinpath(HERE, "results-layers.out")
const TOL_ABS = 1e-5
const TOL_REL = 1e-5
const CONFIGS = ["a", "b", "c", "d", "e"]
const QUANTITIES = ["input_embeddings", "reset_z_H", "reset_z_L", "block_input_h",
                    "block_first_op_out", "block_norm1_out", "block_mlp_out", "block_norm2_out"]
const ROPE_KEYS = ["cos_cached", "sin_cached"]

const lines = String[]
logln(s) = (push!(lines, s); println(s))
flush_out() = open(OUT, "w") do io
    for l in lines; println(io, l); end
end
gname(cfg, k) = string(cfg, ".", k)          # 文字列の補間は使わない（連結で書く）

"cfg から puzzle_emb_len を決める（Inner と同じ規則。埋め込みの形の期待値に使う）。"
function puzzle_emb_len_of(cfg)
    pel = Int(TrmPort._getattr(cfg, :puzzle_emb_ndim))
    pl = Int(TrmPort._getattr(cfg, :puzzle_emb_len))
    return pl == 0 ? cld(pel, Int(TrmPort._getattr(cfg, :hidden_size))) : pl
end

"""行優先の data（fixtures の並び）を、形 shape のまま列優先の配列として読む誤り（負の対照 (ix)）。
_to_julia は reshape(data, reverse(shape)...) して permutedims で戻すが、ここでは逆順にせずに reshape するので、
形は同じで値の並びだけが行優先と列優先の取り違えになる。"""
function rowmajor_as_colmajor(data, shape)
    v = F32.(collect(data))::Vector{F32}
    sh = Int[Int(x) for x in shape]
    isempty(sh) && return fill(v[1])
    return reshape(v, sh...)
end

"model(cfg, state; bad) → Inner。state の名前から公式の名前の重みを入れる。"
function build(cfg, state::AbstractDict; bad = :none)
    data = Dict(k => copy(v) for (k, v) in state)     # 入力を書き換えない（bad = :ix がここだけを変える）
    if bad == :ix
        # (ix): 形は保ったまま、行優先の data を列優先として読む（形は同じで値の並びが違う）
        for (k, v) in state
            data[k] = rowmajor_as_colmajor(TrmPort._to_rowmajor(v), size(v))
        end
    end
    inner = TrmPort.Inner(cfg)
    inner.embed_tokens = CastedEmbedding(data["inner.embed_tokens.embedding_weight"])
    inner.lm_head = CastedLinear(data["inner.lm_head.weight"])
    inner.q_head = CastedLinear(data["inner.q_head.weight"], data["inner.q_head.bias"])
    inner.H_init = reshape(copy(data["inner.H_init"]), 1, 1, :)   # (hidden,) → (1, 1, hidden)
    inner.L_init = reshape(copy(data["inner.L_init"]), 1, 1, :)
    if inner.puzzle_emb !== nothing
        inner.puzzle_emb = CastedEmbedding(data["inner.puzzle_emb.weights"])
    end
    if inner.embed_pos !== nothing
        inner.embed_pos = CastedEmbedding(data["inner.embed_pos.embedding_weight"])
    end
    expn = TrmPort._getattr(cfg, :expansion)
    for (i, blk) in enumerate(inner.L_level.layers)
        pre = string("inner.L_level.layers.", i - 1)
        if blk.mlp_t !== nothing
            blk.mlp_t = SwiGLU(size(data[string(pre, ".mlp_t.gate_up_proj.weight")], 2), expn;
                               gate_up = data[string(pre, ".mlp_t.gate_up_proj.weight")],
                               down = data[string(pre, ".mlp_t.down_proj.weight")])
        else
            qkv = data[string(pre, ".self_attn.qkv_proj.weight")]
            nh = blk.self_attn.num_heads
            hd = blk.self_attn.head_dim
            blk.self_attn = Attention(blk.self_attn.hidden_size, hd, nh, nh, false,
                                      CastedLinear(qkv), CastedLinear(data[string(pre, ".self_attn.o_proj.weight")]),
                                      bad == :rope_value)
        end
        dp = data[string(pre, ".mlp.down_proj.weight")]
        if bad == :weight && i == 1
            dp = copy(dp)
            dp[1, 1] += Float32(0.01)
        end
        blk.mlp = SwiGLU(size(data[string(pre, ".mlp.gate_up_proj.weight")], 2), expn;
                         gate_up = data[string(pre, ".mlp.gate_up_proj.weight")], down = dp)
        blk.bad_norm = bad == :norm_before_transpose ? :norm1 : :none
    end
    return inner
end

"中間の量を公式と同じ順で取る（最初の H 周回・最初のブロック）。block_first_op は mlp_t かどうか。"
function intermediates(inner, x)
    emb = input_embeddings(inner, x["inputs"], x["puzzle_identifiers"])
    bs = size(emb, 1)
    z_H, z_L = reset_carry(inner, fill(true, bs), zeros(Float32, size(emb)), zeros(Float32, size(emb)))
    blk = inner.L_level.layers[1]
    hin = z_L .+ (z_H .+ emb)
    cs = inner.rotary_emb
    n1 = norm1(blk, cs, hin)
    return Dict{String,Any}(
        "input_embeddings" => emb, "reset_z_H" => z_H, "reset_z_L" => z_L,
        "block_input_h" => hin,
        "block_first_op_out" => first_op(blk, cs, hin),
        "block_norm1_out" => n1,
        "block_mlp_out" => mlp_fn(blk, n1),
        "block_norm2_out" => blk(cs, hin))
end

"compare(got, want) → (ok, maxdiff, worst_want, msg)。形の不一致も「合わない」。got と want の両方が有限であること。"
function compare(got, want)
    got isa AbstractArray || return (false, Inf, NaN, "not an array")
    want isa AbstractArray || return (false, Inf, NaN, "oracle is not an array")
    size(got) != size(want) && return (false, Inf, NaN, string("shape ", size(got), " != ", size(want)))
    all(isfinite, got) || return (false, Inf, NaN, "non-finite value in got")
    all(isfinite, want) || return (false, Inf, NaN, "non-finite value in want")
    md, ww = 0.0, 0.0
    ok = true
    for (g, w) in zip(got, want)
        d = abs(Float64(g) - Float64(w))
        if d > md
            md, ww = d, Float64(w)
        end
        ok &= d <= TOL_ABS + TOL_REL * abs(Float64(w))
    end
    return (ok, md, ww, ok ? "ok" : "over tolerance")
end

"fmt_num(x) → 指数表記の文字列を「.3e」相当（e に + を付けず、符号はそのまま e の後ろ）で作る。"
function fmt_num(x)
    v = Float64(x)
    isfinite(v) || return string(v)
    body = @sprintf("%.2e", v)
    # "%.2e" の指数は 3 桁（例 e-08）。2 桁（.3e 相当）に直し、指数の符号も残す
    return string(body[1:end-3], body[end-2:end-1], body[end])
end

"verdict(ok, md, ww, msg) → 結果ファイルに入れる合否の一行。落ちたら最大の絶対差・正解の値・理由を残す。"
function verdict(ok, md, ww, msg)
    ok && return string("PASS (max_abs_diff ", fmt_num(md), ")")
    return string("FAIL (max_abs_diff ", fmt_num(md), " at want value ", ww, "; ", msg, ")")
end

"main: 5 構成 × W1 の中間の量と rope、W0 の rope と埋め込み（形と有限のみ）。最初にずれた量を返す。"
function main()
    logln("S56 手 2: TrmPort.jl の層・ブロック・埋め込みの照合（fixtures を正解とする）")
    logln("tolerance: |got - want| <= $(TOL_ABS) + $(TOL_REL)*|want| elementwise; shape exact; all finite (got and want)")
    failures = String[]
    firstmiss = ""
    fail(msg) = (push!(failures, msg); firstmiss == "" && (firstmiss = msg); nothing)
    for c in CONFIGS
        fx1 = load_fixture(joinpath(HERE, "fixtures", string(c, "_W1.json")))
        fx0 = load_fixture(joinpath(HERE, "fixtures", string(c, "_W0.json")))
        it = fx1.intermediates
        got = try
            intermediates(build(fx1.config, fx1.state), fx1.inputs["x1"])
        catch e
            logln(string("  W1 intermediates: FAIL (threw ", sprint(showerror, e), ")"))
            fail(string("config ", c, " W1 intermediates: FAIL (threw ", sprint(showerror, e), ")"))
            nothing
        end
        if got === nothing
            logln(string("  config ", c, " skipped: the W1 quantities could not be computed (already recorded as a failure)"))
            continue
        end
        inner = build(fx1.config, fx1.state)
        logln(string("\n== config ", c, " (W1): hidden=", TrmPort._getattr(fx1.config, :hidden_size),
                     " pos=", TrmPort._getattr(fx1.config, :pos_encodings),
                     " mlp_t=", TrmPort._getattr(fx1.config, :mlp_t),
                     " puzzle_emb_ndim=", TrmPort._getattr(fx1.config, :puzzle_emb_ndim)))
        # 構成の mlp_t と block_first_op（種類の名前）が合っていること
        want_op = get(it, "block_first_op", "?")
        have_op = inner.L_level.layers[1].mlp_t !== nothing ? "mlp_t" : "self_attn"
        logln(string("  block_first_op oracle=", want_op, " ours=", have_op))
        if want_op != have_op
            fail(string("config ", c, " W1 block_first_op: oracle ", want_op, " ours ", have_op))
        end
        # rope が要るかは構成（pos_encodings）で決める。要るなら正解が欠けていれば失敗
        rope_needed = String(TrmPort._getattr(fx1.config, :pos_encodings)) == "rope"
        for k in ROPE_KEYS
            if rope_needed && !haskey(fx1.rope, k)
                logln(string("  rope ", k, " FAIL (no oracle in fixture)"))
                fail(string("config ", c, " W1 rope ", k, ": no oracle in fixture"))
                continue
            end
            haskey(fx1.rope, k) || continue
            ok, md, ww, msg = compare(inner.rotary_emb === nothing ? nothing : inner.rotary_emb[k == "cos_cached" ? 1 : 2],
                                      fx1.rope[k])
            logln(string("  rope ", k, " max_abs_diff ", fmt_num(md), "  ", verdict(ok, md, ww, msg)))
            ok || fail(string("config ", c, " W1 rope ", k, ": max_abs_diff ", md, " (", msg, ")"))
        end
        for q in QUANTITIES
            if !haskey(it, q)
                logln(string("  ", q, " FAIL (no oracle for required quantity)"))
                fail(string("config ", c, " W1 ", q, ": no oracle for required quantity"))
                continue
            end
            ok, md, ww, msg = compare(got[q], it[q])
            logln(string("  ", q, " max_abs_diff ", fmt_num(md), "  ", verdict(ok, md, ww, msg)))
            ok || fail(string("config ", c, " W1 ", q, ": max_abs_diff ", md, " at want value ", ww, " (", msg, ")"))
        end
        # W0 の rope: 構成が rope を要するときだけ検査し、要るのに正解が無ければ失敗
        inner0 = build(fx0.config, fx0.state)
        rope0_needed = String(TrmPort._getattr(fx0.config, :pos_encodings)) == "rope"
        for k in ROPE_KEYS
            if rope0_needed && !haskey(fx0.rope, k)
                logln(string("  W0 rope ", k, " FAIL (no oracle in fixture)"))
                fail(string("config ", c, " W0 rope ", k, ": no oracle in fixture"))
                continue
            end
            haskey(fx0.rope, k) || continue
            ok, md, ww, msg = compare(inner0.rotary_emb === nothing ? nothing : inner0.rotary_emb[k == "cos_cached" ? 1 : 2],
                                      fx0.rope[k])
            logln(string("  W0 rope ", k, " max_abs_diff ", fmt_num(md), "  ", verdict(ok, md, ww, msg)))
            ok || fail(string("config ", c, " W0 rope ", k, ": max_abs_diff ", md, " (", msg, ")"))
        end
        # W0 には intermediates がないので input_embeddings には正解が無い。
        # 比べられないものを「比較済み」と出さない: 計算し、形と有限だけを検査する（正解との照合ではない）。
        x0 = fx0.inputs["x1"]
        h = Int(TrmPort._getattr(fx0.config, :hidden_size))
        wantshape = (size(x0["inputs"], 1), puzzle_emb_len_of(fx0.config) + size(x0["inputs"], 2), h)
        havew0 = haskey(fx0.intermediates isa AbstractDict ? fx0.intermediates : Dict{String,Any}(), "input_embeddings")
        e0 = try
            input_embeddings(inner0, x0["inputs"], x0["puzzle_identifiers"])
        catch e
            logln(string("  W0 input_embeddings: FAIL (threw ", sprint(showerror, e), ")"))
            fail(string("config ", c, " W0 input_embeddings: FAIL (threw ", sprint(showerror, e), ")"))
            nothing
        end
        # 例外は出ないが配列でない値（nothing など）が返った場合も、検査を飛ばさずに失敗として記録する
        if e0 === nothing
            logln("  W0 input_embeddings: FAIL (not an array)")
            fail(string("config ", c, " W0 input_embeddings: FAIL (returned a non-array value or threw)"))
        elseif !(e0 isa AbstractArray)
            logln(string("  W0 input_embeddings: FAIL (not an array: ", typeof(e0), ")"))
            fail(string("config ", c, " W0 input_embeddings: FAIL (not an array: ", typeof(e0), ")"))
        else
            shape_ok = size(e0) == wantshape
            finite_ok = all(isfinite, e0)
            ok = shape_ok && finite_ok && !havew0
            logln(string("  W0 input_embeddings: shape+finite only (no reference in fixture) — shape ",
                         size(e0), shape_ok ? " == " : " != ", wantshape, " ", shape_ok ? "ok" : "FAIL",
                         "; finite=", finite_ok, " ", finite_ok ? "ok" : "FAIL", "  ", ok ? "PASS" : "FAIL"))
            ok || fail(string("config ", c, " W0 input_embeddings: shape ", size(e0), " (want ", wantshape,
                              ") finite=", finite_ok, " reference_in_fixture=", havew0))
        end
        havew0 && fail(string("config ", c, " W0 input_embeddings: fixture has a reference; shape+finite only is not enough"))
    end
    return failures, firstmiss
end

"外れた要素の数と最大の絶対差（形が違えば全部外れ）。want との差だけで決める（親の base は使わない）。"
function off_and_value(got, want)
    got isa AbstractArray || return (length(want), Inf)
    size(got) == size(want) || return (length(want), Inf)
    n, md = 0, 0.0
    for (g, w) in zip(got, want)
        d = abs(Float64(g) - Float64(w))
        if !(d <= TOL_ABS + TOL_REL * abs(Float64(w)))
            n += 1
            md = max(md, d)
        end
    end
    return (n, md)
end

"""negative_controls(base) → [(id, caught, msg)]。
合否は「注入した読みの量」と「fixture の正解」の差が許容差（|得た値 − 正解| <= 1e-5 + 1e-5*|正解|）を越えることで決める。
base[c][q]（通常の読み）との差は補助の診断として書くだけで、関門にしない。
狙った量を算出できずに例外になったら、その対照は失敗（FAILED）。例外は握り潰さない。"""
function negative_controls(base)
    out = Tuple{String,Bool,String}[]
    function fail_ctl(id, desc, c, q, why)
        push!(out, (id, false, string("negative control (", id, ") FAILED: ", desc, " — config ", c, " ", q, " ", why)))
        return nothing
    end
    function run_ctl(id, desc, c, q, bad, adjust = identity)
        fx = load_fixture(joinpath(HERE, "fixtures", string(c, "_W1.json")))
        it = fx.intermediates
        haskey(it isa AbstractDict ? it : Dict{String,Any}(), q) || return fail_ctl(id, desc, c, q, "has no oracle in the fixture")
        want = it[q]
        want isa AbstractArray || return fail_ctl(id, desc, c, q, "oracle is not an array")
        all(isfinite, want) || return fail_ctl(id, desc, c, q, "oracle has a non-finite value")
        got = try
            intermediates(adjust(build(fx.config, fx.state; bad = bad)), fx.inputs["x1"])[q]
        catch e
            return fail_ctl(id, desc, c, q, string("threw ", sprint(showerror, e),
                                                   " (the quantity could not be computed)"))
        end
        # 対照側の事前検査: 配列・正解と同じ形・全部有限。満たさなければ「対照が成立していない」＝ FAILED
        got isa AbstractArray || return fail_ctl(id, desc, c, q, string("control value is not an array: ", typeof(got)))
        size(got) == size(want) || return fail_ctl(id, desc, c, q, string("control shape ", size(got),
                                                                          " != oracle shape ", size(want)))
        all(isfinite, got) || return fail_ctl(id, desc, c, q, "control value has a non-finite value (NaN/Inf)")
        n, md = off_and_value(got, want)
        caught = n > 0
        tag = caught ? string("negative control (", id, ") caught: ") : string("negative control (", id, ") NOT CAUGHT: ")
        mdnum = isfinite(md) ? string(fmt_num(md)) : "non-finite"    # 表示だけ。判定は off_and_value のとおり
        msg = string(tag, desc, " — config ", c, " ", q, ": fixture off elements ", n,
                     " max_abs_diff vs fixture ", mdnum,
                     " (diagnostic vs usual read: ", diag(got, get(base[c], q, nothing)), ")")
        push!(out, (id, caught, msg))
        return nothing
    end
    run_ctl("i", "mlp.down_proj.weight[1,1] + 0.01 of layer 0", "a", "block_mlp_out", :weight)
    run_ctl("vii", "rope applied to value too", "a", "block_first_op_out", :rope_value)
    run_ctl("viii", "mlp_t first norm before transpose", "c", "block_norm1_out", :norm_before_transpose)
    run_ctl("ix", "row-major data read as column-major, same shape (all weights)", "a", "block_norm2_out", :ix)
    # (x): reset が z_L に H_init を、z_H に L_init を書く（reset_carry の 0 引数の置き換え）
    run_ctl("x", "reset_carry writes H_init into z_L (and L_init into z_H)", "a", "reset_z_L", :none,
            inner -> (h0 = copy(inner.H_init); l0 = copy(inner.L_init);
                      inner.H_init = l0; inner.L_init = h0; inner))
    return out
end

"diag(got, base) → 通常の読みとの最大の絶対差（補助の診断だけ。合否には使わない）。"
function diag(got, base)
    (got isa AbstractArray && base isa AbstractArray && size(got) == size(base)) || return "n/a"
    return @sprintf("%.3e", maximum(abs.(Float64.(got) .- Float64.(base))))
end

function run()
    failures, firstmiss = main()
    logln("\n== negative controls")
    base = Dict{String,Any}()
    for c in CONFIGS
        fx = load_fixture(joinpath(HERE, "fixtures", string(c, "_W1.json")))
        base[c] = intermediates(build(fx.config, fx.state), fx.inputs["x1"])
    end
    ctl = negative_controls(base)
    for (_, _, msg) in ctl
        logln(msg)
    end
    caught = count(x -> x[2], ctl)
    logln("\n== summary")
    logln(string("quantities compared with oracle: ", length(CONFIGS), " configs x W1 (", length(QUANTITIES),
                 " quantities plus rope when the config is rope); W0: rope when the config is rope,",
                 " input_embeddings shape+finite only (no reference in fixture); failures: ", length(failures)))
    logln(string("negative controls caught: ", caught, "/", length(ctl)))
    isempty(firstmiss) || logln(string("first mismatch: ", firstmiss))
    ok = isempty(failures) && caught == length(ctl)
    logln(ok ? "ALL PASS" : "FAILED")
    flush_out()
    return ok
end

# 途中で例外が起きても、最後に必ず結果ファイルへ最終行（FAILED）を書き、exit 1 にする。
ok = try
    run()
catch e
    logln(string("\nFAILED: unexpected exception: ", sprint(showerror, e, catch_backtrace())))
    logln("FAILED")
    false
finally
    # 最終行が ALL PASS / FAILED のどちらかになっているかを確かめ、例外時に FAILED を補う
    if isempty(lines) || !(lines[end] in ("ALL PASS", "FAILED"))
        !isempty(lines) && lines[end] == "FAILED" || push!(lines, "FAILED")
    end
    flush_out()
end
exit(ok && lines[end] == "ALL PASS" ? 0 : 1)
