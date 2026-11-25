# S64 C0 predictor: the seq_len = 47 TRM, open loop (discussion/specs/S64-c0-trm-openloop.md r3; predictions.toml, frozen in
# ../freeze-c0-trm.txt). Reads S57's synthetic worlds stat and rev (S57's 6 frozen files loaded unchanged, as
# ../headroom_audit/audit.jl:35-48) through ON_STEP (read only): from T0 = 800 every step's receptors r1..r8
# (circuit.active[1..8] at the end of the step), acts and Y = y[a] > 0. Tracks obs-full (main), obs-ay and exo (diagnostics).
# Models TRM (config a, H 3, L 6, 3 ACT steps) and TRM-1x1 (H 1, L 1, 1 step), 4 settings each, trained in pure Julia
# (TrmC0.jl, Float32 BLAS GEMM, batch 64); controls RATE, B1, TAB4, TAB_R1; ê against p_cal (PAV), ê_cal, b_min; OOD.
# Gates G0..G8 and G-TIME before the training (G1 also after it; G6 and G8 by the mode g6 after the two processes).
# No change to S57's code, core/, rust/, experiments/trm/ or ~/bridge-protocol.
# Usage (from the lab root):
#   julia --project=. -t 8 experiments/c0_trm/c0_trm.jl out          (the run; then the same with out-rerun)
#   julia --project=. experiments/c0_trm/c0_trm.jl g6                 (G6: out vs out-rerun; G8: core/check, bridge-protocol)
#   julia --project=. -t 1 experiments/c0_trm/c0_trm.jl t1            (two trainings again with one thread, against out/'s weights)
using SHA, JSON, Printf, TOML, LinearAlgebra

const HERE = @__DIR__
const EXP = normpath(joinpath(HERE, ".."))
const LAB = normpath(joinpath(EXP, ".."))
const OUTNAME = length(ARGS) >= 1 ? ARGS[1] : "out"
sha(f) = bytes2hex(open(sha256, f))
shab(b) = bytes2hex(sha256(b))
function read_sums(f)
    ref = Dict{String,String}()
    for l in eachline(f)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    return ref
end

# ---------------- mode g6: G6 (out vs out-rerun) and G8 (core/check, bridge-protocol unchanged) ----------------
function g6main()
    lines = String[]
    sayg(x...) = (s = string(x...); println(s); push!(lines, s))
    A = joinpath(HERE, "out"); B = joinpath(HERE, "out-rerun")
    files = ["results.tsv", "summary.json"]
    wa = sort(readdir(joinpath(A, "weights"))); wb = sort(readdir(joinpath(B, "weights")))
    ok6 = wa == wb && !isempty(wa)
    for f in files
        ha = sha(joinpath(A, f)); hb = sha(joinpath(B, f)); ok6 &= ha == hb
        sayg("G6 ", f, " out ", ha, " out-rerun ", hb, " ", ha == hb ? "identical" : "DIFFERENT")
    end
    for f in wa
        ha = sha(joinpath(A, "weights", f)); hb = f in wb ? sha(joinpath(B, "weights", f)) : ""; ok6 &= ha == hb
        sayg("G6 weights/", f, " ", ha, " ", ha == hb ? "identical" : "DIFFERENT")
    end
    sa = JSON.parsefile(joinpath(A, "summary.json")); sb = JSON.parsefile(joinpath(B, "summary.json"))
    ok6 &= sa["selected"] == sb["selected"]
    sayg("G6 selected settings identical: ", sa["selected"] == sb["selected"])
    sayg("G6 (two processes: selected settings, trained weights, results.tsv, summary.json identical): ", ok6)
    rc = success(pipeline(Cmd(`sh core/check/run.sh`; dir = LAB); stdout = joinpath(A, "core-check.out"), stderr = joinpath(A, "core-check.err")))
    sayg("G8 sh core/check/run.sh exit 0: ", rc)
    bp = joinpath(homedir(), "bridge-protocol")
    st = read(Cmd(`git status --short`; dir = bp), String); hd = strip(read(Cmd(`git rev-parse HEAD`; dir = bp), String))
    df = read(Cmd(`git diff`; dir = bp), String); dc = read(Cmd(`git diff --cached`; dir = bp), String)
    before = read(joinpath(A, "bp-before.txt"), String); bl = [l for l in split(before, "\n") if !isempty(l)]
    samest = bl[1:end-1] == [l for l in split(st, "\n") if !isempty(l)][1:min(end, length(bl) - 1)]
    okbp = bl[end] == hd && isempty(df) && isempty(dc)
    sayg("G8 ~/bridge-protocol: HEAD ", hd, " (before the run ", bl[end], "), git diff empty ", isempty(df), ", git diff --cached empty ", isempty(dc),
         "; the first lines of git status --short as before the run (untracked files of other processes may change; not part of the criterion): ", samest)
    sayg("G8 (core/check exit 0 and bridge-protocol unchanged): ", rc && okbp)
    write(joinpath(A, "g6g8.out"), join(lines, "\n") * "\n")
    return ok6 && rc && okbp ? 0 : 1
end
OUTNAME == "g6" && exit(g6main())

const OUT = joinpath(HERE, OUTNAME == "t1" ? "out" : OUTNAME)
OUTNAME == "t1" || (mkpath(OUT); mkpath(joinpath(OUT, "weights")); mkpath(joinpath(OUT, "g1")))
const LOG = String[]
say(x...) = (s = string(x...); println(s); push!(LOG, s); flush(stdout))
write_log() = OUTNAME == "t1" ? nothing : write(joinpath(OUT, "results.out"), join(LOG, "\n") * "\n")
gate(name, ok) = (ok || (say("STOP: ", name, " failed; nothing after it is run"); write_log(); error("$name failed")); ok)
const GATES = Dict{String,Any}()
const ROWS = Vector{Vector{String}}()
fmt(x::AbstractFloat) = isnan(x) ? "NaN" : @sprintf("%.10g", x)
fmt(x) = string(x)
row(xs...) = push!(ROWS, [fmt(x) for x in xs])
BLAS.set_num_threads(1)
say("S64 C0 TRM open loop, out ", OUTNAME, ", julia threads ", Threads.nthreads(), ", BLAS threads ", BLAS.get_num_threads(), ", ", BLAS.get_config())

# ---------------- G7: the spec and the predictions = the freeze ----------------
const FREEZE = read_sums(joinpath(EXP, "freeze-c0-trm.txt"))
const G7FILES = ["../discussion/specs/S64-c0-trm-openloop.md", "c0_trm/predictions.toml"]
const G7 = length(FREEZE) == 2 && all(f -> get(FREEZE, f, "") == sha(normpath(joinpath(EXP, f))), G7FILES)
say("G7 spec r3 and predictions.toml = freeze-c0-trm.txt: ", G7)
gate("G7", G7)

# ---------------- G0: S57's 6 files and S60's TrmDet.jl, main.rs (and the Mac binary) unchanged ----------------
const S57FILES = ["draw_conf_grid.jl", "check_draw_conf.jl", "check_draw.jl", "synth_world.jl", "../core/circuit.jl", "../core/body_org.jl"]
const S57REF = read_sums(joinpath(EXP, "freeze-draw-conf-code.txt"))
const G0A = all(f -> get(S57REF, f, "") == sha(normpath(joinpath(EXP, f))), S57FILES)
const TRMREF = read_sums(joinpath(EXP, "freeze-trm-det-code.txt"))
const TRMFILES = ["experiments/trm/det/TrmDet.jl", "rust/trm-det/src/main.rs"]
const G0B = all(f -> get(TRMREF, f, "") == sha(joinpath(LAB, f)), TRMFILES)
const RUSTBIN = joinpath(LAB, "rust/trm-det/target/release/trm-det")
const G0BIN = isfile(RUSTBIN) && get(TRMREF, "rust/trm-det/target/release/trm-det", "") == sha(RUSTBIN)
say("G0 S57's 6 files = freeze-draw-conf-code.txt: ", G0A, "; TrmDet.jl, rust/trm-det/src/main.rs = freeze-trm-det-code.txt: ", G0B,
    "; the Mac binary rust/trm-det/target/release/trm-det = the freeze (used as it is, rust/ not built): ", G0BIN)
gate("G0 (code)", G0A && G0B)
const S57 = Module(:S57)
Core.eval(S57, :(include(x) = Base.include($S57, x)))
let src = read(joinpath(EXP, "draw_conf_grid.jl"), String)
    i = findfirst("\nif MODE in (", src); i === nothing && error("anchor: run block")
    pre = src[1:i[1]]
    a = "const MODE = length(ARGS) >= 1 ? ARGS[1] : error(\"mode gates | freeze | pilot | eval\")"
    length(findall(a, pre)) == 1 || error("anchor: MODE")
    include_string(S57, replace(pre, a => "const MODE = \"lib\""), joinpath(EXP, "draw_conf_grid.jl"))
end
include(joinpath(EXP, "trm", "TrmPort.jl"))
include(joinpath(EXP, "trm", "det", "TrmDet.jl"))
include(joinpath(HERE, "TrmC0.jl"))
using .TrmC0: S, V, H, NH, HD, IM, NL, Cfg, CFG_TRM, CFG_1X1
const Mulberry = S57.LabCore.Mulberry

# ---------------- design (predictions.toml, frozen before the runs; checked against the file) ----------------
const PT = TOML.parsefile(joinpath(HERE, "predictions.toml"))
const DEV = collect(1046:1049); const TRAIN = collect(1050:1061); const VAL = collect(1062:1067); const CAL = collect(1068:1073)
const EVAL = collect(1074:1097); const OOD = collect(1098:1109); const NEXT = 1110
const T0 = 800; const STEPS = 10000; const NS = STEPS - T0
const WP = (P = 1000, sigma = 1.0, L = 300, M = 2.5); const BMIN = 6; const BMAX = 24
const OWP = (P = 700, sigma = 1.0, L = 250, M = 2.5); const OBMIN = 7; const OBMAX = 28
const LO = 1 / 200; const HI = 199 / 200; const EPS = 1e-12
const KDEC = 8; const W4 = 4; const ALPHA = 1.0; const ALPHA_R1 = 1.0
const MINOBS = 30; const MINSEEDS = 16; const MINERR = 10; const SIGNA = 0.05; const BOOTB = 5000; const BOOTSEED = 640002
const BATCH = 64; const STRAIN = 800; const INITSEED = 640001; const BATCHSEED = 640100
const ECALSEED = 640200; const ECAL_LR = 1e-3; const ECAL_WD = 0.0; const ECAL_STEPS = 200
const GRID = [(3e-4, 0.0), (3e-4, 1e-2), (1e-3, 0.0), (1e-3, 1e-2)]
const MAXWALL = 10800
const CE = 1.0      # ê's loss coefficient (not fixed by the spec; G2(b): it cannot reach the body or lm_head)
const CHUNK = 64    # examples per forward/backward pass (the whole batch)
let s = PT["seeds"], w = PT["world"], inp = PT["input"], m = PT["model"], t = PT["training"], e = PT["evaluation"]
    ok = s["dev"] == DEV && (s["train_start"]:s["train_end"]) == TRAIN && (s["val_start"]:s["val_end"]) == VAL &&
         (s["cal_start"]:s["cal_end"]) == CAL && (s["eval_start"]:s["eval_end"]) == EVAL && (s["ood_start"]:s["ood_end"]) == OOD &&
         s["next_unused_main_seed"] == NEXT &&
         w["law"] == "L2" && w["arm"] == "UNI" && w["T0"] == T0 == S57.T0 && w["STEPS"] == STEPS == S57.STEPS && w["P"] == WP.P &&
         w["sigma"] == WP.sigma && w["L"] == WP.L && w["M"] == WP.M && (S57.WP.P, S57.WP.sigma, S57.WP.L, S57.WP.M) == (WP.P, WP.sigma, WP.L, WP.M) &&
         w["rev_block_min"] == BMIN && w["rev_block_max"] == BMAX && w["rev_seed_mul"] == 1_000_003 && w["rev_seed_add"] == 63 &&
         w["ood_P"] == OWP.P && w["ood_sigma"] == OWP.sigma && w["ood_L"] == OWP.L && w["ood_M"] == OWP.M &&
         w["ood_rev_block_min"] == OBMIN && w["ood_rev_block_max"] == OBMAX && w["ood_rev_seed_mul"] == 1_000_003 && w["ood_rev_seed_add"] == 64 &&
         inp["W"] == W4 && inp["seq_len"] == S && inp["vocab"] == V && inp["n_receptors_L2"] == 8 && inp["rb_slot_pad"] == true &&
         inp["pad_before_T0"] == true && inp["bos_token"] == 0 && inp["pad_token"] == 0 && inp["r_off_token"] == 1 && inp["r_on_token"] == 2 &&
         inp["act_none_token"] == 3 && inp["act_1_token"] == 4 && inp["act_2_token"] == 5 && inp["y_none_token"] == 6 &&
         inp["y_0_token"] == 7 && inp["y_1_token"] == 8 && inp["q1_token"] == 9 && inp["q2_token"] == 10 &&
         m["hidden"] == H && m["heads"] == NH && m["inter"] == IM && m["L_layers"] == NL && m["trm_H_cycles"] == CFG_TRM.Hc &&
         m["trm_L_cycles"] == CFG_TRM.Lc && m["trm_halt_max_steps"] == CFG_TRM.hmax && m["ctrl_H_cycles"] == CFG_1X1.Hc &&
         m["ctrl_L_cycles"] == CFG_1X1.Lc && m["ctrl_halt_max_steps"] == CFG_1X1.hmax && m["rope_base"] == 10000.0 &&
         m["rms_norm_eps"] == TrmC0.RMS_EPS && m["puzzle_emb_len"] == 0 &&
         t["optimizer"] == "AdamATan2" && t["beta1"] == 0.9 && t["beta2"] == 0.95 && t["opt_a"] == 1.27 && t["opt_b"] == 1.0 &&
         t["warmup_steps"] == 50 && t["batch_size"] == BATCH && t["S_train"] == STRAIN && t["init_seed"] == INITSEED &&
         t["batch_seed_base"] == BATCHSEED && t["ecal_seed"] == ECALSEED && t["ecal_lr"] == ECAL_LR && t["ecal_wd"] == ECAL_WD &&
         t["ecal_steps"] == ECAL_STEPS && t["grid_lr"] == first.(GRID) && t["grid_wd"] == last.(GRID) && t["max_wall_time_sec"] == MAXWALL &&
         e["clip_lo"] == LO && e["clip_hi"] == HI && e["raw_eps"] == EPS && e["b1_decay_k"] == KDEC == S57.LabCore.P_DECAY &&
         e["tab4_window"] == W4 && e["tab4_alpha"] == ALPHA && e["tab_r1_alpha"] == ALPHA_R1 && e["min_obs_per_action"] == MINOBS &&
         e["min_non_tie_seeds"] == MINSEEDS && e["min_err_per_seed"] == MINERR && e["sign_alpha"] == SIGNA &&
         e["bootstrap_B"] == BOOTB && e["bootstrap_seed"] == BOOTSEED && S57.SW_NS == NS && S57.SW_A == 2.5
    ok || error("design constants differ from predictions.toml")
end
clip(p) = clamp(p, LO, HI)
const ROPE = TrmPort.RotaryEmbedding(HD, S, 10000.0)   # (cos, sin), (S, HD) Float32, the official construction
brev(u) = BMIN + floor(Int, (BMAX - BMIN + 1) * Mulberry(1_000_003 * u + 63)())
brev_ood(u) = OBMIN + floor(Int, (OBMAX - OBMIN + 1) * Mulberry(1_000_003 * u + 64)())
function rev_table(g, sr)
    g2 = copy(g)
    for s in sr:size(g, 1)-1; g2[s+1, 1] = g[s+1, 2]; g2[s+1, 2] = g[s+1, 1]; end
    return g2
end
function world_table(u, fam)
    fam == "ood" && return rev_table(S57.synth_table(u, OWP.P, OWP.sigma, OWP.L, OWP.M), OWP.L * brev_ood(u))
    g = S57.synth_table(u, WP.P, WP.sigma, WP.L, WP.M)
    return fam == "stat" ? g : rev_table(g, WP.L * brev(u))
end
function tmapv(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads :greedy for i in eachindex(xs); out[i] = f(xs[i]); end
    return out
end

# ---------------- the streams ----------------
struct Stream
    kind::Symbol; fam::String; seed::Int
    r::BitMatrix                              # (8, NS): receptors r1..r8 at the end of step s (obs); (8, 0) for exo
    act::Vector{Int8}; Y::Vector{Bool}; isex::Vector{Bool}   # indexed by s + 1
    nupd::Int; maxacts::Int; badacts::Int; g2bad::Int; nex::Int; death::Any; names_ok::Bool
end
function exo_stream(u, fam)
    g = world_table(u, fam); bits = S57.gen_bits(u)
    act = Int8[bits[s+1] == 0 ? 1 : 2 for s in 0:NS-1]
    Y = Bool[g[s+1, act[s+1]] > 0 for s in 0:NS-1]
    return Stream(:exo, fam, u, falses(8, 0), act, Y, fill(true, NS), NS, 1, 0, 0, NS, nothing, true)
end
# the run of S57's L2 UNI body in world (u, fam); observe(x) is called at every step from T0 (ON_STEP, read only)
function run_body(u, fam; observe = nothing, prestep = nothing)
    g = world_table(u, fam)
    ext = Dict{Symbol,Any}()
    fam == "stat" || (ext[:SCHED] = (s, k) -> g[s+1, k])
    observe === nothing || (ext[:ON_STEP] = observe)
    prestep === nothing || (ext[:PRESTEP] = prestep)
    return S57.run_arm("L2", "UNI", u; bits = S57.gen_bits(u), extra = (; ext...))
end
function obs_stream(u, fam)
    acting = Vector{Vector{Int}}(undef, STEPS); ys = Vector{Vector{Float64}}(undef, STEPS); seen = falses(STEPS)
    rec = falses(8, NS); names_ok = Ref(false)
    function observe(x)
        x.t >= T0 || return
        acting[x.t+1] = copy(x.acting); ys[x.t+1] = copy(x.y); seen[x.t+1] = true
        for k in 1:8; rec[k, x.t-T0+1] = x.circuit.active[k]; end
        x.t == T0 && (names_ok[] = x.b.names[1:8] == ["r$k" for k in 1:8] && all(==('R'), x.b.kind[1:8]) &&
                                   count(==('R'), x.b.kind) == 8 && x.b.feat[1:8] == collect(1:8) && !("rb" in x.b.names))
    end
    r = run_body(u, fam; observe = observe)
    all(seen[T0+1:STEPS]) || error("obs: a step from T0 was not observed")
    d = r["drawer"]
    ix = [i for i in eachindex(d.lt) if length(d.lcs[i]) >= 2 && d.lt[i] >= T0]
    act = zeros(Int8, NS); Y = falses(NS); isex = falses(NS); maxacts = 0; nupd = 0; badacts = 0
    for t in T0:STEPS-1
        ac = acting[t+1]; maxacts = max(maxacts, length(ac))
        (length(ac) > 1 || (length(ac) == 1 && !(ac[1] in (1, 2)))) && (badacts += 1)
        if length(ac) == 1
            act[t-T0+1] = ac[1]; Y[t-T0+1] = ys[t+1][ac[1]] > 0; nupd += 1
        end
    end
    for i in ix; isex[d.lt[i]-T0+1] = true; end
    # at every example the step's acts are [a] and Y = y[a] > 0 = the drawer's record
    bad = count(i -> (t = d.lt[i]; acting[t+1] != [d.lch[i]] || (ys[t+1][d.lch[i]] > 0) != d.lans[i] || ys[t+1] != d.ly[i]), ix)
    return Stream(:obs, fam, u, rec, act, collect(Bool, Y), collect(Bool, isex), nupd, maxacts, badacts, bad, length(ix), r["death"], names_ok[])
end

# ---------------- the 47-token input (§1.2) ----------------
"column col of tok <- the input of the example at s (records j = s-4..s-1 only; j < 0 PAD). leak :R / :Y = G3's negative controls."
function encode!(tok, col, st::Stream, s::Int, recept::Bool; leak = :none)
    tok[1, col] = 0x00
    for f in 1:W4
        j = s - W4 - 1 + f; base = 1 + (f - 1) * 11
        if j < 0
            for q in 1:11; tok[base+q, col] = 0x00; end
        else
            jr = (leak === :R && f == W4) ? s : j
            for k in 1:8; tok[base+k, col] = recept ? (st.r[k, jr+1] ? 0x02 : 0x01) : 0x00; end
            tok[base+9, col] = 0x00
            a = st.act[j+1]
            tok[base+10, col] = a == 0 ? 0x03 : a == 1 ? 0x04 : 0x05
            jy = (leak === :Y && f == W4) ? s : j
            tok[base+11, col] = st.act[jy+1] == 0 ? 0x06 : st.Y[jy+1] ? 0x08 : 0x07
        end
    end
    tok[46, col] = 0x09; tok[47, col] = 0x0a
    return tok
end
enc(st, s, recept; leak = :none) = vec(encode!(zeros(UInt8, S, 1), 1, st, s, recept; leak = leak))
struct ExSet; seed::Int; tok::Matrix{UInt8}; act::Vector{Int8}; Y::Vector{Bool}; s::Vector{Int}; end
function exset(st::Stream, recept::Bool)
    ss = [s for s in 0:NS-1 if st.isex[s+1]]
    tok = Matrix{UInt8}(undef, S, length(ss))
    for (c, s) in enumerate(ss); encode!(tok, c, st, s, recept); end
    a = st.act[ss.+1]; all(x -> x in (1, 2), a) || error("an example without an act")
    return ExSet(st.seed, tok, a, st.Y[ss.+1], ss)
end
function catsets(v::Vector{ExSet})
    return ExSet(-1, reduce(hcat, [e.tok for e in v]), reduce(vcat, [e.act for e in v]), reduce(vcat, [e.Y for e in v]),
                 reduce(vcat, [e.s for e in v]))
end
const TRACKS = ("obs-full", "obs-ay", "exo")
const FAMS = ("stat", "rev")
const MODELS = ("TRM", "TRM-1x1")
recept_of(track) = track == "obs-full"
kind_of(track) = track == "exo" ? :exo : :obs
cfg_of(model) = model == "TRM" ? CFG_TRM : CFG_1X1

# ---------------- the controls ----------------
code(st, j) = (j < 0 || st.act[j+1] == 0) ? 0 : 2 * (st.act[j+1] - 1) + Int(st.Y[j+1]) + 1
function tabkey(st, s, a)   # audit.jl:303
    k = 0
    for j in s-W4:s-1; k = 5 * k + code(st, j); end
    return 2 * k + a
end
const R1IDX = (1, 2, 3, 4, 7, 8)
function r1key(st, s, a)
    s == 0 && return 2 * 64 + a
    k = 0
    for (i, m) in enumerate(R1IDX); st.r[m, s] && (k += 1 << (i - 1)); end   # record s - 1 is column s
    return 2 * k + a
end
struct Ctrl; rate::Vector{Float64}; n::Vector{Int}; n1::Vector{Int}; tn::Vector{Int}; tn1::Vector{Int}; rn::Vector{Int}; rn1::Vector{Int}; end
function train_ctrl(streams::Vector{Stream})
    n = [0, 0]; n1 = [0, 0]; tn = zeros(Int, 2 * 5^W4); tn1 = zeros(Int, 2 * 5^W4); rn = zeros(Int, 130); rn1 = zeros(Int, 130)
    for st in streams, s in 0:NS-1
        st.isex[s+1] || continue
        a = st.act[s+1]; y = st.Y[s+1]; n[a] += 1; n1[a] += y
        k = tabkey(st, s, a); tn[k] += 1; tn1[k] += y
        if st.kind == :obs; k = r1key(st, s, a); rn[k] += 1; rn1[k] += y; end
    end
    return Ctrl([(n1[a] + 1) / (n[a] + 2) for a in 1:2], n, n1, tn, tn1, rn, rn1)
end
"the controls' P(Y = 1) at the examples of st, in order"
function ctrl_preds(st::Stream, c::Ctrl)
    out = Dict(k => Float64[] for k in ("RATE", "B1", "TAB4", "TAB_R1"))
    m = [0.5, 0.5]
    for s in 0:NS-1
        a = st.act[s+1]
        if st.isex[s+1]
            k = tabkey(st, s, a)
            push!(out["RATE"], clip(c.rate[a])); push!(out["B1"], clip(m[a]))
            push!(out["TAB4"], clip((c.tn1[k] + ALPHA * c.rate[a]) / (c.tn[k] + ALPHA)))
            if st.kind == :obs
                kr = r1key(st, s, a)
                push!(out["TAB_R1"], clip((c.rn1[kr] + ALPHA_R1 * c.rate[a]) / (c.rn[kr] + ALPHA_R1)))
            end
        end
        a != 0 && (m[a] += ((st.Y[s+1] ? 1.0 : 0.0) - m[a]) / KDEC)
    end
    return out
end

# ---------------- models: training and prediction (top-level functions, no captured locals) ----------------
const POOLS = Dict{Tuple{String,String},ExSet}()
const SETS = Dict{Tuple{String,String,Int},ExSet}()   # (track, fam, seed); fam "ood" for the OOD seeds
function train_model(pool::ExSet, model, grid; nsteps = STRAIN, ce = CE, sampler_grid = grid)
    cfg = cfg_of(model); lr, wd = GRID[grid]
    p = TrmC0.init_params(Mulberry(INITSEED))
    w = TrmC0.WorkSet{Float32}(cfg.Lc + 1, ROPE...)
    g = TrmC0.Params{Float32}(); o = TrmC0.Opt(p)
    r = Mulberry(BATCHSEED + sampler_grid); n = size(pool.tok, 2)
    tok = Matrix{UInt8}(undef, S, BATCH); act = Vector{Int}(undef, BATCH); Y = Vector{Bool}(undef, BATCH)
    trace = Float64[]
    for t in 1:nsteps
        for b in 1:BATCH
            i = 1 + floor(Int, n * r())
            for q in 1:S; tok[q, b] = pool.tok[q, i]; end
            act[b] = pool.act[i]; Y[b] = pool.Y[i]
        end
        L = TrmC0.train_step!(p, g, o, w, cfg, tok, act, Y, lr, wd; ce = ce)
        push!(trace, L[1])
    end
    return p, trace
end
"P(Y = 1) and ê at the chosen action of every example of es, and z_H at its question column (each distinct input once)"
function predict_set(p, cfg::Cfg, es::ExSet; keepz = false)
    n = size(es.tok, 2)
    ids = Dict{Vector{UInt8},Int}(); uniq = Int[]; idx = Vector{Int}(undef, n)
    for c in 1:n
        k = es.tok[:, c]
        j = get(ids, k, 0)
        if j == 0; push!(uniq, c); j = length(uniq); ids[k] = j; end
        idx[c] = j
    end
    nu = length(uniq)
    P = zeros(2, nu); E = zeros(2, nu); Z = keepz ? zeros(Float32, H, 2, nu) : zeros(Float32, 0, 0, 0)
    w = TrmC0.Work{Float32}(CHUNK, 0, ROPE...)
    tokc = Matrix{UInt8}(undef, S, CHUNK); pp = zeros(2, CHUNK); ee = zeros(2, CHUNK); zq = zeros(Float32, H, 2, CHUNK)
    for c0 in 0:CHUNK:nu-1
        m = min(CHUNK, nu - c0)
        for b in 1:CHUNK, q in 1:S; tokc[q, b] = es.tok[q, uniq[c0+min(b, m)]]; end   # the last chunk padded with its last input
        TrmC0.predict!(pp, ee, zq, w, p, cfg, tokc)
        for b in 1:m
            P[:, c0+b] .= pp[:, b]; E[:, c0+b] .= ee[:, b]
            keepz && (Z[:, :, c0+b] .= zq[:, :, b])
        end
    end
    pa = [P[es.act[c], idx[c]] for c in 1:n]; ea = [E[es.act[c], idx[c]] for c in 1:n]
    za = keepz ? reduce(hcat, [Z[:, es.act[c], idx[c]] for c in 1:n]) : zeros(Float32, H, 0)
    return (p = pa, e = ea, z = za, nuniq = nu)
end
"per-action mean log loss averaged over the two actions, and the counts"
function score(p::Vector{Float64}, act, Y; raw = false)
    L = [0.0, 0.0]; n = [0, 0]
    for i in eachindex(p)
        a = act[i]; q = raw ? (Y[i] ? max(p[i], EPS) : max(1 - p[i], EPS)) : (Y[i] ? p[i] : 1 - p[i])
        L[a] += -log(q); n[a] += 1
    end
    sc = (n[1] == 0 || n[2] == 0) ? NaN : (L[1] / n[1] + L[2] / n[2]) / 2
    return (sc = sc, n = n)
end
function train_job(job)
    track, fam, model, grid = job
    t0 = time()
    p, trace = train_model(POOLS[(track, fam)], model, grid)
    t1 = time()
    cfg = cfg_of(model)
    val = Any[]
    for u in VAL
        es = SETS[(track, fam, u)]
        pr = predict_set(p, cfg, es)
        push!(val, (seed = u, s = score(clip.(pr.p), es.act, es.Y), nuniq = pr.nuniq))
    end
    return (job = job, p = p, trace = trace, val = val, ttrain = t1 - t0, tval = time() - t1)
end
function pred_job(u)
    key, model, cfg, track, fam, seed, keepz = u
    t0 = time()
    pr = predict_set(SELP[key], cfg, SETS[(track, fam, seed)]; keepz = keepz)
    return (unit = u, pr = pr, t = time() - t0)
end
const SELP = Dict{Any,Any}()

# ---------------- statistics ----------------
function signtest(wins, losses)
    n = wins + losses; n == 0 && return 1.0
    k = min(wins, losses)
    return Float64(min(big(1), 2 * sum(binomial(big(n), big(i)) for i in 0:k) / big(2)^n))
end
function qtl(sv, p)   # type 7 on sorted values
    h = (length(sv) - 1) * p + 1; lo = floor(Int, h); hi = min(lo + 1, length(sv))
    return sv[lo] + (h - lo) * (sv[hi] - sv[lo])
end
function boot(d)
    n = length(d); r = Mulberry(BOOTSEED); mb = Vector{Float64}(undef, BOOTB)
    for b in 1:BOOTB
        s = 0.0
        for _ in 1:n; s += d[1+floor(Int, n * r())]; end
        mb[b] = s / n
    end
    sort!(mb)
    return (qtl(mb, 0.025), qtl(mb, 0.975))
end
median_(v) = (s = sort(v); qtl(s, 0.5))
"d = per-seed differences (positive = the first named better); the C0 criterion"
function compare(d::Vector{Float64})
    n = length(d)
    n == 0 && return Dict{String,Any}("n" => 0, "wins" => 0, "losses" => 0, "ties" => 0, "p_sign" => 1.0, "pass" => false, "detectable" => false)
    w = count(>(0), d); l = count(<(0), d); ci = boot(d); p = signtest(w, l)
    return Dict{String,Any}("n" => n, "wins" => w, "losses" => l, "ties" => n - w - l, "p_sign" => p, "mean" => sum(d) / n,
                            "median" => median_(d), "min" => minimum(d), "max" => maximum(d), "ci95" => collect(ci),
                            "detectable" => w + l >= MINSEEDS, "pass" => p < SIGNA && w > l && w + l >= MINSEEDS)
end

# ---------------- PAV (ê's control p_cal) ----------------
"monotone non-decreasing fit of z on x: equal x pooled first; blocks (x_lo, value); prediction = the block with the largest
x_lo <= x (the first block below its range), clipped"
function pav_fit(x::Vector{Float64}, z::Vector{Bool})
    o = sortperm(x)
    xs = Float64[]; ws = Float64[]; vs = Float64[]
    for i in o
        if !isempty(xs) && x[i] == xs[end]
            vs[end] += z[i]; ws[end] += 1
        else
            push!(xs, x[i]); push!(ws, 1.0); push!(vs, Float64(z[i]))
        end
    end
    bl = Vector{Tuple{Float64,Float64,Float64}}()   # (x_lo, weight, sum)
    for i in eachindex(xs)
        push!(bl, (xs[i], ws[i], vs[i]))
        while length(bl) >= 2 && bl[end-1][3] / bl[end-1][2] > bl[end][3] / bl[end][2]
            a = pop!(bl); b = pop!(bl)
            push!(bl, (b[1], a[2] + b[2], a[3] + b[3]))
        end
    end
    return ([b[1] for b in bl], [b[3] / b[2] for b in bl])
end
function pav_pred(f, x)
    xl, v = f
    i = searchsortedlast(xl, x); i == 0 && (i = 1)
    return clip(v[i])
end
bce(q, z) = z ? -log(q) : -log(1 - q)

# ---------------- gates on the model: G4, G2, G-TIME, G3, G1 ----------------
function gate_g4()
    Ls = [-50.0, -1.0, 0.0, 1.0, 50.0]
    inr = all(0 < TrmC0.p2(a, b) < 1 for a in Ls, b in Ls)
    sym = maximum(abs(TrmC0.p2(a, b) + TrmC0.p2(b, a) - 1) for a in Ls, b in Ls)
    mono = all(TrmC0.p2(Ls[i+1], b) > TrmC0.p2(Ls[i], b) for i in 1:4, b in Ls) && all(TrmC0.p2(a, Ls[i+1]) < TrmC0.p2(a, Ls[i]) for i in 1:4, a in Ls)
    fd(f, x, e) = (f(x + e) - f(x - e)) / (2e)
    function maxrel(dmut)
        m = 0.0
        for a in Ls, b in Ls, y in (false, true)
            _, g8, g7, _ = TrmC0.lmloss(a, b, y)
            if dmut
                s8 = TrmC0.smx(a); s7 = TrmC0.smx(b); z = s8 + s7; dw(x) = x >= 0 ? 1.0 : 1.0 / (1.0 - x)   # wrong s' (negative control)
                g8 = ((y ? -1 / s8 : 0.0) + 1 / z) * dw(a); g7 = ((y ? 0.0 : -1 / s7) + 1 / z) * dw(b)
            end
            n8 = fd(x -> TrmC0.lmloss(x, b, y)[1], a, 1e-6); n7 = fd(x -> TrmC0.lmloss(a, x, y)[1], b, 1e-6)
            m = max(m, abs(g8 - n8) / max(abs(n8), 1e-9), abs(g7 - n7) / max(abs(n7), 1e-9))
        end
        return m
    end
    r = maxrel(false); rn = maxrel(true)
    ok = inr && sym <= 4e-16 && mono && r <= 1e-5 && rn > 1e-5
    say("G4 two-word stablemax on l in {-50,-1,0,1,50}^2: p in (0,1) ", inr, ", max |p(a,b) + p(b,a) - 1| ", sym, ", monotone ", mono,
        ", gradient vs central difference (eps 1e-6) max rel ", @sprintf("%.2e", r), "   neg: s' without the square, max rel (must be > 1e-5) ",
        @sprintf("%.2e", rn), " -> ", ok)
    GATES["G4"] = Dict("pass" => ok, "max_sym" => sym, "max_rel_grad" => r, "neg_max_rel" => rn)
    return ok
end

function gate_g2c()
    # AdamATan2 on a 2-D weight (lm_head row 1, wd applies) and a bias (e_head.bias, no wd), 5 fixed gradients
    th0 = [0.5, -0.3, 0.0, 1.2]; b0 = 0.7
    gs = [[0.1, -0.2, 0.0, 0.05], [0.3, 0.1, -0.4, 0.0], [-0.2, 0.05, 0.2, 0.1], [0.0, -0.1, 0.3, -0.3], [0.15, 0.2, -0.05, 0.4]]
    gb = [0.2, -0.1, 0.05, 0.3, -0.25]
    lr = 1e-3; wd = 1e-2; b1 = 0.9; b2 = 0.95; A = 1.27; Bb = 1.0
    # closed form: m_t = (1 - b1) sum_k b1^(t-k) g_k, v_t = (1 - b2) sum_k b2^(t-k) g_k^2, eta_t = lr t / 50
    function refpath(th, gl, dec)
        x = copy(th)
        for t in 1:5
            eta = lr * t / 50
            for j in eachindex(x)
                m = (1 - b1) * sum(b1^(t - k) * gl[k][j] for k in 1:t); v = (1 - b2) * sum(b2^(t - k) * gl[k][j]^2 for k in 1:t)
                x[j] = x[j] * (1 - eta * dec) - eta * A * atan(m / (1 - b1^t), Bb * sqrt(v / (1 - b2^t)))
            end
        end
        return x
    end
    rw = refpath(th0, gs, wd); rb = refpath([b0], [[x] for x in gb], 0.0)[1]
    function run(T; bc = true)
        p = TrmC0.Params{T}(); g = TrmC0.Params{T}(); o = TrmC0.Opt(p)
        p.lm[1, 1:4] .= T.(th0); p.eb[1] = T(b0)
        for t in 1:5
            TrmC0.zero_params!(g); g.lm[1, 1:4] .= T.(gs[t]); g.eb[1] = T(gb[t])
            TrmC0.adam_step!(p, g, o, lr, wd; bias_correct = bc)
        end
        others = all(i -> i in (10, 12) || all(iszero, TrmC0.plist(p)[i]), 1:14) && all(iszero, p.lm[2:end, :]) && all(iszero, p.lm[1, 5:end])
        return max(maximum(abs.(Float64.(p.lm[1, 1:4]) .- rw)), abs(Float64(p.eb[1]) - rb)), others
    end
    d64, o64 = run(Float64); d32, o32 = run(Float32); dn, _ = run(Float64; bc = false)
    ok = d64 <= 1e-6 && d32 <= 1e-6 && o64 && o32 && dn > 1e-6
    say("G2(c) AdamATan2 5 steps vs the closed form: max |diff| Float64 ", @sprintf("%.2e", d64), ", Float32 ", @sprintf("%.2e", d32),
        ", untouched arrays stay 0 ", o64 && o32, "   neg: no bias correction, max |diff| (must be > 1e-6) ", @sprintf("%.2e", dn), " -> ", ok)
    GATES["G2c"] = Dict("pass" => ok, "max_diff_f64" => d64, "max_diff_f32" => d32, "neg_max_diff" => dn)
    return ok
end

# G2(a): Float64 central differences (eps 1e-4) at the recorded detach points, ê's target and z_H fixed, against the backward
# lm_head and e_head are zero at the initialization (no gradient would reach the body): for G2(a), (d) only they are drawn
# from the same stream after the initialization, sigma = 1/sqrt(32)
function g2params()
    r = Mulberry(INITSEED)
    p32 = TrmC0.init_params(r)
    L = zeros(Float64, V, H); TrmC0.fill_rm!(L, TrmC0.tnorm(r, V * H, 1 / sqrt(H))); p32.lm .= Float32.(L)
    p32.ew .= Float32.(reshape(TrmC0.tnorm(r, H, 1 / sqrt(H)), 1, H)); p32.eb .= Float32.(TrmC0.tnorm(r, 1, 1 / sqrt(H)))
    return TrmC0.convert_params(Float64, p32)
end
function g2a_one(cfg::Cfg, es::ExSet)
    p = g2params()
    B = 4
    tok = es.tok[:, 1:B]; act = Int.(es.act[1:B]); Y = es.Y[1:B]
    w = TrmC0.Work{Float64}(B, cfg.Lc + 1, ROPE...)
    g = TrmC0.Params{Float64}(); rec = TrmC0.GradRec{Float64}()
    TrmC0.grad!(g, p, w, cfg, tok, act, Y; ce = CE, rec = rec)
    eps = 1e-4
    function check(gg)
        local worst = 0.0; local per = Dict{String,Float64}()   # local: the closure must not share the caller's names
        for (i, nm) in enumerate(TrmC0.PNAMES)
            th = TrmC0.plist(p)[i]; ga = TrmC0.plist(gg)[i]; n = length(th)
            gmax = maximum(abs, ga)
            idx = unique(vcat(partialsortperm(vec(abs.(ga)), 1:min(8, n); rev = true), round.(Int, range(1, n; length = min(8, n)))))
            m = 0.0
            for j in idx
                old = th[j]
                th[j] = old + eps; lp = TrmC0.loss_fixed(p, w, cfg, tok, act, Y, rec; ce = CE)
                th[j] = old - eps; lm = TrmC0.loss_fixed(p, w, cfg, tok, act, Y, rec; ce = CE)
                th[j] = old
                num = (lp - lm) / (2eps); a = ga[j]
                den = max(abs(a), abs(num), 1e-6 * gmax)
                rel = den == 0 ? (a == num ? 0.0 : Inf) : abs(a - num) / den
                m = max(m, rel)
            end
            per[nm] = m; worst = max(worst, m)
        end
        return worst, per
    end
    worst, per = check(g)
    TrmC0.MUT[] = :sign
    gneg = TrmC0.Params{Float64}()
    TrmC0.grad!(gneg, p, w, cfg, tok, act, Y; ce = CE, rec = TrmC0.GradRec{Float64}())
    TrmC0.MUT[] = :none
    wneg, _ = check(gneg)
    zero_groups = [nm for (i, nm) in enumerate(TrmC0.PNAMES) if all(iszero, TrmC0.plist(g)[i])]
    return worst, per, wneg, zero_groups
end
function gate_g2a(es)
    ok = true; out = Dict{String,Any}()
    for (nm, cfg) in (("TRM", CFG_TRM), ("TRM-1x1", CFG_1X1))
        worst, per, wneg, zg = g2a_one(cfg, es)
        o = worst <= 1e-4 && wneg > 1e-4
        ok &= o
        say("G2(a) ", nm, ": Float64 central difference (eps 1e-4, detach points / ê target / ê's z_H fixed) vs backward, max rel per group: ",
            join(["$k $(@sprintf("%.1e", per[k]))" for k in TrmC0.PNAMES], ", "), "; worst ", @sprintf("%.2e", worst),
            "; groups with exactly zero gradient: ", isempty(zg) ? "none" : join(zg, " "),
            "   neg: sign flip in the RMS-norm backward, worst (must be > 1e-4) ", @sprintf("%.2e", wneg), " -> ", o)
        out[nm] = Dict("worst" => worst, "per_group" => per, "neg_worst" => wneg, "zero_groups" => zg, "pass" => o)
    end
    GATES["G2a"] = merge(out, Dict("pass" => ok))
    return ok
end
# G2(d): the batch's distinct inputs as single columns (training) = every example its own column, Float64, 64 exo dev examples
function g2d_job(model)
    cfg = cfg_of(model); p = g2params(); pool = POOLS[("dev-exo", "stat")]
    tok = pool.tok[:, 1:BATCH]; act = Int.(pool.act[1:BATCH]); Y = pool.Y[1:BATCH]
    g1 = TrmC0.Params{Float64}(); g2 = TrmC0.Params{Float64}()
    l1 = TrmC0.grad!(g1, p, TrmC0.Work{Float64}(BATCH, cfg.Lc + 1, ROPE...), cfg, tok, act, Y; ce = CE)
    l2 = TrmC0.grad!(g2, p, TrmC0.WorkSet{Float64}(cfg.Lc + 1, ROPE...), cfg, tok, act, Y; ce = CE)
    m = 0.0
    for (a, b) in zip(TrmC0.plist(g1), TrmC0.plist(g2))
        s = maximum(abs, a); m = max(m, s == 0 ? maximum(abs, b) : maximum(abs.(a .- b)) / s)
    end
    return (model = model, rel = m, dl = maximum(abs.(collect(l1) .- collect(l2))), nuniq = length(unique(eachcol(tok))))
end
function gate_g2d()
    rs = tmapv(g2d_job, collect(MODELS)); ok = true
    for x in rs
        o = x.rel <= 1e-9 && x.dl <= 1e-12 && x.nuniq < BATCH; ok &= o
        say("G2(d) ", x.model, ": 64 exo dev examples (", x.nuniq, " distinct inputs) as distinct columns vs one column each (Float64): max rel diff of the gradient ",
            @sprintf("%.1e", x.rel), " (<= 1e-9), of the losses ", @sprintf("%.1e", x.dl), " -> ", o)
    end
    GATES["G2d"] = Dict("pass" => ok)
    return ok
end
function g2b_job((model, ce))
    p, _ = train_model(POOLS[("dev-obs-full", "stat")], model, 4; nsteps = 10, ce = ce)
    pr = predict_set(p, cfg_of(model), SETS[("obs-full", "stat", DEV[1])])
    return (model = model, ce = ce, p = p, pa = pr.p)
end
function gate_g2b()
    rs = tmapv(g2b_job, [(m, c) for m in MODELS for c in (0.0, 10.0)])
    ok = true; out = Dict{String,Any}()
    for m in MODELS
        a = only(filter(x -> x.model == m && x.ce == 0.0, rs)); b = only(filter(x -> x.model == m && x.ce == 10.0, rs))
        body = all(i -> TrmC0.plist(a.p)[i] == TrmC0.plist(b.p)[i], TrmC0.BODY) &&
               all(i -> reinterpret(UInt32, vec(TrmC0.plist(a.p)[i])) == reinterpret(UInt32, vec(TrmC0.plist(b.p)[i])), TrmC0.BODY)
        pa = reinterpret(UInt64, a.pa) == reinterpret(UInt64, b.pa)
        ehead = a.p.ew != b.p.ew && all(iszero, a.p.ew)
        o = body && pa && ehead; ok &= o
        say("G2(b) ", m, ": 10 updates with ê's coefficient 0 and 10: body and lm_head bit-identical ", body, ", p_a on dev u", DEV[1],
            " (", length(a.pa), " examples) bit-identical ", pa, "   (e_head differs, and is 0 with coefficient 0: ", ehead, ") -> ", o)
        out[m] = o
    end
    GATES["G2b"] = merge(out, Dict("pass" => ok))
    return ok
end

# G-TIME: n concurrent copies (one per Julia thread) of 1 + 10 updates on dev; s/update under full load
function gtime_job((track, model, i))
    pool = POOLS[("dev-" * track, "stat")]; cfg = cfg_of(model); lr, wd = GRID[4]
    p = TrmC0.init_params(Mulberry(INITSEED)); w = TrmC0.WorkSet{Float32}(cfg.Lc + 1, ROPE...)
    g = TrmC0.Params{Float32}(); o = TrmC0.Opt(p); r = Mulberry(BATCHSEED + 4); n = size(pool.tok, 2)
    tok = Matrix{UInt8}(undef, S, BATCH); act = Vector{Int}(undef, BATCH); Y = Vector{Bool}(undef, BATCH)
    function one()
        for b in 1:BATCH
            j = 1 + floor(Int, n * r()); tok[:, b] .= view(pool.tok, :, j); act[b] = pool.act[j]; Y[b] = pool.Y[j]
        end
        TrmC0.train_step!(p, g, o, w, cfg, tok, act, Y, lr, wd)
    end
    one()
    t = @elapsed for _ in 1:10; one(); end
    return (track = track, model = model, i = i, t = t / 10, p = p)
end
function lpt(durs, k)
    loads = zeros(k)
    for d in sort(durs; rev = true); loads[argmin(loads)] += d; end
    return maximum(loads)
end
const DEVMODEL = Ref{Any}(nothing)
function gate_gtime()
    nt = Threads.nthreads(); out = Dict{String,Any}(); tper = Dict{String,Float64}(); same = true
    for tr in TRACKS, m in MODELS
        rs = tmapv(gtime_job, [(tr, m, i) for i in 1:nt])
        ts = sort([x.t for x in rs]); tper["$tr $m"] = ts[(nt+1)÷2]
        same &= all(x -> TrmC0.param_bytes(x.p) == TrmC0.param_bytes(rs[1].p), rs)
        (tr == "obs-full" && m == "TRM") && (DEVMODEL[] = rs[1].p)
        say("G-TIME ", tr, " ", m, ": ", nt, " concurrent copies x 10 updates on dev (stat): s/update ", join([@sprintf("%.3f", x) for x in ts], " "))
    end
    durs = [STRAIN * tper["$tr $m"] for tr in TRACKS for f in FAMS for m in MODELS for gi in 1:4]
    est = lpt(durs, nt)
    ok = est <= MAXWALL
    say("G-TIME estimate of the 48 trainings (", STRAIN, " updates each; per track and model from its dev s/update; LPT on ", nt, " threads): ",
        @sprintf("%.0f", est), " s (limit ", MAXWALL, " s); serial sum ", @sprintf("%.0f", sum(durs)), " s; the copies bit-identical ", same, " -> ", ok)
    GATES["G-TIME"] = Dict("pass" => ok && same)   # the times themselves go to results.out and gtime.json only
    write(joinpath(OUT, "gtime.json"), JSON.json(Dict("threads" => nt, "s_per_update" => tper, "estimate_s" => est, "limit_s" => MAXWALL,
                                                      "serial_s" => sum(durs), "copies_identical" => same)))
    return ok && same
end

# G3: y[t] changed at 25 examples of each dev seed, the step recomputed from the state before it (S57's capture and
# step_draw_conf!, nw included); the input at t and (p_t, ê_t) must not change, the input at t + 1 must; LEAK_R / LEAK_Y must.
function spread(v, n)
    length(v) <= n && return v
    return v[unique(round.(Int, range(1, length(v); length = n)))]
end
function g3_job((u, fam))
    st = STREAMS[(:obs, fam, u)]
    cand = [s for s in 4:NS-2 if st.isex[s+1]]
    ts = Set(T0 .+ spread(cand, 25)); cap = Dict{Int,Any}()
    run_body(u, fam; prestep = x -> (x.t in ts && (cap[x.t] = S57.capture(x))))
    kw = S57.stepkw("L2")
    res = NamedTuple[]
    for t in sort(collect(ts))
        s = t - T0
        function rerun(change)
            z = deepcopy(cap[t]); z.drawer.t = t
            change && (for k in 1:2; z.yin[k] = z.yin[k] > 0 ? 0.0 : 5.0; end)
            o = S57.step_draw_conf!(z.circuit, z.b, z.yin; noise = z.noise, sil = z.sil, draw = z.drawer, kw...)
            ac = [z.b.patch[m] for m in o.acting if z.b.patch[m] <= 2]
            return (r = z.circuit.active[1:8], ac = ac, Y = length(ac) == 1 ? z.yin[ac[1]] > 0 : false)
        end
        o0 = rerun(false); o1 = rerun(true)
        rep = o0.r == st.r[:, s+1] && o0.ac == [st.act[s+1]] && o0.Y == st.Y[s+1]
        r2 = copy(st.r); act2 = copy(st.act); Y2 = copy(st.Y)
        r2[:, s+1] .= o1.r; act2[s+1] = length(o1.ac) == 1 ? o1.ac[1] : 0; Y2[s+1] = o1.Y
        st2 = Stream(st.kind, st.fam, st.seed, r2, act2, Y2, st.isex, 0, 0, 0, 0, 0, nothing, true)
        push!(res, (t = t, rep = rep, changed = (o1.r != o0.r || o1.Y != o0.Y), same_act = o1.ac == o0.ac,
                    in_t = enc(st, s, true) == enc(st2, s, true), in_next = enc(st, s + 1, true) != enc(st2, s + 1, true),
                    leakR = enc(st, s, true; leak = :R) != enc(st2, s, true; leak = :R), leakY = enc(st, s, true; leak = :Y) != enc(st2, s, true; leak = :Y),
                    tok = (enc(st, s, true), enc(st2, s, true), enc(st, s, true; leak = :R), enc(st2, s, true; leak = :R),
                           enc(st, s, true; leak = :Y), enc(st2, s, true; leak = :Y)), a = st.act[s+1]))
    end
    return (u = u, fam = fam, res = res)
end
# one input at a time in a one-column work space (the original and the changed input in the same position)
const G3W = Ref{Any}(nothing)
function g3_pred(p, tokv, a)
    G3W[] === nothing && (G3W[] = TrmC0.Work{Float32}(1, 0, ROPE...))
    pp = zeros(2, 1); ee = zeros(2, 1); zq = zeros(Float32, H, 2, 1)
    TrmC0.predict!(pp, ee, zq, G3W[], p, CFG_TRM, reshape(tokv, S, 1))
    return (pp[a, 1], ee[a, 1])
end
function gate_g3()
    rs = tmapv(g3_job, [(u, f) for f in FAMS for u in DEV])
    p = DEVMODEL[]
    ok = true; out = Dict{String,Any}()
    for f in FAMS
        R = reduce(vcat, [x.res for x in rs if x.fam == f])
        n = length(R)
        pe = 0; pdR = 0; pdY = 0
        for x in R
            a0 = g3_pred(p, x.tok[1], x.a); a1 = g3_pred(p, x.tok[2], x.a)
            pe += reinterpret(UInt64, collect(a0)) == reinterpret(UInt64, collect(a1))
            pdR += g3_pred(p, x.tok[3], x.a)[1] != g3_pred(p, x.tok[4], x.a)[1]
            pdY += g3_pred(p, x.tok[5], x.a)[1] != g3_pred(p, x.tok[6], x.a)[1]
        end
        c(k) = count(x -> getfield(x, k), R)
        o = n == 100 && c(:rep) == n && c(:changed) == n && c(:in_t) == n && pe == n && c(:in_next) == n && c(:leakR) == n && c(:leakY) == n &&
            pdR > 0 && pdY > 0
        ok &= o
        say("G3 obs-full ", f, " (dev ", join(DEV, " "), ", ", n, " examples): the step rerun from its state reproduces the record ", c(:rep), "/", n,
            "; y[t] changed -> the step's record changed ", c(:changed), "/", n, " (act unchanged ", c(:same_act), "/", n, "); input at t bit-identical ",
            c(:in_t), "/", n, ", (p_t, ê_t) bit-identical ", pe, "/", n, ", input at t+1 changed ", c(:in_next), "/", n,
            "   neg: LEAK_R input changed ", c(:leakR), "/", n, ", p_t changed ", pdR, "/", n, "; LEAK_Y input changed ", c(:leakY), "/", n,
            ", p_t changed ", pdY, "/", n, " (model: TRM after 11 updates on dev) -> ", o)
        out[f] = Dict("n" => n, "pass" => o, "p_changed_leakR" => pdR, "p_changed_leakY" => pdY)
    end
    GATES["G3"] = merge(out, Dict("pass" => ok))
    return ok
end

# G1: a TRMDET1 bundle (seq_len 47, vocab 12, RoPE tables (47, 8)) of the weights; the final ACT step of TrmC0 vs TrmPort
# (<= 1e-4), and the frozen S60 tools: run_det.jl (TrmDet) vs the Mac binary rust/trm-det (bit-identical; 1-ulp control m4)
function make_bundle(path, p, cfg::Cfg, tok8)
    R = TrmDet
    st = TrmC0.official_state(p); B = size(tok8, 2)
    recs = R.Rec[R.RecI("cfg", (13,), Int32[B, S, V, H, NH, IM, cfg.Hc, cfg.Lc, NL, cfg.hmax, 1, 0, 4]),
                 R.RecF("const", (3,), Float32[Float32(1e-5), Float32(0.707106781), sqrt(Float32(H))])]
    for name in sort!(collect(keys(st))); a = st[name]; push!(recs, R.RecF(name, size(a), Float32.(R.to_rm(a)))); end
    push!(recs, R.RecF("rope.cos", size(ROPE[1]), R.to_rm(ROPE[1])), R.RecF("rope.sin", size(ROPE[2]), R.to_rm(ROPE[2])))
    xs = (tok8, tok8[:, [B; 1:B-1]], tok8[:, B:-1:1])
    for k in 1:3
        push!(recs, R.RecI("x$k.inputs", (B, S), Int32.(R.to_rm(permutedims(xs[k])))), R.RecI("x$k.pid", (B,), zeros(Int32, B)))
    end
    push!(recs, R.RecI("steps.input", (4,), Int32[1, 1, 1, 1]), R.RecI("mixed.input", (1,), Int32[2]),
          R.RecI("mixed.start_halted", (B,), Int32[b % 2 for b in 1:B]))
    R.write_recs(path, R.MAGIC_BUNDLE, recs)
end
function trmport_final(p, cfg::Cfg, tok8)
    B = size(tok8, 2)
    names = [:hidden_size, :num_heads, :puzzle_emb_ndim, :seq_len, :puzzle_emb_len, :mlp_t, :expansion, :rms_norm_eps, :vocab_size,
             :pos_encodings, :rope_theta, :L_layers, :H_cycles, :L_cycles, :halt_max_steps, :batch_size, :num_puzzle_identifiers]
    vals = Any[H, NH, 0, S, 0, false, 4.0, 1e-5, V, "rope", 10000.0, NL, cfg.Hc, cfg.Lc, cfg.hmax, B, 1]
    model = TrmPort.ACTModel((names = names, values = vals), TrmC0.official_state(p))
    batch = Dict{String,Any}("inputs" => Int.(permutedims(tok8)), "puzzle_identifiers" => zeros(Int, B))
    carry = TrmPort.initial_carry(model, batch); out = nothing
    for _ in 1:cfg.hmax; carry, out = TrmPort.act_forward(model, carry, batch); end
    return out["logits"], carry.z_H
end
function trmc0_final(p, cfg::Cfg, tok8)
    B = size(tok8, 2)
    w = TrmC0.Work{Float32}(B, 0, ROPE...)
    zH, _ = TrmC0.final_state!(w, p, cfg, tok8)
    lg = p.lm * zH
    L = Array{Float32}(undef, B, S, V); Z = Array{Float32}(undef, B, S, H)
    for b in 1:B, s in 1:S
        n = s + S * (b - 1)
        L[b, s, :] .= lg[:, n]; Z[b, s, :] .= zH[:, n]
    end
    return L, Z
end
function runcmd(cmd, outf)
    ok = success(pipeline(ignorestatus(cmd); stdout = outf, stderr = outf * ".err"))
    return ok
end
function gate_g1(label, p, cfg::Cfg, tok8)
    dir = joinpath(OUT, "g1"); bun = joinpath(dir, label * ".bin"); jl = joinpath(dir, label * ".jl.bin"); rs = joinpath(dir, label * ".rs.bin")
    make_bundle(bun, p, cfg, tok8)
    jlc = `julia --project=$LAB $(joinpath(EXP, "trm", "det", "run_det.jl")) $bun $jl`
    okj = runcmd(jlc, joinpath(dir, label * ".jl.txt"))
    okr = runcmd(`$RUSTBIN $bun $rs`, joinpath(dir, label * ".rs.txt"))
    cmp = `julia --project=$LAB $(joinpath(EXP, "trm", "det", "compare_bin.jl")) $bun $jl $rs`
    okc = okj && okr && runcmd(cmp, joinpath(dir, label * ".cmp.txt"))
    cmptxt = isfile(joinpath(dir, label * ".cmp.txt")) ? read(joinpath(dir, label * ".cmp.txt"), String) : ""
    # negative control m4: embed_tokens[t, 0] + 1 ulp (t = the first input token) in the bundle given to Rust
    mut = joinpath(dir, label * ".m4.bin"); rsm = joinpath(dir, label * ".m4.rs.bin")
    okm = runcmd(`julia --project=$LAB $(joinpath(EXP, "trm", "det", "mutate_bin.jl")) m4 $bun $mut`, joinpath(dir, label * ".m4.txt")) &&
          runcmd(`$RUSTBIN $mut $rsm`, joinpath(dir, label * ".m4.rs.txt"))
    negc = okm && !runcmd(`julia --project=$LAB $(joinpath(EXP, "trm", "det", "compare_bin.jl")) $bun $jl $rsm`, joinpath(dir, label * ".m4.cmp.txt"))
    negtxt = isfile(joinpath(dir, label * ".m4.cmp.txt")) ? read(joinpath(dir, label * ".m4.cmp.txt"), String) : ""
    neg = negc && occursin(r"differing [1-9]", negtxt) && !occursin("FAILED structure", negtxt)
    # TrmC0 and TrmPort at the final ACT step; TrmDet's records of that step
    kf = cfg.hmax
    Lc, Zc = trmc0_final(p, cfg, tok8); Lp, Zp = trmport_final(p, cfg, tok8)
    dcp = max(maximum(abs.(Float64.(Lc) .- Float64.(Lp))), maximum(abs.(Float64.(Zc) .- Float64.(Zp))))
    dcd = NaN; dpd = NaN
    if okj
        d = TrmDet.recdict(TrmDet.read_recs(jl, TrmDet.MAGIC_OUT))
        Ld = TrmDet.to_jl(d["step$kf.logits"].f, d["step$kf.logits"].dims); Zd = TrmDet.to_jl(d["step$kf.z_H"].f, d["step$kf.z_H"].dims)
        dcd = max(maximum(abs.(Float64.(Lc) .- Float64.(Ld))), maximum(abs.(Float64.(Zc) .- Float64.(Zd))))
        dpd = max(maximum(abs.(Float64.(Lp) .- Float64.(Ld))), maximum(abs.(Float64.(Zp) .- Float64.(Zd))))
    end
    ok = okc && neg && dcp <= 1e-4
    say("G1 ", label, " (H ", cfg.Hc, " L ", cfg.Lc, ", final ACT step ", kf, ", ", size(tok8, 2), " inputs): TrmC0 vs TrmPort max |diff| (logits, z_H) ",
        @sprintf("%.2e", dcp), " (<= 1e-4); TrmC0 vs TrmDet ", @sprintf("%.2e", dcd), ", TrmPort vs TrmDet ", @sprintf("%.2e", dpd),
        "; TrmDet (run_det.jl) vs rust/trm-det bit-identical: ", okc, " [", strip(split(cmptxt, "\n")[end-1 >= 1 ? end - 1 : 1]), "]",
        "   neg m4 (+1 ulp) caught: ", neg, " -> ", ok)
    row("g1", label, cfg.Hc, cfg.Lc, sha(bun), okj ? sha(jl) : "", okr ? sha(rs) : "", okc, neg, ok)
    return Dict("pass" => ok, "trmc0_vs_trmport" => dcp, "trmc0_vs_trmdet" => dcd, "trmport_vs_trmdet" => dpd, "det_rust_identical" => okc, "neg_caught" => neg)
end

# ---------------- mode t1: two trainings again in a one-thread process, against the weights of out/ (thread-count independence) ----------------
function t1main()
    Threads.nthreads() == 1 || error("t1: run with -t 1")
    picks = [("obs-ay", "stat", "TRM", 1), ("obs-full", "stat", "TRM-1x1", 1)]
    ref = Dict{String,String}()
    for l in eachline(joinpath(HERE, "out", "results.tsv"))
        x = split(l, "\t"); x[1] == "weights" && (ref[join(x[2:5], " ")] = x[6])
    end
    sts = Dict(u => obs_stream(u, "stat") for u in TRAIN)   # (STREAMS of the main part is defined below this mode)
    lines = String[]; ok = true
    for (track, f, m, gi) in picks
        pool = catsets([exset(sts[u], recept_of(track)) for u in TRAIN])
        t = @elapsed p, _ = train_model(pool, m, gi)
        h = shab(TrmC0.param_bytes(p)); r = get(ref, "$track $f $m $gi", "")
        ok &= h == r
        push!(lines, "t1 $track $f $m grid $gi: one-thread process ($(round(Int, t)) s) weights $h, out/ (8 threads) $r: $(h == r ? "identical" : "DIFFERENT")")
        println(lines[end])
    end
    push!(lines, "t1 (one thread = eight threads for the trainings rerun): $ok")
    write(joinpath(HERE, "out", "t1.out"), join(lines, "\n") * "\n")
    return ok ? 0 : 1
end
OUTNAME == "t1" && exit(t1main())

# =====================================================================================================================
# main
# =====================================================================================================================
const T_START = time()
# ---------------- G5: the seed sets ----------------
let sets = Dict("dev" => DEV, "train" => TRAIN, "val" => VAL, "cal" => CAL, "eval" => EVAL, "ood" => OOD)
    allu = reduce(vcat, collect(values(sets)))
    disj = length(unique(allu)) == length(allu)
    outside = all(u -> !(1 <= u <= 1045) && !(52000 <= u <= 52999), allu) && NEXT > maximum(allu)
    GATES["G5_seeds"] = disj && outside
    say("G5 dev/train/val/cal/eval/ood pairwise disjoint ", disj, ", outside 1..1045 and 52xxx, next unused 1110 ", outside)
    gate("G5 (seeds)", disj && outside)
end

# ---------------- the streams ----------------
const STREAMS = Dict{Tuple{Symbol,String,Int},Stream}()
let jobs = vcat([(:obs, f, u) for f in FAMS for u in vcat(DEV, TRAIN, VAL, CAL, EVAL)], [(:obs, "ood", u) for u in OOD])
    t = @elapsed rs = tmapv(j -> obs_stream(j[3], j[2]), jobs)
    for (j, r) in zip(jobs, rs); STREAMS[j] = r; end
    for f in FAMS, u in vcat(DEV, TRAIN, VAL, CAL, EVAL); STREAMS[(:exo, f, u)] = exo_stream(u, f); end
    say("streams: ", length(jobs), " body runs in ", @sprintf("%.0f", t), " s")
end
let ob = [st for ((k, f, u), st) in STREAMS if k == :obs]
    nupd = sum(st.nupd for st in ob); mx = maximum(st.maxacts for st in ob); bad = sum(st.badacts for st in ob)
    g2bad = sum(st.g2bad for st in ob); nex = sum(st.nex for st in ob); nm = all(st.names_ok for st in ob)
    deaths = Dict(f => count(st -> st.fam == f && st.death !== nothing, ob) for f in ("stat", "rev", "ood"))
    ok = mx <= 1 && bad == 0 && g2bad == 0 && nm
    say("G0 acts: ", length(ob), " obs runs, update steps from T0 ", nupd, ", max acts per step ", mx, ", steps with more than one act or an act outside {1, 2}: ",
        bad, "; examples ", nex, ", record mismatches with the drawer ", g2bad, "; units 1..8 are r1..r8 (8 receptors, no rb) ", nm,
        "; deaths stat ", deaths["stat"], " rev ", deaths["rev"], " ood ", deaths["ood"], " -> ", ok)
    GATES["G0"] = Dict("pass" => ok && G0A && G0B, "update_steps" => nupd, "max_acts" => mx, "bad_acts" => bad, "record_mismatch" => g2bad,
                       "rust_binary_frozen" => G0BIN)
    gate("G0 (acts)", ok)
end
# the example sets of each track, family, seed; the training pools
for track in TRACKS, f in vcat(collect(FAMS), "ood")
    (f == "ood" && track != "obs-full") && continue
    for u in (f == "ood" ? OOD : vcat(DEV, TRAIN, VAL, CAL, EVAL))
        SETS[(track, f, u)] = exset(STREAMS[(kind_of(track), f, u)], recept_of(track))
    end
end
for track in TRACKS, f in FAMS; POOLS[(track, f)] = catsets([SETS[(track, f, u)] for u in TRAIN]); end
for track in TRACKS; POOLS[("dev-" * track, "stat")] = catsets([SETS[(track, "stat", u)] for u in DEV]); end
for track in TRACKS, f in FAMS
    pl = POOLS[(track, f)]
    say("pool ", track, " ", f, ": ", size(pl.tok, 2), " examples (act 1 ", count(==(1), pl.act), ", act 2 ", count(==(2), pl.act), "), answered ",
        count(pl.Y), ", distinct inputs ", length(unique(eachcol(pl.tok))))
end
# ---------------- G5: s = 0 all PAD, s = 1 only the last frame from s = 0; receptor slots PAD outside obs-full ----------------
let ok = true, n = 0
    for ((k, f, u), st) in STREAMS, track in TRACKS
        kind_of(track) == k || continue
        rc = recept_of(track)
        t0 = enc(st, 0, rc); t1 = enc(st, 1, rc)
        fr = UInt8[[rc ? (st.r[m, 1] ? 0x02 : 0x01) : 0x00 for m in 1:8]; 0x00; st.act[1] == 0 ? 0x03 : st.act[1] == 1 ? 0x04 : 0x05;
                   st.act[1] == 0 ? 0x06 : st.Y[1] ? 0x08 : 0x07]
        ok &= all(==(0x00), t0[2:45]) && t0[1] == 0x00 && t0[46:47] == [0x09, 0x0a] && all(==(0x00), t1[2:34]) && t1[35:45] == fr
        n += 1
    end
    pad = all(all(==(0x00), es.tok[[1 + (f - 1) * 11 + q for f in 1:W4 for q in 1:9], :]) for ((tr, f, u), es) in SETS if tr != "obs-full")
    rb = all(all(==(0x00), es.tok[[1 + (f - 1) * 11 + 9 for f in 1:W4], :]) for ((tr, f, u), es) in SETS)
    GATES["G5"] = Dict("pass" => ok && pad && rb && GATES["G5_seeds"], "streams_tracks" => n)
    say("G5 s = 0: positions 1..44 all PAD, s = 1: positions 1..33 PAD and 34..44 = the record of s = 0, over ", n, " stream-tracks: ", ok,
        "; receptor slots PAD in obs-ay and exo ", pad, "; the rb slot PAD everywhere ", rb)
    gate("G5", ok && pad && rb)
end

# ---------------- G4, G2 ----------------
gate("G4", gate_g4())
gate("G2(c)", gate_g2c())
gate("G2(a)", gate_g2a(SETS[("obs-full", "stat", DEV[1])]))
gate("G2(b)", gate_g2b())
gate("G2(d)", gate_g2d())
GATES["G2"] = Dict("pass" => GATES["G2a"]["pass"] && GATES["G2b"]["pass"] && GATES["G2c"]["pass"] && GATES["G2d"]["pass"])
# ---------------- G-TIME ----------------
gate("G-TIME", gate_gtime())
# ---------------- G3 ----------------
gate("G3", gate_g3())
# ---------------- G1 before the training (the initial weights; obs-full stat dev inputs) ----------------
const TOK8_DEV = SETS[("obs-full", "stat", DEV[1])].tok[:, 1:8]
let p0 = TrmC0.init_params(Mulberry(INITSEED))
    a = gate_g1("init_TRM", p0, CFG_TRM, TOK8_DEV); b = gate_g1("init_TRM-1x1", p0, CFG_1X1, TOK8_DEV)
    GATES["G1_init"] = Dict("TRM" => a, "TRM-1x1" => b, "pass" => a["pass"] && b["pass"])
    gate("G1 (initial weights)", a["pass"] && b["pass"])
end
say("gates before the training passed (", @sprintf("%.0f", time() - T_START), " s)")
write_log()

# ---------------- training: 48 jobs ----------------
const JOBS = sort([(tr, f, m, gi) for tr in TRACKS for f in FAMS for m in MODELS for gi in 1:4]; by = j -> (j[3] == "TRM" ? 0 : 1, j))
const TT0 = time()
const TRES = tmapv(train_job, JOBS)
const TT = time() - TT0
say("training: ", length(JOBS), " jobs in ", @sprintf("%.0f", TT), " s (TRM train/val s per job: ",
    join([@sprintf("%.0f/%.0f", r.ttrain, r.tval) for r in TRES if r.job[3] == "TRM"], " "), ")")
const SEL = Dict{Tuple{String,String,String},Int}()
const VALSC = Dict{Any,Any}()
for r in TRES
    track, f, m, gi = r.job
    ok = [v for v in r.val if v.s.n[1] >= MINOBS && v.s.n[2] >= MINOBS]
    mv = isempty(ok) ? NaN : sum(v.s.sc for v in ok) / length(ok)
    VALSC[r.job] = (mean = mv, n = length(ok))
    lr, wd = GRID[gi]
    row("val", track, f, m, gi, lr, wd, mv, length(ok), join([fmt(v.s.sc) for v in r.val], ";"))
    row("weights", track, f, m, gi, shab(TrmC0.param_bytes(r.p)))
    tr = r.trace
    say("train ", track, " ", f, " ", m, " grid ", gi, " (lr ", lr, ", wd ", wd, "): lm loss by 100 updates ",
        join([@sprintf("%.4f", sum(tr[i:min(i + 99, end)]) / length(i:min(i + 99, length(tr)))) for i in 1:100:length(tr)], " "), "; val mean ", @sprintf("%.5f", mv), " over ", length(ok), " seeds")
end
for track in TRACKS, f in FAMS, m in MODELS
    cands = [(VALSC[(track, f, m, gi)].mean, gi) for gi in 1:4]
    best = minimum(c -> (isnan(c[1]) ? Inf : c[1], c[2]), cands)[2]
    SEL[(track, f, m)] = best
    r = only(filter(x -> x.job == (track, f, m, best), TRES))
    SELP[(track, f, m)] = r.p
    wf = joinpath(OUT, "weights", "$(track)_$(f)_$(m).bin"); write(wf, TrmC0.param_bytes(r.p))
    row("selected", track, f, m, best, GRID[best][1], GRID[best][2], VALSC[(track, f, m, best)].mean, sha(wf))
    say("selected ", track, " ", f, " ", m, ": grid ", best, " (val ", join([@sprintf("%.5f", VALSC[(track, f, m, gi)].mean) for gi in 1:4], " "), ")")
end
write_log()

# ---------------- predictions of the selected models ----------------
const UNITS = Any[]
for track in TRACKS, f in FAMS, m in MODELS, u in vcat(EVAL, CAL)
    push!(UNITS, ((track, f, m), m, cfg_of(m), track, f, u, m == "TRM"))
end
for u in OOD; push!(UNITS, (("obs-full", "rev", "TRM"), "TRM", CFG_TRM, "obs-full", "ood", u, false)); end
for track in TRACKS, f in FAMS, u in EVAL; push!(UNITS, ((track, f, "TRM"), "TRM-inf1x1", CFG_1X1, track, f, u, false)); end
sort!(UNITS; by = x -> (x[3] == CFG_TRM ? 0 : 1, x[4] == "obs-full" ? 0 : 1, x[4], x[5], x[2], x[6]))
const PT0 = time()
const PRES = tmapv(pred_job, UNITS)
const PT_ = time() - PT0
say("predictions: ", length(UNITS), " units in ", @sprintf("%.0f", PT_), " s")
const PRED = Dict{Any,Any}()
for r in PRES; u = r.unit; PRED[(u[2], u[4], u[5], u[6])] = r.pr; end   # (model name, track, fam, seed)

# ---------------- scores and comparisons ----------------
const SUMMARY = Dict{String,Any}()
const CMP = Dict{String,Any}()
const PRDS = ("RATE", "B1", "TAB4", "TAB_R1", "TRM", "TRM_raw", "TRM-1x1", "TRM-inf1x1")
for track in TRACKS, f in FAMS
    ctrl = train_ctrl([STREAMS[(kind_of(track), f, u)] for u in TRAIN])
    say("controls ", track, " ", f, ": RATE ", join([@sprintf("%.6f", x) for x in ctrl.rate], " "), ", TAB4 keys seen ", count(>(0), ctrl.tn), "/1250",
        track == "exo" ? "" : ", TAB_R1 keys seen $(count(>(0), ctrl.rn))/130")
    scs = Dict{String,Dict{Int,Float64}}(k => Dict{Int,Float64}() for k in PRDS)
    excl = Int[]
    for u in EVAL
        st = STREAMS[(kind_of(track), f, u)]; es = SETS[(track, f, u)]
        cp = ctrl_preds(st, ctrl)
        ps = Dict{String,Vector{Float64}}("RATE" => cp["RATE"], "B1" => cp["B1"], "TAB4" => cp["TAB4"],
                                          "TRM" => clip.(PRED[("TRM", track, f, u)].p), "TRM-1x1" => clip.(PRED[("TRM-1x1", track, f, u)].p),
                                          "TRM-inf1x1" => clip.(PRED[("TRM-inf1x1", track, f, u)].p))
        track != "exo" && (ps["TAB_R1"] = cp["TAB_R1"])
        n = score(ps["TRM"], es.act, es.Y).n
        ex = n[1] < MINOBS || n[2] < MINOBS
        ex && push!(excl, u)
        for (k, p) in ps
            s = score(p, es.act, es.Y); scs[k][u] = s.sc
            row("seed_score", track, f, u, k, s.sc, s.n[1], s.n[2], ex)
        end
        s = score(PRED[("TRM", track, f, u)].p, es.act, es.Y; raw = true); scs["TRM_raw"][u] = s.sc
        row("seed_score", track, f, u, "TRM_raw", s.sc, s.n[1], s.n[2], ex)
    end
    keep = [u for u in EVAL if !(u in excl)]
    base = track == "exo" ? ["RATE", "B1", "TAB4", "TRM-1x1"] : ["RATE", "B1", "TAB4", "TAB_R1", "TRM-1x1"]
    for b in vcat(base, ["TRM-inf1x1"])
        d = [scs[b][u] - scs["TRM"][u] for u in keep]
        c = compare(d); CMP["$track $f TRM>$b"] = c
        row("compare", track, f, "TRM", b, c["n"], c["wins"], c["losses"], c["ties"], c["p_sign"], get(c, "mean", NaN), get(c, "median", NaN),
            get(c, "ci95", [NaN, NaN])[1], get(c, "ci95", [NaN, NaN])[2], get(c, "min", NaN), get(c, "max", NaN), c["detectable"], c["pass"])
        say(@sprintf("%-8s %-4s TRM vs %-10s n %2d  wins %2d losses %2d ties %d  p %.3g  mean %+.5f [%+.5f, %+.5f]  median %+.5f  range [%+.5f, %+.5f]  %s",
                     track, f, b, c["n"], c["wins"], c["losses"], c["ties"], c["p_sign"], get(c, "mean", NaN), get(c, "ci95", [NaN, NaN])...,
                     get(c, "median", NaN), get(c, "min", NaN), get(c, "max", NaN), c["pass"] ? "PASS" : "not passed"))
    end
    means = Dict(k => (v = [scs[k][u] for u in keep]; isempty(v) ? NaN : sum(v) / length(v)) for k in PRDS if !isempty(scs[k]))
    say("   mean scores over ", length(keep), " seeds (excluded ", isempty(excl) ? "none" : join(excl, " "), "): ",
        join(["$k $(@sprintf("%.5f", means[k]))" for k in PRDS if haskey(means, k)], ", "))
    SUMMARY["scores $track $f"] = Dict("excluded" => excl, "means" => means)
end
const C0PASS = all(CMP["obs-full $f TRM>$b"]["pass"] for f in FAMS for b in ("RATE", "B1", "TAB4", "TAB_R1", "TRM-1x1"))
say("C0 (obs-full, stat and rev, TRM over RATE, B1, TAB4, TAB_R1, TRM-1x1, all significant): ", C0PASS ? "PASS (C1 may proceed)" : "NOT PASSED (C1 does not proceed)")
for f in FAMS
    CMP["obs-full $f TRM>TRM-1x1"]["pass"] || say("   obs-full ", f, ": the advantage of the configuration (H/L recursion and multi-step ACT together) over TRM-1x1 not confirmed")
    CMP["obs-full $f TRM>TAB_R1"]["pass"] || say("   obs-full ", f, ": an advantage over the one-step receptor table TAB_R1 not confirmed")
end
row("c0", "obs-full", C0PASS)

# ---------------- ê: p_cal (PAV on cal), ê_cal (e_head refit on cal), b_min ----------------
function ecal_fit(Z::Matrix{Float32}, err::Vector{Bool})
    p = TrmC0.Params{Float32}(); g = TrmC0.Params{Float32}(); o = TrmC0.Opt(p); r = Mulberry(ECALSEED); n = size(Z, 2)
    for t in 1:ECAL_STEPS
        TrmC0.zero_params!(g)
        for _ in 1:BATCH
            i = 1 + floor(Int, n * r())
            e = TrmC0.sigm(Float64(TrmC0.dotcol(p.ew, 1, Z, i) + p.eb[1]))
            ge = Float32((e - (err[i] ? 1.0 : 0.0)) / BATCH)
            for j in 1:H; g.ew[1, j] += ge * Z[j, i]; end
            g.eb[1] += ge
        end
        TrmC0.adam_step!(p, g, o, ECAL_LR, ECAL_WD)
    end
    return p
end
ecal_pred(p, Z) = [TrmC0.sigm(Float64(TrmC0.dotcol(p.ew, 1, Z, i) + p.eb[1])) for i in 1:size(Z, 2)]
const EHAT = Dict{String,Any}()
for track in TRACKS, f in FAMS
    cx = Float64[]; cz = Bool[]; cZ = Matrix{Float32}[]
    for u in CAL
        pr = PRED[("TRM", track, f, u)]; es = SETS[(track, f, u)]
        append!(cx, [min(clip(p), 1 - clip(p)) for p in pr.p]); append!(cz, [(p >= 0.5) != y for (p, y) in zip(pr.p, es.Y)]); push!(cZ, pr.z)
    end
    fit = pav_fit(cx, cz); pe = ecal_fit(reduce(hcat, cZ), cz)
    recs = Any[]
    for u in EVAL
        pr = PRED[("TRM", track, f, u)]; es = SETS[(track, f, u)]
        err = [(p >= 0.5) != y for (p, y) in zip(pr.p, es.Y)]
        x = [min(clip(p), 1 - clip(p)) for p in pr.p]
        qe = clip.(pr.e); qc = [pav_pred(fit, xi) for xi in x]; qk = clip.(ecal_pred(pe, pr.z)); qm = x
        n = length(err); ne = count(err); na = [count(i -> err[i] && es.act[i] == a, 1:n) for a in 1:2]
        Lm(q, sel) = (ix = [i for i in 1:n if sel(i)]; isempty(ix) ? NaN : sum(bce(q[i], err[i]) for i in ix) / length(ix))
        Le, Lc, Lk, Lb = Lm(qe, i -> true), Lm(qc, i -> true), Lm(qk, i -> true), Lm(qm, i -> true)
        det = ne >= MINERR && ne < n
        rr = (seed = u, n = n, ne = ne, na = na, Le = Le, Lc = Lc, Lk = Lk, Lb = Lb, O1 = 1 - Le / Lc, O1k = 1 - Lk / Lc, O1m = 1 - Le / Lb,
              Le1 = Lm(qe, i -> err[i]), Le0 = Lm(qe, i -> !err[i]), Lc1 = Lm(qc, i -> err[i]), Lc0 = Lm(qc, i -> !err[i]), det = det)
        push!(recs, rr)
        row("ehat_seed", track, f, u, n, ne, na[1], na[2], Le, Lc, Lk, Lb, rr.O1, rr.O1k, rr.O1m, rr.Le1, rr.Le0, rr.Lc1, rr.Lc0, det ? "detectable" : "undetectable")
    end
    dr = [r for r in recs if r.det]
    co = compare([r.O1 for r in dr]); ck = compare([r.O1k for r in dr]); cd = compare([r.O1k - r.O1 for r in dr]); cm = compare([r.O1m for r in dr])
    stable = co["n"] > 0 && co["p_sign"] < SIGNA && co["wins"] > co["losses"] && co["ci95"][1] > 0
    EHAT["$track $f"] = Dict("detectable_seeds" => length(dr), "undetectable" => [r.seed for r in recs if !r.det], "O1_cal" => co, "O1_cal_ecal" => ck,
                             "ecal_minus_ehat" => cd, "O1_min" => cm, "stable_positive" => stable, "pav_blocks" => length(fit[1]))
    for (nm, c) in (("O1_cal(ehat)", co), ("O1_cal(ehat_cal)", ck), ("O1_cal(ehat_cal)-O1_cal(ehat)", cd), ("O1_min(ehat)", cm))
        row("ehat_summary", track, f, nm, c["n"], c["wins"], c["losses"], c["p_sign"], get(c, "mean", NaN), get(c, "median", NaN),
            get(c, "ci95", [NaN, NaN])[1], get(c, "ci95", [NaN, NaN])[2])
    end
    say(@sprintf("ê %-8s %-4s: detectable seeds %2d (undetectable %s); PAV blocks %d; O1^cal mean %+.4f [%+.4f, %+.4f] wins %d losses %d p %.3g (stable > 0: %s); ê_cal O1^cal mean %+.4f; ê_cal - ê %+.4f [%+.4f, %+.4f]; O1^min mean %+.4f",
                 track, f, length(dr), isempty(EHAT["$track $f"]["undetectable"]) ? "none" : join(EHAT["$track $f"]["undetectable"], " "), length(fit[1]),
                 get(co, "mean", NaN), get(co, "ci95", [NaN, NaN])..., co["wins"], co["losses"], co["p_sign"], stable, get(ck, "mean", NaN),
                 get(cd, "mean", NaN), get(cd, "ci95", [NaN, NaN])..., get(cm, "mean", NaN)))
end

# ---------------- OOD ----------------
const OODR = let d = Float64[], excl = Int[]
    for u in OOD
        st = STREAMS[(:obs, "ood", u)]; es = SETS[("obs-full", "ood", u)]
        m = [0.5, 0.5]; b1 = Float64[]
        for s in 0:NS-1
            a = st.act[s+1]
            st.isex[s+1] && push!(b1, clip(m[a]))
            a != 0 && (m[a] += ((st.Y[s+1] ? 1.0 : 0.0) - m[a]) / KDEC)
        end
        sT = score(clip.(PRED[("TRM", "obs-full", "ood", u)].p), es.act, es.Y); sB = score(b1, es.act, es.Y)
        ex = sT.n[1] < MINOBS || sT.n[2] < MINOBS
        row("ood_seed", u, brev_ood(u), sT.sc, sB.sc, sT.n[1], sT.n[2], ex)
        ex ? push!(excl, u) : push!(d, sB.sc - sT.sc)
    end
    c = compare(d); fail = c["wins"] <= c["losses"]
    row("ood_compare", "obs-full", "rev-trained TRM", "B1", c["n"], c["wins"], c["losses"], c["ties"], c["p_sign"], get(c, "mean", NaN),
        get(c, "ci95", [NaN, NaN])[1], get(c, "ci95", [NaN, NaN])[2], fail ? "generalization_failure" : "no_failure")
    say(@sprintf("OOD (P 700, L 250; %d seeds, excluded %s): rev-trained obs-full TRM vs B1 wins %d losses %d ties %d p %.3g mean %+.5f [%+.5f, %+.5f] -> %s",
                 c["n"], isempty(excl) ? "none" : join(excl, " "), c["wins"], c["losses"], c["ties"], c["p_sign"], get(c, "mean", NaN),
                 get(c, "ci95", [NaN, NaN])..., fail ? "wins <= losses: failure to generalize out of the training distribution" : "wins > losses"))
    Dict("compare" => c, "excluded" => excl, "generalization_failure" => fail)
end

# ---------------- G1 after the training (the selected obs-full models; eval u1074 inputs) ----------------
let r = Dict{String,Any}(), ok = true
    for f in FAMS, m in MODELS
        tok8 = SETS[("obs-full", f, EVAL[1])].tok[:, 1:8]
        x = gate_g1("sel_obs-full_$(f)_$(m)", SELP[("obs-full", f, m)], cfg_of(m), tok8); r["$f $m"] = x; ok &= x["pass"]
    end
    GATES["G1_trained"] = merge(r, Dict("pass" => ok))
    GATES["G1"] = Dict("pass" => ok && GATES["G1_init"]["pass"])
    say("G1 (initial and trained weights): ", GATES["G1"]["pass"])
end

# ---------------- predictions (P-S64-1..5) ----------------
const P2 = all(CMP["exo $f TRM>$b"]["pass"] for f in FAMS for b in ("RATE", "B1", "TAB4"))
const P4HOLD = !EHAT["obs-full stat"]["stable_positive"] && !EHAT["obs-full rev"]["stable_positive"]
const P5HOLD = OODR["generalization_failure"]
const GPASS = all(GATES[k]["pass"] for k in ("G0", "G1", "G2", "G3", "G4", "G5", "G-TIME")) && G7
const PRED_OUT = Dict("P-S64-1" => "G0-G5, G7, G-TIME in this process: $(GPASS ? "pass" : "FAIL"); G6, G8 by the mode g6",
                      "P-S64-2" => P2 ? "holds" : "missed", "P-S64-3" => C0PASS ? "holds" : "missed",
                      "P-S64-4" => P4HOLD ? "holds (ê does not stably exceed p_cal on obs-full)" : "missed in its first clause (ê stably exceeds p_cal); see the size",
                      "P-S64-5" => P5HOLD ? "holds (wins <= losses)" : "missed (wins > losses)")
for k in sort(collect(keys(PRED_OUT))); say(k, ": ", PRED_OUT[k]); row("prediction", k, PRED_OUT[k]); end

# ---------------- outputs ----------------
let keys_ = [join(r[1:min(end, 6)], "\t") for r in ROWS]
    length(unique(ROWS)) == length(ROWS) || error("results.tsv: duplicate rows")
end
open(joinpath(OUT, "results.tsv"), "w") do io
    println(io, "record_type\tfields...")
    for r in ROWS; println(io, join(r, "\t")); end
end
SUMMARY["gates"] = GATES; SUMMARY["G7"] = G7
SUMMARY["selected"] = Dict(join(k, " ") => v for (k, v) in SEL)
SUMMARY["val"] = Dict(join(string.(k), " ") => v.mean for (k, v) in VALSC)
SUMMARY["compare"] = CMP; SUMMARY["C0_pass"] = C0PASS; SUMMARY["ehat"] = EHAT; SUMMARY["ood"] = OODR; SUMMARY["predictions"] = PRED_OUT
SUMMARY["weights_sha256"] = Dict(join(k, " ") => shab(TrmC0.param_bytes(v)) for (k, v) in SELP)
SUMMARY["phenomenal_claim"] = "not_certified"
open(joinpath(OUT, "summary.json"), "w") do io; JSON.print(io, SUMMARY, 1); end
say("total ", @sprintf("%.0f", time() - T_START), " s")
write_log()
