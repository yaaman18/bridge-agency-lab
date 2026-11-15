# S56 手 3 の配線の自己点検（関門。凍結の対象にせず、実装の合否の証拠にもしない）。
# test_port.jl の配線だけを確かめる: ここで TrmPort という名前の模擬モジュール（後に module MockPort）を置き、test_port.jl を include する。
# 模擬は fixtures の正解の値を返す（test_port.jl の照合の配線を見るためだけ。TrmPort.jl 本体には入れない）。
#   (a) 正しい値を返す模擬: 通常系の全部（ACT 列 20・mixed_reset・h_round_end 15）が通り、負の対照は (i) だけ caught（他の 7 つは NOT CAUGHT で、誤って caught にしない）。最後の行は FAILED（8 つ揃わないため）。
#   (b) 値を少し壊した模擬（出力 3 キーの一つ、carry の z_H、current_data、halted、steps）では通常系が拒まれる。
# 出力の口: include する module に OUTPUT_PATH = results-port-mock.out を置く（results-port.out は書かない）。
# 走らせ方（ラボの根から）: julia --project=. experiments/trm/selftest_port_mock.jl（最後の行が SELFTEST PASS なら合格）
using JSON
const MOCK_HERE = @__DIR__
const MOCK_OUT = joinpath(MOCK_HERE, "results-port-mock.out")
# 模擬の本体。名前は Main に置くとしても main の名前を主に使う（include は Main.TrmPort を見る）。
# このファイルの場所は、根の側でここに定める（mock の中・後の include からも見える）。
module MockPort
# load_fixture は JSON を読む（TrmPort.jl と同じパッケージ）。
using Base: @__DIR__
using JSON
const F32 = Float32
struct MockInner
    config::Any
    state::Dict{String,Any}
    embed_tokens::Any
    lm_head::Any
    q_head::Any
    H_init::Any
    L_init::Any
    puzzle_emb::Any
    embed_pos::Any
end
mutable struct MockCarry
    inner_carry::Any
    steps::Vector{Int}
    halted::Vector{Bool}
    current_data::Dict{String,Any}
    # cd は契約の整数の生配列（Dict ではない）。そのまま写して、Dict を要求しない。
    MockCarry(ic, s, h, cd) = new(ic, Int.(collect(s)), Bool.(collect(h)),
                                  Dict{String,Any}(k => copy(v) for (k, v) in cd))
end
mutable struct MockModel
    config::Any
    state::Dict{String,Any}
    inner::MockInner
    kw::Dict{Symbol,Any}
end
# 場面の設定（selftest が置く）: :corrupt 壊し方（:none は正しい値）。:injected は重みの注入の検出（対照 (i)）。
const OPT = Dict{Symbol,Any}(:corrupt => :none, :injected => false, :hrounds => Dict{Any,Any}(),
                             :steps => Dict{Any,Any}(), :orig_w11 => Dict{Any,Any}(), :weights_w11 => nothing)
const CONTROL_ARGS = (:swap_update_order, :q_head_pos, :bad_rope_value, :bad_norm_order, :H_cycles, :L_cycles)
"mock_tensor: fixture のテンソルを読む（TrmPort.jl の load_tensor と同じ規則）: int は Int、bool は Bool、他は Float32。"
function mock_tensor(d::AbstractDict)
    sh = Int[Int(x) for x in d["shape"]]
    v = F32.(collect(d["data"]))
    y = isempty(sh) ? fill(F32(v[1])) : Array(permutedims(reshape(v, reverse(sh)...), length(sh):-1:1))
    dt = String(get(d, "dtype", "float32"))
    startswith(dt, "int") && return Int.(y)
    dt == "bool" && return Bool.(y)
    return y
end
"one(v): fixture の 1 手ぶん → 量の Dict（current_data は 2 つの整数の配列。正解の値そのまま）。"
function one(v)
    r = Dict{String,Any}(k => copy(mock_tensor(v[k])) for k in keys(v) if v[k] isa AbstractDict && haskey(v[k], "data"))
    r["current_data"] = (copy(mock_tensor(v["current_data"]["inputs"])),
                         copy(mock_tensor(v["current_data"]["puzzle_identifiers"])))
    return r
end
"load_fixture_builtin(path): TrmPort.load_fixture の返す形（steps・mixed_reset は JSON の Dict のまま）。入力の表は読み込みの後に 1 か所で作る。"
function load_fixture_builtin(path::AbstractString)
    o = JSON.parsefile(path)
    ks = sort!(collect(keys(o["config"])))
    inter = Dict{String,Any}("h_round_end" => o["intermediates"]["h_round_end"])
    return (config = (names = Symbol.(ks), values = Any[o["config"][k] for k in ks]),
            state = Dict{String,Any}(k => mock_tensor(v) for (k, v) in o["state_dict"]),
            rope = Dict{String,Any}(), inputs = inputs_of(o),
            steps = o["steps"], mixed_reset = o["mixed_reset"], intermediates = inter, env = o["env"])
end
"inputs_of(o): 入力の表（x1..x3 → inputs と puzzle_identifiers の整数の配列）。"
function inputs_of(o)
    d = Dict{String,Any}()
    for (k, v) in o["inputs"]
        d[k] = Dict{String,Any}("inputs" => mock_tensor(v["inputs"]),
                                "puzzle_identifiers" => mock_tensor(v["puzzle_identifiers"]))
    end
    return d
end
"load_fixture(path): TrmPort.load_fixture が返す形（test_port が名前で引ける）。"
load_fixture(path::AbstractString) = load_fixture_builtin(path)
"Inner(cfg): 重みの入っていない Inner。重みは weights(inner, state) で入れる。"
Inner(cfg) = MockInner(cfg, Dict{String,Any}(), nothing, nothing, nothing,
                       fill(F32(0), 1, 1, 1), fill(F32(0), 1, 1, 1), nothing, nothing)
"weights(inner, state): 重みを入れた新しい Inner。層 0 の down_proj の [1,1] も OPT[:weights_w11] に記録する（対照 (i) の検出用）。"
function weights(inner::MockInner, state::AbstractDict)
    s = Dict{String,Any}(k => copy(v) for (k, v) in state)
    OPT[:weights_w11] = s["inner.L_level.layers.0.mlp.down_proj.weight"][1, 1]
    return MockInner(inner.config, s, s["inner.embed_tokens.embedding_weight"], s["inner.lm_head.weight"],
                     (s["inner.q_head.weight"], s["inner.q_head.bias"]),
                     reshape(copy(s["inner.H_init"]), 1, 1, :), reshape(copy(s["inner.L_init"]), 1, 1, :),
                     get(s, "inner.puzzle_emb.weights", nothing), nothing)
end
"ACTModel(cfg, state; kw...): inner は重みを入れた Inner。kw は対照用（未知の名前は例外）。"
function ACTModel(cfg, state::AbstractDict; kw...)
    for k in keys(kw)
        k in CONTROL_ARGS || error(string("unknown ACTModel argument: ", k))
    end
    kwd = Dict{Symbol,Any}(kw)
    if haskey(kwd, :H_cycles) || haskey(kwd, :L_cycles)
        # 欄の並びを変えない（台帳の鍵は構成の値の並びそのもの。入れ替えると H_cycles の台帳を引けない）
        cfg = (names = copy(cfg.names), values = Any[k == :H_cycles ? get(kwd, :H_cycles, cfg.values[i]) :
                                                        k == :L_cycles ? get(kwd, :L_cycles, cfg.values[i]) : cfg.values[i]
                                                       for (i, k) in enumerate(cfg.names)])
    end
    inner = weights(Inner(cfg), state)
    return MockModel(cfg, Dict{String,Any}(k => v for (k, v) in state), inner, kwd)
end
"load_tensor(d): 契約の名 (TrmPort.load_tensor)。fixture の JSON の tensor（Dict）→ 配列（コードのほかの所と同じ値）。"
load_tensor(d::AbstractDict) = mock_tensor(d)
"nH(m): 構成の H_cycles（mock の h_round_end の周回の数）。"
nH(m::MockModel) = Int(m.config.values[findfirst(==(:H_cycles), m.config.names)])
initial_carry(m::MockModel, batch::Dict) = MockCarry((z_H = copy(m.inner.H_init), z_L = copy(m.inner.L_init)),
                                                     zeros(Int, size(batch["inputs"], 1)), fill(false, size(batch["inputs"], 1)),
                                                     Dict{String,Any}("inputs" => copy(batch["inputs"]),
                                                                      "puzzle_identifiers" => copy(batch["puzzle_identifiers"])))
"step_of(carry): carry.steps + 1（fixtures の何手めを返すか）。"
step_of(carry) = step_of_vals(carry.steps)
step_of_vals(steps) = maximum(Int.(steps)) + 1

"act_forward(m, carry, batch): 次の手（carry.steps+1）の正解（fixture の steps）を求め、壊し方（OPT[:corrupt]）に従って
返す状態の欄だけを壊す（値は正解のまま）。対照 (i) の重みの注入は、入れ直す重みの [1,1] が元の値と違うかで見る。"
function act_forward(m::MockModel, carry::MockCarry, batch::Dict)
    steps = step_of(carry)
    c = OPT[:corrupt]
    c in (:none, :z_H, :halted, :steps, :q_halt, :q_continue, :current_data, :outer, :logits) ||
        error(string("unknown disturbance: ", c))
    # 台帳には JSON のままの 1 手（passed_input の文字列も入る）が置いてあるので、量のキーだけを取り出して読む。
    raw = OPT[:steps][(m.config.values, m.kw)][string("step", steps)]
    s = Dict{String,Any}()
    for k in ("logits", "q_halt_logits", "q_continue_logits", "z_H", "z_L", "steps", "halted")
        s[k] = copy(mock_tensor(raw[k]))
    end
    s["current_data"] = (copy(mock_tensor(raw["current_data"]["inputs"])),
                         copy(mock_tensor(raw["current_data"]["puzzle_identifiers"])))
    fold = F32(0)
    if OPT[:injected]
        orig = OPT[:orig_w11][m.config.values]
        fold = abs(Float64(OPT[:weights_w11]) - Float64(orig)) > 1e-4 ? F32(1e-2) : F32(0)
    end
    out = Dict{String,Any}("logits" => s["logits"] .+ fold, "q_halt_logits" => s["q_halt_logits"],
                           "q_continue_logits" => s["q_continue_logits"])
    z_H, z_L = copy(s["z_H"]), copy(s["z_L"])
    newsteps, halted = s["steps"], s["halted"]
    cd = Dict{String,Any}("inputs" => copy(s["current_data"][1]), "puzzle_identifiers" => copy(s["current_data"][2]))
    c == :q_halt && (out["q_halt_logits"] = out["q_halt_logits"] .+ F32(1e-3))
    c == :q_continue && (out["q_continue_logits"] = out["q_continue_logits"] .+ F32(1e-3))
    c == :z_H && (z_H = z_H .+ F32(1e-3))
    c == :halted && (halted = fill(false, length(halted)))
    c == :steps && (newsteps = newsteps .* 10)
    c == :current_data && (cd["puzzle_identifiers"] = cd["puzzle_identifiers"] .+ 1)
    c == :outer && (cd = Dict{String,Any}("inputs" => cd["inputs"], "puzzle_identifiers" => cd["puzzle_identifiers"], "extra" => Int[1]))
    c == :logits && (out["logits"] = out["logits"] .+ F32(1e-3))
    return MockCarry((z_H = z_H, z_L = z_L), newsteps, halted, cd), out
end
"h_round_ends(inner, x; reset): inner.config の構成の h_round_end（周回 1 から）。reset の値で変えない。"
function h_round_ends(inner::MockInner, x::Dict; reset::Bool = true)
    hs = OPT[:hrounds][inner.config.values]
    return [(copy(mock_tensor(r["z_H"])), copy(mock_tensor(r["z_L"]))) for r in hs]
end
"Carry(ic, s, h, cd): 契約の Carry の名前（模擬は MockCarry を返す）。"
const Carry = MockCarry
end # module MockPort

# ---- 自己点検の本体 ----
const CONFS = ["a", "b", "c", "d", "e"]
# このファイルの場所。@__DIR__・@__FILE__ は include の仕方（julia -e の include_string）によって根を返すので、
# この 2 つの相対パスが ../fixtures・test_port.jl に届く所まで上るところをこのディレクトリ（experiments/trm）とする。
function find_selftest_dir()
    cands = String[dirname(abspath(@__FILE__)), abspath(@__DIR__), pwd()]
    for c in cands
        d = c
        for _ in 1:6
            isfile(joinpath(d, "test_port.jl")) && isdir(joinpath(d, "fixtures")) && return d
            d = dirname(d)
        end
    end
    error("selftest_port_mock: cannot locate experiments/trm (test_port.jl and fixtures/)")
end
"toplevel_port(nm, path) → TrmPort.jl を、根の側と同じ前置き（using Base・using JSON）で作った module nm に 1 回だけ読み、その TrmPort を返す。
nm はこの自己点検の module の中に置く（この module は根でない所〈MockPortRunner など〉に include されているので Main を使わない）。"
function toplevel_port(nm::Symbol, path)
    if !isdefined(@__MODULE__, nm)
        m = Module(nm)
        Core.eval(m, :(using Base))
        Core.eval(m, :(using JSON))
        Base.include(m, path)
        Core.eval(@__MODULE__, :($nm = $m))
    end
    return getfield(@__MODULE__, nm).TrmPort
end
parsefile_json(path) = toplevel_port(:TrmPortJs, joinpath(SELFTEST_DIR, "TrmPort.jl")).JSON.parsefile(path)
const SELFTEST_DIR = find_selftest_dir()
path_of(c, w) = joinpath(SELFTEST_DIR, "fixtures", string(c, "_", w, ".json"))
const TrmRef = toplevel_port(:TrmRefPort, joinpath(SELFTEST_DIR, "TrmPort.jl"))   # 本物の実装（構成の並びのため）
const TrmJs = toplevel_port(:TrmPortJs, joinpath(SELFTEST_DIR, "TrmPort.jl"))     # JSON（構成の値を引くため）
"setup(c): 構成 c の steps と down_proj の元の値を OPT に置き、fixture を返す（FIX より先に走る）。
構成の並びは TrmPort.load_fixture の並びに揃える（台帳の鍵は ACTModel が受け取る cfg の値の並びそのもの）。"
function setup(c)
    path = path_of(c, "W1")
    f = MockPort.load_fixture(path)
    ks = TrmRef.load_fixture(path).config.names          # 並びと名前は本物の load_fixture に揃える
    f = merge(f, (config = (names = copy(ks), values = Any[f.config.values[findfirst(==(k), f.config.names)] for k in ks]),))
    vals = f.config.values
    MockPort.OPT[:hrounds][vals] = f.intermediates["h_round_end"]
    MockPort.OPT[:orig_w11][vals] = f.state["inner.L_level.layers.0.mlp.down_proj.weight"][1, 1]
    for kw in (Dict{Symbol,Any}(), Dict{Symbol,Any}(:swap_update_order => true), Dict{Symbol,Any}(:q_head_pos => 2),
               Dict{Symbol,Any}(:bad_rope_value => true), Dict{Symbol,Any}(:bad_norm_order => true))
        MockPort.OPT[:steps][(vals, kw)] = f.steps
    end
    # 対照 (ii): H_cycles を 1 減らした構成（構成の値だけが違う。kw は空）
    keysH = Any[k == :H_cycles ? 2 : v for (k, v) in zip(f.config.names, vals)]
    MockPort.OPT[:steps][(keysH, Dict{Symbol,Any}())] = f.steps
    MockPort.OPT[:hrounds][keysH] = f.intermediates["h_round_end"]
    MockPort.OPT[:orig_w11][keysH] = f.state["inner.L_level.layers.0.mlp.down_proj.weight"][1, 1]
    return f
end
const FIX = Dict(c => setup(c) for c in CONFS)
const checks = String[]
slog(s) = println(s)
check(name, ok, detail) = (push!(checks, string(ok ? "ok   " : "FAIL ", name, " (", detail, ")")); ok)
"""run_driver(corrupt; injected=false): 場面を置き、OUTPUT_PATH を替え、test_port.jl を新しい module MockPortRunner へ include して
run() の値を取る。含む側の TrmPort は Main に置く（test_port.jl は Main.TrmPort を見る）。戻り値 (値, 例外)。
Main の TestPort に古い定義が残っていても使わない（include のたびに新しい module を作る）。"""
function run_driver(corrupt; injected = false)
    MockPort.OPT[:corrupt] = corrupt
    MockPort.OPT[:injected] = injected
    r = (val = false, err = nothing)
    try
        # 名前は include 文字列の中に書く（module の外で作った Module は、後に const で名前を束ねても、
        # include の後で isdefined が偽になる）。見る先の module の名前 TrmPort と出力の口 OUTPUT_PATH を置く。
        src = string("module MockPortRunner\n", "using Base, Printf, JSON\n",
                     "const TrmPort = ", repr(MockPort), "\n", "const OUTPUT_PATH = ", repr(MOCK_OUT), "\nend\n")
        m = Core.eval(Main, Meta.parseall(src))
        Base.include(m, joinpath(SELFTEST_DIR, "test_port.jl"))
        tp = getfield(m, :TestPort)
        r = (val = Base.invokelatest(getfield(tp, :run)), err = nothing)
    catch e
        r = (val = false, err = sprint(showerror, e))
    end
    return r
end
"tokens(ls) → 最後の行、同意した行（2 空格の後に手の見出しが続く行）の FAIL の数、負の対照の行数・FAILED・caught・NOT CAUGHT、h_round_end の周回の行数と FAILED の数。"
function tokens(ls)
    # 通常系の行: 見出し（2 空格以上の後に手の見出し）と、その下の字下げの 4 空格以上の行（FAIL / FAILED を含むもの）。
    usual = count(x -> occursin(r"^    +\S", x) && (occursin("FAIL", x) || occursin("FAILED", x)), ls)
    round_failed = count(x -> startswith(x, "  round ") && occursin("FAILED", x), ls)
    return (last = isempty(ls) ? "" : ls[end], usual = usual,
            ctl = count(x -> occursin("negative control (", x), ls),
            ctl_failed = count(x -> occursin("negative control (", x) && occursin(" FAILED: ", x), ls),
            caught = count(x -> occursin(r"\) caught: ", x), ls),
            notcaught = count(x -> occursin(") NOT CAUGHT: ", x), ls),
            rounds = count(x -> startswith(x, "  round "), ls),
            round_failed = round_failed, fails = count(x -> startswith(x, "  FAIL"), ls))
end
# (a) 正しい値を返す模擬: 通常系の全部が通る（ACT 列 20 の見出しと 80 手、mixed_reset 10、h_round_end 15）。対照は (i) だけ caught。
r = run_driver(:none)
ls = readlines(MOCK_OUT)
t = tokens(ls)
slog(string("(a) include value ", r.val, ", exception ", r.err === nothing ? "none" : r.err))
check("(a) the include returned true", r.val === true && r.err === nothing, string(r.val, " ", r.err))
check("(a) no usual FAIL line", t.usual == 0 && t.fails == 0, string(t.usual, " lines with FAIL, ", t.fails, " FAIL lines"))
check("(a) 20 ACT columns (80 step records)", count(x -> occursin("ACT column: steps", x), ls) == 20 &&
      count(x -> occursin(r"^  step[1-4]:$", x), ls) == 80, string(length(ls), " lines"))
check("(a) 15 h_round_end rounds", t.rounds == 15 && t.round_failed == 0, string(t.rounds, " rounds, ", t.round_failed, " FAILED"))
check("(a) 8 negative controls, only (i) caught", t.ctl == 8 && t.ctl_failed == 0 && t.caught == 1 && t.notcaught == 7,
      string("controls ", t.ctl, " FAILED ", t.ctl_failed, " caught ", t.caught, " not caught ", t.notcaught))
check("(a) the last line is FAILED (7 of 8 controls are not caught by the mock)", t.last == "FAILED", t.last)
# (b) 少し壊した模擬: 通常系が拒まれる（(a) と同じ対照の数で、最後の行は FAILED）。
const NEG = [:logits, :q_halt, :q_continue, :z_H, :current_data, :halted, :steps, :outer]
for corrupt in NEG
    rr = run_driver(corrupt)
    lls = readlines(MOCK_OUT)
    tt = tokens(lls)
    okb = rr.err === nothing && (tt.fails > 0) && tt.usual == 0 && tt.round_failed == 0 && tt.ctl_failed == 0 && tt.last == "FAILED"
    check(string("(b) ", corrupt, " is rejected"), okb,
          string("usual FAIL ", tt.usual, " FAIL lines ", tt.fails, " h_round_end FAILED ", tt.round_failed,
                 " control FAILED ", tt.ctl_failed, " last ", tt.last, rr.err === nothing ? "" : string(" err ", rr.err)))
end
slog("selftest_port_mock: the wiring of test_port.jl only (mock TrmPort; not evidence of the implementation)")
for l in checks
    slog(l)
end
nfail = count(l -> startswith(l, "FAIL"), checks)
slog(string("checks: ", length(checks), ", failed: ", nfail))
slog(nfail == 0 ? "SELFTEST PASS" : "SELFTEST FAILED")
exit(nfail == 0 ? 0 : 1)
