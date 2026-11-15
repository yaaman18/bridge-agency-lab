# S56 診断（測定だけ）: 構成 a・c・d の差が丸めの増幅か、本当の経路の差かを測る。
# TrmPort（SamsungSAILMontreal/TinyRecursiveModels, commit 7de0d20 の移植, MIT: LICENSE-upstream-MIT.txt）は読むだけ。
# diag/TrmPort_f64.jl は TrmPort.jl の本文から「語として」の型トークンだけを置換してこのスクリプトが作る
# （文字列・コメントの中は置換しない。公式 models/layers.py 163-169 の rms_norm は入力を Float32 で計算し元の型に
#  戻すので、写しも入力を Float32 に上げて計算し Float64 に戻す。rope の cos/sin は公式と同じ Float32 の表）。
# module TrmPortF64 として include する。
const REPORT = IOBuffer()   # results-diag-precision.out（標準出力にも同じものを出す）
say(io, xs...) = println(io, xs...)
using JSON  # diag/ の JSON を読むだけ
const HERE = @__DIR__
const F64_PATH = joinpath(HERE, "diag", "TrmPort_f64.jl")
include(joinpath(HERE, "diag_precision_rms.txt"))   # source_lines・replace_tokens・RMS_NORM_F64（下の生成が使う）
include(joinpath(HERE, "TrmPort.jl"))
"""TrmPort.jl の本文から、写し diag/TrmPort_f64.jl を作る（盲目的な文字列置換をしない）。
各行を replace_tokens（文字列・コメントの外の語の境界の Float32 / F32 と接尾辞付きリテラルだけ）で替え、
rms_norm の def の行から単独の end の行までだけを rms_body（公式と同じ型の扱い）に差し替え、
module の行の名を TrmPortF64 にする。戻り値は (写しの本文, 置換した数)。"""
function make_f64_source(src, rms_body)
    lines_src = source_lines(src)
    # rms_norm の def の行と、その次の単独の end の行
    d = findfirst(x -> occursin("function rms_norm(", x), lines_src)
    d === nothing && error("rms_norm not found in TrmPort.jl")
    er = findfirst(==("end"), lines_src[first(d):end])
    er === nothing && error("rms_norm end not found in TrmPort.jl")
    e = first(d) + first(er) - 1
    # 写しの行: rms_norm の外は転置の線を 1 行ずつ通し、rms_norm は写しの行に替える
    kept = String[]
    append!(kept, String.(lines_src[1:first(d) - 1]))
    append!(kept, String.(rms_body))
    append!(kept, String.(lines_src[e + 1:end]))
    out = String[]
    n_replaced = 0
    for (jj, line) in enumerate(kept)
        r = replace_tokens(String(line))
        n_replaced += r[2]
        push!(out, r[1])
        jj == 1 && (out[1] = "module TrmPortF64")          # 1 行目の module の名だけを替える
    end
    return (join(out, "\n"), n_replaced, first(d), e)
end

"写しを diag/TrmPort_f64.jl に書く。戻り値は外側の置換したトークンの数。"
function write_f64_port(src)
    rms_body = RMS_NORM_F64                      # 写しの rms_norm（.out にも写す）
    (body, k) = make_f64_source(src, RMS_NORM_F64)
    mkpath(dirname(F64_PATH))
    write(F64_PATH, body)
    return (body = body, k = k, rms_body = rms_body)
end
const F64_PORT = write_f64_port(read(joinpath(HERE, "TrmPort.jl"), String))
const F64_TOKENS = F64_PORT.k
include_string(Main, F64_PORT.body, F64_PATH)   # 書いた写しをそのまま include（読む字とばらつかない）
const PT = TrmPortF64

const P32 = TrmPort
const QS = ("logits", "z_H", "z_L", "q_halt_logits", "q_continue_logits")
const ACT_Q = ("logits", "z_H", "z_L")      # 判定の材料 (c) の列に使う量（q は q_head の重み 0 で別枠）
const PASSED = ("x1", "x2", "x1")            # ACT の手 1〜3（oracle_work.run_act_sequence と同じ）
const CONFIGS = ("a", "c", "d")              # a は条件の良い構成（有効性の確認 (ii) に使う）
const WEIGHTS = ("W0", "W1")

fixture(c, w) = P32.load_fixture(joinpath(HERE, "fixtures", string(c, "_", w, ".json")))
"diag の JSON（行優先の平らな配列＋形）を、形に直した Dict で返す。"
function json_tensor(d)
    sh = Int.(d["shape"])
    v = Float64.(d["data"])
    return isempty(sh) ? fill(v[1]) : Array(permutedims(reshape(v, reverse(sh)...), length(sh):-1:1))
end
maxabs(a, b) = isempty(a) ? 0.0 : maximum(abs.(Float64.(a) .- Float64.(b)))
"fixtures の参照（test_port.jl と同じく Bool へ戻す。Int はそのまま）。"
reference(d) = P32.load_tensor(d)
rowmajor(a) = vec(permutedims(Array(a), ndims(a):-1:1))   # 行優先の平らな配列（Python と同じ順）
"mod（P32 か PT）の ACTModel を fx から組む。"
build_model(mod, fx, state) = mod.ACTModel(fx.config, state)
"state（fixtures の名前 → 配列）の浮動小数を T に写す（整数はそのまま）。"
to_type(T, fx) = Dict(k => (eltype(v) <: AbstractFloat ? Array{T}(v) : copy(v)) for (k, v) in fx.state)
"diag の py_f32/py_f64 の JSON の重みを (名前 → 配列) で返す（整数型のものは fixture のまま）。"
function json_state(o, fx)
    return Dict(k => (eltype(fx.state[k]) <: AbstractFloat ? json_tensor(v) : copy(fx.state[k]))
                for (k, v) in o["state_dict"])
end
"The ACT の手 1〜3（x1, x2, x1）。各手の出力と carry の z を Float64 にして返す。"
function trajectory(mod, fx, state)
    m = build_model(mod, fx, state)
    carry = mod.initial_carry(m, fx.inputs[PASSED[1]])
    out_steps = NamedTuple[]
    for name in PASSED
        carry, out = mod.act_forward(m, carry, fx.inputs[name])
        push!(out_steps, (logits=Float64.(out["logits"]), q_halt_logits=Float64.(out["q_halt_logits"]),
                          q_continue_logits=Float64.(out["q_continue_logits"]),
                          z_H=Float64.(carry.z_H), z_L=Float64.(carry.z_L)))
    end
    return out_steps
end

has_inf(a) = any(isinf, a)   # 0 でない無限大（Inf）があるか
"手 1 の中の周回（H_cycles × L_cycles）の各の z_L と、各ブロックの最後の値を、2 つの走りで比べて、
最初に 1e-8 を越えた所の名前を返す（越えなければ none という字）。"
function step1_first_gap(modA, stA, modB, stB, fx)
    batch = fx.inputs[PASSED[1]]
    r = Dict{String,Any}[]
    for (mod, st) in ((modA, stA), (modB, stB))
        m = build_model(mod, fx, st)
        inner = m.inner
        carry = mod.initial_carry(m, batch)
        zH, zL = mod.reset_carry(inner, fill(true, size(carry.z_H, 1)), carry.z_H, carry.z_L)
        emb = Array{mod.F32,3}(mod.input_embeddings(inner, batch["inputs"], batch["puzzle_identifiers"]))
        push!(r, Dict{String,Any}("emb" => Float64.(emb)))
        for h in 1:Int(mod._getattr(inner.config, :H_cycles)), l in 1:Int(mod._getattr(inner.config, :L_cycles))
            zL = inner.L_level(zL, zH .+ emb; cos_sin=m.cos_sin)       # h_round と同じ順
            push!(r[end], string("h", h, ".l", l, ".z_L") => Float64.(zL))
            if inner.swap_update_order
                zH = inner.L_level(zH, zL; cos_sin=m.cos_sin)
            end
        end
        push!(r[end], "final.z_H" => Float64.(zH))
    end
    for k in keys(r[1])
        k == "emb" && continue
        d = maxabs(r[1][k], r[2][k])
        d > 1e-8 && return string(k, " (", d, ")")
    end
    return "none"
end


"diag/py_f64_<c>_<W>.json を読む（steps の手ごと・量ごと、形は Julia の配列）。なければ nothing。"
function load_py64(c, w)
    path = joinpath(HERE, "diag", string("py_f64_", c, "_", w, ".json"))
    isfile(path) || return nothing
    o = JSON.parsefile(path)["steps"]
    return Dict(k => Dict(q => json_tensor(v) for (q, v) in st) for (k, st) in o)
end
"diag/py_f32_<c>_<W>.json（fixtures と同じ重み・入力の Float32 の写し）を読む。なければ nothing。"
function load_py32(c, w)
    path = joinpath(HERE, "diag", string("py_f32_", c, "_", w, ".json"))
    isfile(path) || return nothing
    return JSON.parsefile(path)
end

"構成 (c, w) を走らせ、表の行を書き、手ごとの列を返す。"
function measure(io, c, w)
    fx = fixture(c, w)
    st32 = to_type(Float32, fx)
    # (i) 有効性: f64 の写しに、f32 の重み（diag/py_f32 の写し）と f32 の入力を渡して手 1 を走らせる。
    o32 = load_py32(c, w)
    gap_i = NaN
    if o32 === nothing
        say(io, "  (i) f64 copy with Float32 weights: diag/py_f32_", c, "_", w, ".json がない（diag_precision.py を先に走らせる）")
    else
        s32 = trajectory(P32, fx, st32)
        s64f32 = trajectory(PT, fx, json_state(o32, fx))
        gap_i = maximum(maxabs(s64f32[1][q], s32[1][q]) for q in QS)
        say(io, "  (i) f64 copy with Float32 weights vs f32 port, step 1 max: ", string(gap_i), " ",
            1e-6 <= gap_i <= 1e-4 ? "(inside 1e-6..1e-4)" : "(outside 1e-6..1e-4)")
    end
    s32 = trajectory(P32, fx, st32)
    s64 = trajectory(PT, fx, to_type(Float64, fx))
    py = load_py64(c, w)
    say(io, "")
    say(io, "== ", c, " ", w, " ==")
    say(io, "step  quantity           f64-julia|f64-python  f32-julia|fixture  f32-julia|f64-julia  f64-julia|Inf")
    jf_all = [Dict(q => NaN for q in QS) for _ in 1:3]      # 手 k の量 q の julia f64|python f64
    cols = Dict(q => Float64[] for q in ACT_Q)              # 手ごとの jf の logits/z_H/z_L の最大
    fv = Dict(q => Float64[] for q in ACT_Q)                # 同上（julia f32|fixture）
    fj = Float64[]                                          # 手ごとの julia f32|julia f64 の最大
    first_gap = String[]
    for k in 1:3
        ref = fx.steps[string("step", k)]
        for q in QS
            a32 = getproperty(s32[k], q)
            b64 = getproperty(s64[k], q)
            r32 = reference(ref[q])
            jf = py === nothing ? NaN : maxabs(rowmajor(b64), rowmajor(py[string("step", k)][q]))
            jf_all[k][q] = jf
            fin = !any(has_inf, b64)
            if q in ACT_Q
                push!(fv[q], fin ? maxabs(a32, r32) : NaN)
                push!(cols[q], jf)
            end
            if py !== nothing && jf > 1e-8
                push!(first_gap, string("step", k, ".", q, " (", jf, ")"))
            end
            say(io, lpad(k, 4), "  ", rpad(q, 18), " ", py === nothing ? rpad("(no diag JSON)", 19) :
                lpad(string(round(jf; sigdigits=4)), 19), "  ",
                lpad(string(round(maxabs(a32, r32); sigdigits=4)), 16), "  ",
                lpad(fin ? string(round(maxabs(b64, a32); sigdigits=4)) : "(" * string(Inf) * ")", 16), "  ",
                lpad(fin ? "no" : "Inf", 9))
        end
        fin_all = all(!any(has_inf, getproperty(s64[k], q)) for q in QS)
        push!(fj, fin_all ? maximum(maxabs(getproperty(s64[k], q), getproperty(s32[k], q)) for q in QS) : NaN)
    end
    if py !== nothing && all(!any(has_inf, getproperty(s64[k], q)) for k in 1:3 for q in QS)
        say(io, "  step1 internals, f64 copy vs f32 port, first where >1e-8: ",
            step1_first_gap(PT, to_type(Float64, fx), P32, st32, fx))
    end
    if py !== nothing
        say(io, "  julia64|python64 > 1e-8 (all quantities): ", isempty(first_gap) ? "none" : join(first_gap, "; "))
    end
    return (gap_i = gap_i, jf = cols, fv = fv, fj = fj, fj_gap = Float64[], jf_all = jf_all,
            first_gap = first_gap, py = py !== nothing)

end

"results-diag-precision.out の中身を書く。戻り値は 0（完走）か 1（無効として止まる）。有効性 (i)(ii) の両方が
成り立つときだけ c・d の表を読む。判定はしない（材料だけを書く）。"
function main(io)
    say(io, "S56 diag precision (measurement only; no tolerance is changed here)")
    say(io, "Julia ", VERSION, "; sequence x1,x2,x1; z after the step; all numbers are max abs diffs")
    say(io, "f64 copy: diag/TrmPort_f64.jl, generated from TrmPort.jl with word-level type tokens only")
    say(io, "  (Float32->Float64, const F32 = Float32 -> Float64, 1f-literal suffixes; never inside strings/comments).")
    say(io, "  rms_norm as in the official model (input cast to float32, computed, cast back to float64); rope tables float32.")
    say(io, "  tokens replaced outside rms_norm: ", F64_TOKENS, "; rms_norm of the copy:")
    for line in source_lines(RMS_SRC)[1]
        say(io, "    ", line)
    end
    say(io, "columns: jf = f64-julia|f64-python (row-major); fv = f32-julia|fixture; fj = f32-julia|f64-julia;")
    say(io, "  Inf = the julia f64 run has Inf (fv is then NaN, i.e. no finite distance to the fixture)")
    R = Dict{Tuple{String,String},Any}()
    for c in ("a", "c", "d"), w in WEIGHTS
        R[(c, w)] = measure(io, c, w)
        if R[(c, w)].py === nothing
            say(io, newline, "diag/py_f64_", c, "_", w, ".json がない: diag_precision.py を先に（QUICK の順で）走らせる。")
            return 1
        end
    end
    # (i) 構成 c・d の f64 の写しに f32 の重み・入力を渡した走り 対 f32 の移植（手 1 の全量の最大）
    say(io, "")
    say(io, "== validity (checked before reading the c/d table) ==")
    ok_i = true
    for c in ("c", "d"), w in WEIGHTS
        g = R[(c, w)].gap_i
        say(io, "  (i) ", c, " ", w, " f64 copy with Float32 weights vs f32 port (step 1): ", g,
            " [", 1e-6 <= g <= 1e-4 ? "ok" : "OUTSIDE 1e-6..1e-4", "]")
        ok_i &= !isnan(g) && 1e-6 <= g <= 1e-4
    end
    worst_ii, wrt_ii = 0.0, "none"
    for w in WEIGHTS, k in 1:3, q in QS
        v = R[("a", w)].jf_all[k][q]
        v > worst_ii && (worst_ii, wrt_ii = v, string(w, " step", k, ".", q))
    end
    ok_ii = worst_ii <= 1e-9
    say(io, "  (ii) a: julia f64|python f64 over all steps and quantities: max ", worst_ii, " at ", wrt_ii,
        ok_ii ? " <= 1e-9" : " > 1e-9")
    if !(ok_i && ok_ii)
        say(io, "  => INVALID: the f64 copy (or the f64 columns) cannot be read; the c/d table below is not read.")
        return 1
    end
    say(io, "  => valid: both (i) and (ii) hold; the c/d table below can be read.")
    say(io, "")
    say(io, "== verdict material (columns only; the judgement is claude-lab's) ==")
    say(io, "per step: max over logits/z_H/z_L; (a) official float32 vs float64, (b) julia f32|fixture,")
    say(io, "  (c) julia f64|python f64; perstep = [step1 value step2 value step3 value]")
    perstep(v) = "[" * join([string(k, ":") * string(round(v[k]; sigdigits=4)) for k in 1:3], " ") * "]"
    for c in ("c", "d"), w in WEIGHTS
        r = R[(c, w)]
        say(io, "(c) ", c, " ", w, " julia f64|python f64 per step: ",
            perstep([maximum(r.jf_all[k][q] for q in ACT_Q) for k in 1:3]))
        say(io, "(b) ", c, " ", w, " julia f32|fixture per step:    ",
            perstep([maximum(r.fv[q][k] for q in ACT_Q) for k in 1:3]))
        say(io, "    ", c, " ", w, " julia f32|f64 per step:        ",
            isempty(r.fj) ? "(-) julia f64 has Inf" : perstep(r.fj),
            "  first step-quantity >1e-8: ", isempty(r.first_gap) ? "none" : join(r.first_gap, "; "))
    end
    say(io, "  (a) is the python f32|f64 per-step column in the Python section below.")
    say(io, "")
    say(io, "== Python measurements (diag_precision.py standard output, same steps and fixtures) ==")
    return print_py_report(io) ? 0 : 1
end
"diag/py_report.txt（diag_precision.py の直前の標準出力）を写す。なければ false。"
function print_py_report(io)
    path = joinpath(HERE, "diag", "py_report.txt")
    isfile(path) || return false
    write(io, read(path, String))
    return true
end
const RMS_SRC = join(RMS_NORM_F64, "\n")
open(joinpath(HERE, "results-diag-precision.out"), "w") do io
    global RESULT_OK = main(io)
end
show(stdout, String(take!(REPORT)))
# main の戻り値が 0 なら 0、そうでなければ 1 で終わる（QUICK の終了コードで見分けられるように）。
exit(RESULT_OK == 0 ? 0 : 1)
