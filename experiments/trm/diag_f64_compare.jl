# S56 診断（最後の測定）: 有効な Float64 の移植の走りと、公式の Float64 の出力（diag/py_f64_*.json）との照合。
# TrmPort（SamsungSAILMontreal/TinyRecursiveModels, commit 7de0d20 の移植。MIT: LICENSE-upstream-MIT.txt）と、
# 発注側が生成済みの diag/TrmPort64.jl・diag/TrmPort64r.jl は読みだけ。fixtures・diag/ の中身・許容差は変えない。
using JSON
using LinearAlgebra: BLAS, norm
BLAS.set_num_threads(1)          # 浮動小数の積和を経路によらず決める（BLAS の分割に依存させない）
const HERE = @__DIR__
const OUT_PATH = joinpath(HERE, "results-diag-f64.out")
const REPORT = IOBuffer()

include(joinpath(HERE, "TrmPort.jl"))                 # module TrmPort（Float32）
include(joinpath(HERE, "diag", "TrmPort64.jl"))       # module TrmPort64（F32 = Float64。rms_norm も Float64）
include(joinpath(HERE, "diag", "TrmPort64r.jl"))      # module TrmPort64r（F32 = Float64。rms_norm だけ公式どおり Float32）

const P32 = TrmPort
const PASSED = ("x1", "x2", "x1")            # ACT の手 1〜3（test_port.jl・oracle_work.run_act_sequence と同じ）
const CONFIGS = ("a", "c", "d")
const WEIGHTS = ("W0", "W1")
const CMP_CONFIGS = ("c", "d")
const QUANTITIES = ("logits", "z_H", "z_L", "q_halt_logits", "q_continue_logits")
const TOL_VALID2 = 1e-9

# say: REPORT に書き、標準出力にも同じ行を出す。
say(io, xs...) = (println(io, xs...); println(stdout, xs...))
fixture(c, w) = P32.load_fixture(joinpath(HERE, "fixtures", string(c, "_", w, ".json")))
py_path(c, w) = joinpath(HERE, "diag", string("py_f64_", c, "_", w, ".json"))

"diag の JSON（行優先の平らな配列＋形）→ Julia の形の Float64 の配列（diag_precision.jl と同じ直し方）。"
function json_tensor(d)
    sh = Int.(d["shape"])
    v = Float64.(d["data"])
    return isempty(sh) ? fill(v[1]) : Array(permutedims(reshape(v, reverse(sh)...), length(sh):-1:1))
end

"py_f64_steps(c, w): diag/py_f64_<c>_<W>.json の steps を手ごと・量ごとの Float64 の配列にする。"
function py_f64_steps(c, w)
    o = JSON.parsefile(py_path(c, w))
    o["dtype"] == "float64" || error(string("dtype ", o["dtype"]))
    return Dict(k => Dict(q => json_tensor(st[q]) for q in QUANTITIES) for (k, st) in o["steps"])
end

"重みだけ T に広げる（整数はそのまま）。fixture の配列は書き換えない。"
to_type(T, d) = Dict(k => (eltype(v) <: AbstractFloat ? T.(v) : copy(v)) for (k, v) in d)

"trajectory(mod, m, fx): test_port.jl と同じ入口（initial_carry は x1 の入力、act_forward の入力は step k の passed_input）。
手ごとの量 (logits, z_H, z_L, q_halt_logits, q_continue_logits) の組を返す。引き数を書き換えないので ! は付けない。"
function trajectory(mod, m, fx)
    carry = mod.initial_carry(m, fx.inputs[fx.steps["step1"]["passed_input"]])
    steps = NamedTuple[]
    for k in 1:length(PASSED)
        carry, out = mod.act_forward(m, carry, fx.inputs[fx.steps[string("step", k)]["passed_input"]])
        push!(steps, (logits = out["logits"], z_H = carry.z_H, z_L = carry.z_L,
                      q_halt_logits = out["q_halt_logits"], q_continue_logits = out["q_continue_logits"]))
    end
    return steps
end

"run_variant(V, fx) → (走り, 表の注記)。V0 = TrmPort64、V1 = TrmPort64r、V2 = TrmPort64r で rope の表だけ
(Float32 の TrmPort が同じ構成で作った表 → Float64) に差し替える。a は learned の位置の表を使うので、
表を作っている表（embed_pos、ACTModel の初期化で入る）を差し替える。V は局所の文字列として比べる。"
function run_variant(V::AbstractString, fx)
    state64 = to_type(Float64, fx.state)
    if V == "V0"
        return trajectory(TrmPort64, TrmPort64.ACTModel(fx.config, state64), fx), "V0: TrmPort64 as generated"
    elseif V == "V1"
        return trajectory(TrmPort64r, TrmPort64r.ACTModel(fx.config, state64), fx), "V1: TrmPort64r as generated"
    elseif V == "V2"
        m = TrmPort64r.ACTModel(fx.config, state64)
        tab32 = to_type(Float32, fx.state)
        m32 = P32.ACTModel(fx.config, tab32)            # Float32 の表を作っている ACTModel
        if m.cos_sin !== nothing
            c32, s32 = m32.inner.rotary_emb            # ACTModel の組み立てで入る rope の表（Float32）
            got = (Float64.(c32), Float64.(s32))
            m.inner.rotary_emb = nothing               # 表は下で模型の欄に入れる（先に外してから入れる）
            m.inner.rotary_emb = got
            m.cos_sin = got
            note = string("V2: rope table = widened Float32 TrmPort table (", size(got[1]), ")")
        elseif m.inner.embed_pos !== nothing && m32.inner.embed_pos !== nothing
            # learned の位置の表（Float32）→ Float64（h_round は inner（64r）の欄を読む）。
            tab64 = TrmPort64r.CastedEmbedding(Float64.(m32.inner.embed_pos.embedding_weight))
            m.inner.embed_pos = tab64
            note = string("V2: learned pos table = widened Float32 TrmPort table (", size(tab64.embedding_weight), ")")
        else
            error("V2: neither rope nor learned pos table present")
        end
        return trajectory(TrmPort64r, m, fx), note
    end
    error(string("unknown variant ", V))
end

pval(nt, q) = getproperty(nt, Symbol(q))
maxabs(a, b) = (size(a) == size(b) || error(string("shape ", size(a), " != ", size(b)));
                isempty(a) || (all(isfinite, a) && all(isfinite, b)) || error(string("non-finite in comparison ", size(a)));
                isempty(a) ? 0.0 : maximum(abs.(Float64.(a) .- Float64.(b))))
"f32 と変種の f64 の手ごとの最大（logits, z_H, z_L）。"
function step_gaps(runs32, runs64)
    return [maximum(maxabs(pval(runs64[k], q), pval(runs32[k], q)) for q in ("logits", "z_H", "z_L"))
            for k in 1:length(PASSED)]
end

"valid2(vals): vals = [(W, a の走り, a の py_f64), …]。手 1〜3・全量で |julia f64 - python f64| の最大と、その手の名。"
function valid2(vals)
    check = Float64[]
    where_ = String[]
    for (w, runs64, py) in vals
        for k in 1:length(PASSED), q in QUANTITIES
            push!(check, maxabs(pval(runs64[k], q), py[string("step", k)][q]))
            push!(where_, string("a ", w, " step", k, " ", q))
        end
    end
    i = argmax(check)
    return (check[i], where_[i])
end

"cmp_lines(io, tag, runs, py, c, w): 手ごとに 5 つの量の最大差を 1 行で書く。"
function cmp_lines(io, tag, runs, py, c, w)
    for k in 1:length(PASSED)
        p = py[string("step", k)]
        say(io, tag, c, " ", w, " step ", k,
            " logits ", maxabs(pval(runs[k], "logits"), p["logits"]),
            " z_H ", maxabs(pval(runs[k], "z_H"), p["z_H"]),
            " z_L ", maxabs(pval(runs[k], "z_L"), p["z_L"]),
            " q_halt ", maxabs(pval(runs[k], "q_halt_logits"), p["q_halt_logits"]),
            " q_continue ", maxabs(pval(runs[k], "q_continue_logits"), p["q_continue_logits"]))
    end
end

"measure_variant(V): 1 変種の Float64 の走りを作り、VALID1・VALID2・CMP/REF を書く。例外は ERROR 行にして返す。"
function measure_variant(V)
    r64 = Dict{Tuple{String,String},Any}()
    notes = Dict{Tuple{String,String},String}()
    r32 = Dict{Tuple{String,String},Any}()
    try
        for c in CONFIGS, w in WEIGHTS
            fx = fixture(c, w)
            r32[(c, w)] = trajectory(P32, P32.ACTModel(fx.config, to_type(Float32, fx.state)), fx)
            got = run_variant(V, fx)
            r64[(c, w)] = got[1]
            notes[(c, w)] = got[2]
        end
        elt = eltype(pval(r64[("c", "W0")][1], "logits"))
        gaps = Dict((c, w) => step_gaps(r32[(c, w)], r64[(c, w)]) for c in CONFIGS for w in WEIGHTS)
        ok1 = all(c -> all(g -> 0.0 < g < 1e-2, gaps[c]), ((c, w) for c in CONFIGS for w in WEIGHTS)) && elt == Float64
        for c in CMP_CONFIGS, w in WEIGHTS
            say(REPORT, "VALID1 ", V, " ", c, " ", w, " step maxima ", gaps[(c, w)], " eltype ", elt, " ",
                (ok1 && all(g -> 0.0 < g < 1e-2, gaps[(c, w)]) && elt == Float64) ? "OK" : "NG")
        end
        say(REPORT, "VALID1 ", V, " a W0/W1 step maxima ", gaps[("a", "W0")], " ", gaps[("a", "W1")], " eltype ", elt,
            " ", ok1 ? "OK" : "NG")
        avals = [(w, r64[("a", w)], py_f64_steps("a", w)) for w in WEIGHTS]
        (x0, where0) = valid2(avals)
        ok2 = valid2([avals[1]])[1] <= TOL_VALID2 && valid2([avals[2]])[1] <= TOL_VALID2
        say(REPORT, "VALID2 ", V, " a: max over all steps and quantities of |julia f64 - python f64| = ",
            valid2([avals[1]])[1], " (a W0), ", valid2([avals[2]])[1], " (a W1) ", ok2 ? "PASS" : "FAIL",
            " (<= ", TOL_VALID2, "; pooled worst ", where0, ")")
        say(REPORT, "NOTE ", V, " tables: a ", notes[("a", "W0")], "; c ", notes[("c", "W0")], "; d ", notes[("d", "W0")])
        if ok1 && ok2
            say(REPORT, "CMP ", V, " vs python f64 (c, d; steps 1-3)")
            for c in CMP_CONFIGS, w in WEIGHTS
                cmp_lines(REPORT, string("CMP ", V, " "), r64[(c, w)], py_f64_steps(c, w), c, w)
            end
        else
            say(REPORT, "CMP skipped: invalid (", V, "; VALID1 ", ok1 ? "OK" : "NG", ", VALID2 ", ok2 ? "PASS" : "FAIL", ")")
        end
        for c in CMP_CONFIGS, w in WEIGHTS
            cmp_lines(REPORT, "REF ", r32[(c, w)], py_f64_steps(c, w), c, w)
        end
        return true
    catch e
        # 握り潰さない: この変種を ERROR として書き、次の変種へ進む（スクリプトは最後まで走る）。
        say(REPORT, "ERROR: ", V, ": ", sprint(showerror, e))
        return false
    end
end

function main()
    say(REPORT, "S56 diag f64 compare, variants V0=TrmPort64, V1=TrmPort64r, V2=TrmPort64r with widened Float32 tables")
    say(REPORT, "VALID1: 0 < maxabs(f32-port vs f64-port) < 1e-2, every step, Float64 output; VALID2: <= ", TOL_VALID2)
    for V in ("V0", "V1", "V2")
        measure_variant(V)
    end
    println(REPORT, "DIAG DONE")
    println(stdout, "DIAG DONE")
    write(OUT_PATH, String(take!(REPORT)))
end
main()
