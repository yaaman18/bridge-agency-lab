# S57 (A1) drawing with weights made from the circuit's certainty (discussion/specs/S57-draw-conf.md r2; predictions-draw-conf.md r2;
# freeze-draw-conf.txt freeze 1). Built on S55 (draw_grid.jl, not changed): the same source-copy construction of step! and
# body_org_run, the same drawer (ordered (patch, unit index), rejection sampling of integer weights, one draw per step).
# Arms DET (the rank), UNI (uniform), CONF (w_m = 1 + conf[m], conf = the step!'s own conf of that step). Raising to T0 = 800 is DET.
# The hook hands the drawer conf, habit, total and y of the step; the drawer records them, the weights and whether the act
# was answered (y[p] > 0 at the step of the act, p = the chosen patch).
# Bits: draw-conf-bits/u<u>.bits for u in 686:725 and u<u>-biased.bits for 686:689, S55's rule (Mulberry(1000003 u + 55),
# biased: Mulberry(1000003 u + 56) < 0.2). D4b uses S55's draw-bits/unit-d4b.bits (read only).
# Usage (from experiments/):
#   julia --project=.. -t 8 draw_conf_grid.jl gates    F, D1-D7, D4b on the pilot windows 686-689 (writes the bit files if absent)
#   julia --project=.. draw_conf_grid.jl freeze         writes freeze-draw-conf-code.txt (gates must all be true)
#   julia --project=.. -t 8 draw_conf_grid.jl pilot    pilot windows 686-689, §3 admission (appends the pilot block to the code freeze)
#   julia --project=.. -t 8 draw_conf_grid.jl eval     evaluation windows 690-725 (admitted laws only)
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON, SHA
include(joinpath(@__DIR__, "synth_world.jl"))
include(joinpath(@__DIR__, "check_draw_conf.jl"))
using .DrawConfJudge
const CJ = DrawConfJudge
const DJ = CJ.DJ

const LAB = normpath(joinpath(@__DIR__, ".."))
const EXP = joinpath(LAB, "experiments")
const BITDIR = joinpath(EXP, "draw-conf-bits")
const OUTDIR = joinpath(EXP, "draw-conf-out")
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode gates | freeze | pilot | eval")
const T0 = 800; const STEPS = 10000
const COUNTAT = [T0 + x for x in (500, 2000, 9200)]
const STATEAT = T0 + 2000
const BASE = (U = 0.02, MCOST = 0.004, STEPS = STEPS, FEED = true, KC = 0.002, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
const LAWS = ("L2", "L2+SF")
law_opts(law) = law == "L2" ? BASE : merge(BASE, (SEDFADE = true,))
const WP = (P = 1000, sigma = 1, L = 300, M = 2.5)
world_opts(u) = (SCHED = synth_sched(u, WP.P, WP.sigma, WP.L, WP.M),)
const ARMS = ("DET", "UNI", "CONF")
const PILOT = 686:689; const EVALS = 690:725
const NBITS = DJ.NBITS

# ---------------- bit files (S55's rule) ----------------
lsb(x::Float64) = Int(UInt32(x * 4294967296.0) & 0x00000001)
function gen_bits(u)
    r = Mulberry(1_000_003 * u + 55)
    return UInt8[lsb(r()) for _ in 1:NBITS]
end
function gen_biased(u)
    b = gen_bits(u); r = Mulberry(1_000_003 * u + 56)
    for i in 1:NBITS
        x = r()
        (b[i] == 0x00 && x < 0.2) && (b[i] = 0x01)
    end
    return b
end
bitfile(u; biased = false) = joinpath(BITDIR, biased ? "u$(u)-biased.bits" : "u$(u).bits")
const BITU = vcat(collect(PILOT), collect(EVALS))
bitnames() = vcat(["u$(u).bits" for u in BITU], ["u$(u)-biased.bits" for u in PILOT])
sha(f) = bytes2hex(open(sha256, f))
function make_bits()
    isdir(BITDIR) && return false
    mkpath(BITDIR)
    for u in BITU; write(bitfile(u), gen_bits(u) .+ UInt8('0')); end
    for u in PILOT; write(bitfile(u; biased = true), gen_biased(u) .+ UInt8('0')); end
    write(joinpath(BITDIR, "SHA256SUMS"), join([sha(joinpath(BITDIR, n)) * "  " * n for n in bitnames()], "\n") * "\n")
    return true
end
function read_sums(f)
    ref = Dict{String,String}()
    for l in eachline(f)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    return ref
end
function bits_ok(; extra = nothing)
    ref = read_sums(joinpath(BITDIR, "SHA256SUMS"))
    okS = all(n -> haskey(ref, n) && sha(joinpath(BITDIR, n)) == ref[n], bitnames())
    okR = all(u -> DJ.load_bits(bitfile(u)) == gen_bits(u), BITU) && all(u -> DJ.load_bits(bitfile(u; biased = true)) == gen_biased(u), PILOT)
    okX = extra === nothing || all(n -> get(extra, "draw-conf-bits/" * n, "") == ref[n], bitnames())
    return okS && okR && okX
end
const BITS = Dict{Int,Vector{UInt8}}()
const BBITS = Dict{Int,Vector{UInt8}}()
const NUNIT = 1_500_000
const UNITFILE = joinpath(EXP, "draw-bits", "unit-d4b.bits"); const UNITSUMS = joinpath(EXP, "draw-bits", "SHA256SUMS-d4b")
gen_unit() = (r = Mulberry(1_000_003 + 57); UInt8[lsb(r()) for _ in 1:NUNIT])
function load_unit()
    v = read(UNITFILE); length(v) == NUNIT && all(c -> c == UInt8('0') || c == UInt8('1'), v) || error("unit bit file")
    return v .- UInt8('0')
end
unit_ok() = get(read_sums(UNITSUMS), "unit-d4b.bits", "") == sha(UNITFILE) && load_unit() == gen_unit()
const NOTES = "S57 on S55's construction. The body has no m0 (S55 spec r3 §8): cs = {m1, m2}. CONF weights 1 + conf[m] (conf = step!'s own " *
    "local of that step); W need not be a power of 2, so rejections occur in a life. D4b reuses S55's unit file; its W = 10 case is CONF " *
    "with conf (4, 2, 1) on (m1, m2, m0) -> weights 5:3:2. PB1 groups = (cs, weights / gcd)."

# ---------------- step_draw_conf!: core/circuit.jl's step! with the draw ----------------
function rep1(f, anchor, new)
    n = length(findall(anchor, f)); n == 1 || error("anchor occurs $n times: $anchor")
    return replace(f, anchor => new)
end
const CIRCUIT_SRC = read(joinpath(LAB, "core", "circuit.jl"), String)
function draw_step_source(src)
    i = findfirst("function step!(st::CState, b::Circuit, y;", src); i === nothing && error("anchor: function step!")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    f = src[i[1]:j[end]]
    f = rep1(f, "function step!(st::CState, b::Circuit, y;", "function step_draw_conf!(st::CState, b::Circuit, y;")
    f = rep1(f, "rest_off = false, body_flag = nothing)", "rest_off = false, body_flag = nothing, draw = nothing)")
    a = "        for m in cand; m != win && (nw[m] = false); end\n"
    f = rep1(f, a, """
        if draw !== nothing   # S57 (draw_conf_grid.jl): one draw from the choosing set; the drawer gets this step's conf, habit, total and y
            dcs = cand
            if idle_first; didl = [m for m in cand if now - st.lastM[m] > FORGET]; isempty(didl) || (dcs = didl); end
            win = draw(cand, dcs, win, key, b, conf, habit, total, y)
        end
""" * a)
    return f
end
const STEP_DRAW_SRC = draw_step_source(CIRCUIT_SRC)
Core.eval(LabCore, Meta.parse(STEP_DRAW_SRC))
const step_draw_conf! = LabCore.step_draw_conf!

# ---------------- body_org_run_draw_conf: core/body_org.jl's body_org_run calling step_draw_conf! ----------------
const RN = (:fixed, :snap, :silset, :keptS, :billS, :lsH, :trace, :countAt, :rYield, :rN, :rCap, :rActs, :rAns, :rMoved, :rSpent, :rUpkeep,
            :w, :pool, :perm, :b, :circuit, :noise, :lost, :blocked, :seen, :acts, :logv, :alive, :death, :maxErr, :nActs, :nAns,
            :moved, :spent, :sumCount, :sumLate, :nform, :kept, :upkeep, :win, :drawer, :stateAt)
const CN = (:U, :MCOST, :STEPS, :ctr, :contrast, :idle_first, :core_gate, :seen_both, :sed_fade, :READCUR, :REVR, :KC, :PER, :RAISE,
            :DROPR, :ST0, :REVRK, :FIXAT, :SILAT, :REPLAYX, :KCBILL, :KEPTS, :COUNTAT, :REPORT, :SNAPAT, :LSTRACE, :TRACE, :T0,
            :ON_STEP, :SEEN, :cond, :seed, :o, :replay_acts, :DRAW, :SAVEAT, :RESUME, :STATEAT, :PRESTEP, :DRAWFROM, :saved, :R, :t)
const BODY_ORG_SRC = read(joinpath(LAB, "core", "body_org.jl"), String)
function draw_run_source(src)
    i = findfirst("function body_org_run(cond::String", src); i === nothing && error("anchor: function")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    f = src[i[1]:j[end]]
    f = rep1(f, "function body_org_run(cond::String", "function body_org_run_draw_conf(cond::String")
    a = "TRACE = _opt(o, :TRACE, false) == true\n"
    f = rep1(f, a, a * """
    DRAW = _opt(o, :DRAW); SAVEAT = _opt(o, :SAVEAT); RESUME = _opt(o, :RESUME); STATEAT = _opt(o, :STATEAT); PRESTEP = _opt(o, :PRESTEP)
    DRAWFROM = _opt(o, :DRAWFROM, 800); drawer = DRAW; saved = nothing; stateAt = nothing   # S55/S57 (draw_conf_grid.jl)
""")
    restore = join(["$n = R[:$n]" for n in RN], "; ")
    f = rep1(f, "    for t in 0:STEPS-1\n", """
    if RESUME !== nothing   # S55: continue a saved run state (the individual and the bit position)
        R = deepcopy(RESUME)
        $restore
    end
    for t in (RESUME === nothing ? 0 : RESUME[:t]):STEPS-1
        if SAVEAT !== nothing && t == SAVEAT
            saveL = Base.@locals()
            unk = [k for (k, v) in saveL if !(k in $(repr(RN))) && !(k in $(repr(CN))) && !(v isa Function)]
            isempty(unk) || error("run state: unlisted locals \$unk")
            saved = deepcopy(Dict{Symbol,Any}(k => saveL[k] for k in $(repr(RN)) if haskey(saveL, k)))
            length(saved) == $(length(RN)) || error("run state: missing locals")
            saved[:t] = t
        end
""")
    a = "        if alive && isempty(body); alive = false; death = t; end\n"
    f = rep1(f, a, a * """
        if STATEAT !== nothing && stateAt === nothing && t <= STATEAT && (t == STATEAT || !alive)
            stateAt = deepcopy((death = death, w = w, pool = pool, circuit = circuit, noise = noise))
        end
""")
    f = rep1(f, "            out = step!(circuit, b, [yin[1], yin[2], 0.0]; ", """
            PRESTEP === nothing || PRESTEP((t = t, circuit = circuit, b = b, noise = noise, yin = [yin[1], yin[2], 0.0], sil = silset, drawer = drawer))
            drawer === nothing || (drawer.t = t)
            out = step_draw_conf!(circuit, b, [yin[1], yin[2], 0.0]; """)
    f = rep1(f, "sil = silset)\n", "sil = silset, draw = (drawer !== nothing && t >= DRAWFROM) ? drawer : nothing)\n")
    f = rep1(f, "\"log\" => logv, \"acts\" => acts, ", "\"log\" => logv, \"acts\" => acts, \"drawer\" => drawer, \"saved\" => saved, \"stateAt\" => stateAt, ")
    return f
end
const RUN_DRAW_SRC = draw_run_source(BODY_ORG_SRC)
Core.eval(LabCore, Meta.parse(RUN_DRAW_SRC))
const body_org_run_draw_conf = LabCore.body_org_run_draw_conf

# ---------------- the drawer ----------------
mutable struct Drawer
    arm::String
    bits::Vector{UInt8}
    pos::Int          # bits used so far (0-based position of the next bit)
    t::Int            # the body step (set by the run before each circuit step)
    hw::Bool          # D6 negative control only: CONF weights from habit instead of conf
    lt::Vector{Int}; lcand::Vector{Vector{Int}}; lcs::Vector{Vector{Int}}; lkeys::Vector{Vector{Int}}
    lconf::Vector{Vector{Int}}; lhab::Vector{Vector{Int}}; ltot::Vector{Vector{Int}}; lw::Vector{Vector{Int}}
    ldet::Vector{Int}; lch::Vector{Int}; lpos::Vector{Int}; lnb::Vector{Int}; lrej::Vector{Int}
    lans::Vector{Bool}; ly::Vector{Vector{Float64}}
end
Drawer(arm, bits; hw = false) = Drawer(arm, bits, 0, -1, hw, Int[], Vector{Int}[], Vector{Int}[], Vector{Int}[], Vector{Int}[], Vector{Int}[],
                                       Vector{Int}[], Vector{Int}[], Int[], Int[], Int[], Int[], Int[], Bool[], Vector{Float64}[])
# Called by step_draw_conf! when there are two or more candidates. cs ordered by (patch, unit index); with fewer than two
# in cs, or DET, no bit is used and the rank's win is kept.
function (d::Drawer)(cand, cs, win, key, b, conf, habit, total, y)
    s = sort(cs; by = m -> (b.patch[m], m))
    pats = [b.patch[m] for m in s]
    push!(d.lt, d.t); push!(d.lcand, copy(cand)); push!(d.lcs, pats); push!(d.lkeys, [key(m) for m in s]); push!(d.ldet, b.patch[win])
    push!(d.lconf, [conf[m] for m in s]); push!(d.lhab, [habit[m] for m in s]); push!(d.ltot, [total[m] for m in s])
    w = d.arm == "UNI" ? fill(1, length(s)) : d.arm == "CONF" ? [1 + (d.hw ? habit[m] : conf[m]) for m in s] : Int[]
    push!(d.lw, w)
    pos0 = d.pos; nb = 0; rej = 0; ch = win
    if length(s) >= 2 && d.arm != "DET"
        W = sum(w)
        while (1 << nb) < W
            nb += 1
        end
        r = 0
        while true
            d.pos + nb <= length(d.bits) || error("draw: the bit file is exhausted at position $(d.pos)")
            r = 0
            for i in 1:nb
                r = 2 * r + Int(d.bits[d.pos+i])
            end
            d.pos += nb
            r < W && break
            rej += 1
        end
        acc = 0; k = 0
        while true
            k += 1; acc += w[k]
            r < acc && break
        end
        ch = s[k]
    end
    pc = b.patch[ch]
    push!(d.lch, pc); push!(d.lpos, pos0); push!(d.lnb, nb); push!(d.lrej, rej)
    push!(d.lans, pc <= 2 && y[pc] > 0); push!(d.ly, [Float64(y[1]), Float64(y[2])])
    return ch
end
drawlog(d::Drawer) = Dict{String,Any}("t" => d.lt, "ncand" => length.(d.lcand), "cs" => d.lcs, "keys" => d.lkeys, "conf" => d.lconf, "hab" => d.lhab,
                                      "tot" => d.ltot, "w" => d.lw, "det" => d.ldet, "chosen" => d.lch, "pos" => d.lpos, "nb" => d.lnb, "rej" => d.lrej,
                                      "ans" => d.lans, "y" => d.ly)

function run_arm(law, arm, u; bits = nothing, extra = (;), hw = false)
    d = Drawer(arm, bits === nothing ? BITS[u] : bits; hw = hw)
    return body_org_run_draw_conf("ORG", u, merge(law_opts(law), world_opts(u), (COUNTAT = COUNTAT, REPORT = true, STATEAT = STATEAT, DRAW = d), extra))
end

# ---------------- helpers (as S55) ----------------
function deq(a, b)
    (a isa AbstractDict && b isa AbstractDict) && return Set(keys(a)) == Set(keys(b)) && all(deq(a[k], b[k]) for k in keys(a))
    typeof(a) == typeof(b) || return false
    if a isa AbstractArray
        return size(a) == size(b) && all(deq(a[i], b[i]) for i in eachindex(a))
    elseif a isa Tuple || a isa NamedTuple
        return length(a) == length(b) && all(deq(a[i], b[i]) for i in 1:length(a))
    elseif a === nothing || a isa Number || a isa AbstractString || a isa Symbol || a isa Char || a isa AbstractSet
        return isequal(a, b)
    elseif a isa Function
        return a === b
    else
        return all(deq(getfield(a, f), getfield(b, f)) for f in fieldnames(typeof(a)))
    end
end
without(r, ks...) = Dict(k => v for (k, v) in r if !(k in ks))
alive_at(r, x) = r["death"] === nothing || r["death"] > T0 + x
const GL = String[]
say(x...) = (s = string(x...); println(s); push!(GL, s); flush(stdout))
function freeze_ok()
    ref = Dict{String,String}()
    for l in eachline(joinpath(EXP, "freeze-draw-conf.txt"))
        startswith(l, "# S57 freeze 1") && empty!(ref)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    return length(ref) == 2 && all(sha(normpath(joinpath(EXP, f))) == h for (f, h) in ref), ref
end
function tmap(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads for i in eachindex(xs); out[i] = f(xs[i]); end
    return out
end
spread(v, n) = length(v) <= n ? v : v[unique(round.(Int, range(1, length(v); length = n)))]
stepkw(law) = (contrast = :bin3, idle_first = true, core_gate = true, seen_both = false, sed_fade = law == "L2+SF")
# conf, habit, total of the members of cs, recomputed from the state before the step and step!'s drove (memory on)
function parts_from(st0, b, drove, cs)
    n = length(b.names); tot = zeros(Int, n); conf = zeros(Int, n); hab = zeros(Int, n)
    for (k, (a, c, w)) in enumerate(b.edges)
        drove[k] || continue
        tot[c] += w
        if st0.q[k] >= 1; conf[c] += w; elseif st0.sg[k] >= 1; hab[c] += w; end
    end
    return [conf[m] for m in cs], [hab[m] for m in cs], [tot[m] for m in cs]
end
keys_from(st0, b, drove, cs) = ((c, h, t) = parts_from(st0, b, drove, cs); [c[i] * 1_000_000 + h[i] * 1_000 + t[i] for i in eachindex(cs)])
# the state before a step; the drawer is a fresh one at the same bit position (its records are not needed; bits shared, read only)
function capture(x)
    d = Drawer(x.drawer.arm, x.drawer.bits); d.pos = x.drawer.pos
    return (t = x.t, circuit = deepcopy(x.circuit), b = deepcopy(x.b), noise = deepcopy(x.noise), yin = copy(x.yin), sil = copy(x.sil), drawer = d)
end
drawn_ts(d::Drawer) =[d.lt[i] for i in eachindex(d.lt) if length(d.lcs[i]) >= 2 && d.lt[i] >= T0]

# ---------------- gates ----------------
function gates()
    res = Dict{String,Any}()
    say(NOTES)
    made = make_bits()
    say("bit files ", made ? "written" : "present", " in ", BITDIR)
    okF, ref = freeze_ok()
    okB = bits_ok()
    nb = copy(DJ.load_bits(bitfile(686))); nb[1000] = 0x01 - nb[1000]
    negB = nb == gen_bits(686)
    cst = [abs(DJ.chi2p(4.0, 2) - exp(-2.0)) < 1e-12, abs(DJ.chi2p(3.841458820694124, 1) - 0.05) < 1e-9,
           abs(DJ.chi2p(7.814727903251178, 3) - 0.05) < 1e-9, abs(DJ.chi2p(0.5, 1) - 0.4795001221869535) < 1e-9]
    # sign test self-test: 9 wins 0 losses -> p = 2/512; 7 wins 0 losses -> undetectable
    s1 = CJ.sign_test(fill(1, 9), fill(0, 9)); s2 = CJ.sign_test(vcat(fill(1, 7), fill(0, 5)), fill(0, 12))
    s3 = CJ.sign_test(vcat(fill(0, 8), fill(1, 2)), vcat(fill(1, 8), fill(1, 2)))
    sst = [abs(s1["p"] - 2 / 512) < 1e-15 && s1["verdict"] == "larger", s2["verdict"] == "undetectable" && s2["ties"] == 5,
           s3["verdict"] == "smaller" && s3["ties"] == 2]
    say("F: spec and predictions equal freeze 1 of freeze-draw-conf.txt: ", okF, "  ", ref)
    say("F: bit files equal the rule and SHA256SUMS: ", okB, "   neg: a flipped bit equals the rule (must be false): ", negB,
        "   chi-square p self-test: ", cst, "   sign test self-test: ", sst)
    okU = unit_ok()
    say("F: D4b unit bit file (S55's) equals its rule and SHA256SUMS-d4b: ", okU)
    res["F"] = okF && okB && !negB && all(cst) && all(sst) && okU
    TR = (TRACE = true,)
    # D1: DET through the copy = body_org_run at every step; neg: UNI and CONF differ
    c1 = [(law, u) for law in LAWS for u in PILOT]
    D1 = tmap(c1) do (law, u)
        o = merge(law_opts(law), world_opts(u), (COUNTAT = COUNTAT, REPORT = true), TR)
        a = body_org_run("ORG", u, o)
        dd = body_org_run_draw_conf("ORG", u, merge(o, (DRAW = Drawer("DET", BITS[u]),)))
        du = body_org_run_draw_conf("ORG", u, merge(o, (DRAW = Drawer("UNI", BITS[u]),)))
        dc = body_org_run_draw_conf("ORG", u, merge(o, (DRAW = Drawer("CONF", BITS[u]),)))
        ks = collect(keys(a))
        (key = "$law u$u", eq = deq(a, Dict(k => dd[k] for k in ks)), negU = deq(a, Dict(k => du[k] for k in ks)), negC = deq(a, Dict(k => dc[k] for k in ks)),
         nDraw = length(drawn_ts(dd["drawer"])))
    end
    for x in D1; say("D1 ", x.key, ": DET copy = body_org_run at every step: ", x.eq, " (drawing steps ", x.nDraw, ")   neg: UNI equal (must be false): ", x.negU, ", CONF equal (must be false): ", x.negC); end
    res["D1"] = all(x -> x.eq && !x.negU && !x.negC, D1)
    say("D1: ", res["D1"])
    # D2 (a): run state at T0 of UNI and CONF = DET; neg: drawing from step 0
    c2 = [(law, arm, u) for law in LAWS for arm in ("UNI", "CONF") for u in PILOT]
    D2a = tmap(c2) do (law, arm, u)
        sd = run_arm(law, "DET", u; extra = (SAVEAT = T0, TRACE = true))["saved"]
        sa = run_arm(law, arm, u; extra = (SAVEAT = T0, TRACE = true))["saved"]
        sx = run_arm(law, arm, u; extra = (SAVEAT = T0, TRACE = true, DRAWFROM = 0))["saved"]
        (key = "$law $arm u$u", eq = deq(without(sd, :drawer), without(sa, :drawer)), neg = deq(without(sd, :drawer), without(sx, :drawer)), nb = sa[:drawer].pos)
    end
    for x in D2a; say("D2a ", x.key, ": run state at T0 = DET (bits used before T0: ", x.nb, "): ", x.eq, "   neg: drawing from step 0 equal (must be false): ", x.neg); end
    # D2 (b) and D6: one-step comparison with core's step! from states taken during the UNI / CONF runs
    D2b = tmap(c2) do (law, arm, u)
        r = run_arm(law, arm, u)
        dl = r["drawer"]; dset = Set(dl.lt)
        e = r["death"] === nothing ? STEPS : r["death"]
        A = spread([t for t in T0:e-1 if !(t in dset)], 50)
        dts = drawn_ts(dl); B = spread(dts, 50)
        # D6 sample: 50 drawing steps spread over the run and 50 spread over the drawing steps where the recorded conf and habit differ
        dif = [dl.lt[i] for i in eachindex(dl.lt) if length(dl.lcs[i]) >= 2 && dl.lt[i] >= T0 && dl.lconf[i] != dl.lhab[i]]
        B6 = sort(unique(vcat(B, spread(dif, 50))))
        want = Set(vcat(A, B6)); cap = Dict{Int,Any}()
        run_arm(law, arm, u; extra = (PRESTEP = x -> (x.t in want && (cap[x.t] = capture(x))),))
        kw = stepkw(law)
        okA = Bool[]; okB = Bool[]; negA = Bool[]; full = Bool[]
        ok6 = Bool[]; n6diff = 0; neg6 = Bool[]
        for t in A
            x = cap[t]; p = deepcopy(x); q = deepcopy(x); z = deepcopy(x)
            o1 = step!(p.circuit, p.b, p.yin; noise = p.noise, sil = p.sil, kw...)
            q.drawer.t = t
            o2 = step_draw_conf!(q.circuit, q.b, q.yin; noise = q.noise, sil = q.sil, draw = q.drawer, kw...)
            push!(okA, deq(o1, o2) && deq(p.circuit, q.circuit) && deq(p.noise, q.noise) && deq(p.b, q.b) && q.drawer.pos == x.drawer.pos)
            z.yin[1] = 5.0 - z.yin[1]
            o3 = step_draw_conf!(z.circuit, z.b, z.yin; noise = z.noise, sil = z.sil, draw = z.drawer, kw...)
            push!(negA, deq(o1, o3) && deq(p.circuit, z.circuit))
        end
        for t in B6
            x = cap[t]; p = deepcopy(x); q = deepcopy(x)
            o1 = step!(p.circuit, p.b, p.yin; noise = p.noise, sil = p.sil, kw...)
            q.drawer.t = t; n0 = length(q.drawer.lt)
            o2 = step_draw_conf!(q.circuit, q.b, q.yin; noise = q.noise, sil = q.sil, draw = q.drawer, kw...)
            d = q.drawer
            ok = length(d.lt) == n0 + 1 && o1.choice !== nothing && d.lcand[end] == o1.choice.cand && deq(o1.drove, o2.drove) &&
                 d.ldet[end] == x.b.patch[o1.choice.win] && deq(o1.choice, o2.choice) && deq(p.noise, q.noise)
            cf = Int[]; hb = Int[]
            if ok
                ord = sort(o1.choice.cand; by = m -> (x.b.patch[m], m))
                dcs = [m for m in ord if x.b.patch[m] in d.lcs[end]]
                cf, hb, tt = parts_from(x.circuit, x.b, o1.drove, dcs)
                ok = d.lkeys[end] == keys_from(x.circuit, x.b, o1.drove, dcs) && d.lconf[end] == cf && d.lhab[end] == hb && d.ltot[end] == tt
            end
            t in B && push!(okB, ok)
            t in B && d.lch[end] == d.ldet[end] && push!(full, deq(o1, o2) && deq(p.circuit, q.circuit))
            if arm == "CONF"
                # D6: the drawer's weights = 1 + step!'s conf (recomputed from step!'s drove and the state before the step)
                push!(ok6, ok && d.lw[end] == [1 + c for c in cf])
                if ok && cf != hb
                    n6diff += 1
                    z = deepcopy(x); z.drawer.hw = true; z.drawer.t = t
                    step_draw_conf!(z.circuit, z.b, z.yin; noise = z.noise, sil = z.sil, draw = z.drawer, kw...)
                    push!(neg6, z.drawer.lw[end] == [1 + c for c in cf])
                end
            end
        end
        (key = "$law $arm u$u", nA = length(A), nB = length(B), okA = all(okA), okB = all(okB), negA = all(negA), full = all(full), nFull = length(full),
         n6 = length(ok6), ok6 = all(ok6), n6diff = n6diff, neg6pass = count(neg6))
    end
    for x in D2b
        say("D2b ", x.key, ": ", x.nA, " steps with one candidate or none: output and next state equal step!: ", x.okA,
            " | ", x.nB, " drawing steps: candidates, keys (conf, habit, total), DET's choice equal step!: ", x.okB,
            " (full equality where the draw chose DET's motor, ", x.nFull, " steps: ", x.full, ")   neg: input y1 altered equal (must be false): ", x.negA)
        if startswith(split(x.key)[2], "CONF")
            say("D6 ", x.key, ": weights = 1 + step!'s conf at ", x.n6, " sampled drawing steps: ", x.ok6, " | steps with conf != habit in the sample: ", x.n6diff,
                "   neg: weights from habit pass at those steps (must be 0): ", x.neg6pass)
        end
    end
    res["D2"] = all(x -> x.eq && !x.neg, D2a) && all(x -> x.okA && x.okB && x.full && !x.negA && x.nA > 0 && x.nB > 0, D2b)
    C6 = [x for x in D2b if occursin(" CONF ", x.key)]
    res["D6"] = all(x -> x.n6 > 0 && x.ok6 && x.n6diff > 0 && x.neg6pass == 0, C6)
    say("D2: ", res["D2"], "   D6: ", res["D6"])
    # D3 replay / resume, D4 balance (UNI and CONF)
    SV = T0 + 1000
    D3 = tmap(c2) do (law, arm, u)
        ex = (SAVEAT = SV, TRACE = true)
        a = run_arm(law, arm, u; extra = ex); a2 = run_arm(law, arm, u; extra = ex)
        rerun = deq(a, a2)
        b = run_arm(law, arm, u; extra = (TRACE = true, RESUME = a["saved"]))
        resume = deq(without(a, "saved"), without(b, "saved"))
        bad = deepcopy(a["saved"]); bad[:drawer].pos = 0
        x = run_arm(law, arm, u; extra = (TRACE = true, RESUME = bad))
        negResume = deq(a["trace"], x["trace"])
        dr = drawlog(a["drawer"]); fb = DJ.load_bits(bitfile(u))
        okn, badn = CJ.replay(dr, fb, arm)
        dsh = deepcopy(dr); dsh["pos"] = [p + 1 for p in dsh["pos"]]
        _, badsh = CJ.replay(dsh, fb, arm)
        d = a["drawer"]
        used = sum(d.lnb[i] * (1 + d.lrej[i]) for i in eachindex(d.lt); init = 0)
        contig = all(d.lpos[i+1] == d.lpos[i] + d.lnb[i] * (1 + d.lrej[i]) for i in 1:length(d.lt)-1) && (isempty(d.lt) || d.lpos[1] == 0)
        bal = d.pos == used && contig
        rj = copy(d.lrej); lb = findlast(>(0), d.lnb); lb === nothing || (rj[lb] += 1)
        negBal = d.pos == sum(d.lnb[i] * (1 + rj[i]) for i in eachindex(d.lt); init = 0)
        (key = "$law $arm u$u", rerun = rerun, resume = resume, negResume = negResume, alivesv = alive_at(a, SV - T0), posAtSave = a["saved"][:drawer].pos,
         replayOk = okn, replayBad = badn, negShiftBad = badsh, bal = bal, used = used, negBal = negBal, rej = sum(d.lrej; init = 0))
    end
    for x in D3
        say("D3 ", x.key, ": rerun bit-identical: ", x.rerun, ", resume from the run state at ", SV, " (bit position ", x.posAtSave, ", alive ", x.alivesv,
            ") = uninterrupted: ", x.resume, ", records replayed from the bit file: ", x.replayOk, " ok / ", x.replayBad, " not",
            "   neg: resume without the bit position equal (must be false): ", x.negResume, ", positions shifted by 1, not reproduced: ", x.negShiftBad)
        say("D4 ", x.key, ": bits used ", x.used, " = sum b (1 + rejections) and positions contiguous: ", x.bal, " (rejections ", x.rej,
            ")   neg: one rejection added balances (must be false): ", x.negBal)
    end
    c4 = [(law, arm) for law in LAWS for arm in ("UNI", "CONF")]
    D4x = tmap(c4) do (law, arm)
        msg = try
            run_arm(law, arm, 686; bits = BITS[686][1:20]); "no error"
        catch err
            sprint(showerror, err)
        end
        (key = "$law $arm u686", stopped = occursin("exhausted", msg), msg = first(msg, 120))
    end
    for x in D4x; say("D4 exhaustion ", x.key, " (20-bit file): stopped with an error: ", x.stopped, "  (", x.msg, ")"); end
    res["D3"] = all(x -> x.rerun && x.resume && x.replayBad == 0 && x.replayOk > 0 && !x.negResume && x.negShiftBad > 0, D3)
    res["D4"] = all(x -> x.bal && !x.negBal, D3) && all(x -> x.stopped, D4x)
    # D4b: the draw function alone, W = 3 (UNI over three) and W = 10 (CONF with conf 4, 2, 1 -> 5:3:2), 100000 draws each
    ub = load_unit(); fb = newborn(false; rest = true)
    tri = [LabCore.unit(fb, "m1"), LabCore.unit(fb, "m2"), LabCore.unit(fb, "m0")]
    nU = length(fb.names); cz = zeros(Int, nU); cu = zeros(Int, nU); cu[tri[1]] = 4; cu[tri[2]] = 2; cu[tri[3]] = 1
    yz = [1.0, 1.0, 0.0]
    d4b = Bool[]; pos = 0
    for arm in ("UNI", "CONF")
        d = Drawer(arm, ub); d.pos = pos; d.t = T0
        cv = arm == "CONF" ? cu : cz
        for _ in 1:100_000; d(tri, tri, tri[1], m -> 0, fb, cv, cz, cz, yz); end
        p0 = pos; pos = d.pos
        dr = drawlog(d); rs = CJ.recs_of(dr)
        j = CJ.judge_groups(rs; minn = 400)
        rejn = sum(d.lrej)
        used = sum(d.lnb[i] * (1 + d.lrej[i]) for i in eachindex(d.lt))
        contig = d.lpos[1] == p0 && all(d.lpos[i+1] == d.lpos[i] + d.lnb[i] * (1 + d.lrej[i]) for i in 1:length(d.lt)-1)
        bal = d.pos - p0 == used && contig
        okr, badr = CJ.replay(dr, ub, arm)
        rj = copy(d.lrej); rj[findlast(>(0), d.lnb)] += 1
        negBal = d.pos - p0 == sum(d.lnb[i] * (1 + rj[i]) for i in eachindex(d.lt))
        wrong = CJ.judge_groups(rs; minn = 400, wover = (cs, w) -> arm == "UNI" ? [5, 3, 2] : [1, 1, 1])
        row = j["rows"][1]
        say("D4b ", arm, " W = ", sum(dr["w"][1]), ": draws ", length(d.lt), ", rejections ", rejn, ", shares ", round.(row["share"]; digits = 4),
            " vs ", round.(row["spec"]; digits = 4), ", p ", round(row["p"]; digits = 4), ", PB1 rule: ", j["verdict"], ", bits ", used, " = sum b (1 + rej), contiguous: ", bal,
            ", replayed ", okr, " ok / ", badr, "   neg: one rejection added balances (must be false): ", negBal,
            ", judged against the other weights (must be miss): ", wrong["verdict"])
        push!(d4b, length(j["rows"]) == 1 && rejn > 0 && j["verdict"] == "holds" && bal && badr == 0 && !negBal && wrong["verdict"] == "miss")
    end
    res["D4b"] = all(d4b)
    say("D3: ", res["D3"], "   D4: ", res["D4"], "   D4b: ", res["D4b"])
    # D5: biased bits, UNI and CONF, the PB1 rule with lower bound 100, per law and arm: at least one judged group does not match
    c5 = [(law, arm, u) for law in LAWS for arm in ("UNI", "CONF") for u in PILOT]
    D5r = tmap(c5) do (law, arm, u)
        r = run_arm(law, arm, u; bits = BBITS[u]); CJ.recs_of(drawlog(r["drawer"]))
    end
    d5 = Bool[]
    for law in LAWS, arm in ("UNI", "CONF")
        rs = reduce(vcat, [D5r[i] for i in eachindex(c5) if c5[i][1] == law && c5[i][2] == arm])
        j = CJ.judge_groups(rs; minn = 100)
        nm = count(r -> r["judged"] && !r["matches"], j["rows"])
        for r in j["rows"]
            r["judged"] || continue
            say("D5 ", law, " biased ", arm, " cs ", r["cs"], " w ", r["w"], ": n ", r["n"], ", shares ", round.(r["share"]; digits = 3), " vs ", round.(r["spec"]; digits = 3),
                ", p ", r["p"], ", Holm reject ", r["holmReject"], ", within 0.05 ", r["withinBand"])
        end
        push!(d5, j["nJudged"] > 0 && nm >= 1)
        say("D5 ", law, " ", arm, ": groups ", length(j["rows"]), ", judged ", j["nJudged"], ", not matching ", nm, " -> ", d5[end])
    end
    res["D5"] = all(d5)
    say("D5: ", res["D5"])
    # D7: the answered record against a separate count from the run's per-step acts, y and d (ON_STEP observer)
    c7 = [(law, arm, u) for law in LAWS for arm in ARMS for u in PILOT]
    D7 = tmap(c7) do (law, arm, u)
        col = Dict{Int,Any}()
        r = run_arm(law, arm, u; extra = (ON_STEP = x -> (col[x.t] = (acting = copy(x.acting), y = copy(x.y), d = copy(x.d), alive = x.alive)),))
        d = r["drawer"]
        acts = r["acts"]
        function cmp7(sh)
            local bad = 0; local n = 0
            for i in eachindex(d.lt)
                t = d.lt[i] + sh; n += 1
                c = get(col, t, nothing)
                if c === nothing || acts[t+1] != c.acting
                    bad += 1; continue
                end
                p = d.lch[i]
                good = c.alive && c.acting == [p] && d.lans[i] == (c.y[p] > 0) && d.ly[i] == c.y
                good || (bad += 1)
            end
            return n, bad
        end
        n, bad = cmp7(0); _, badsh = cmp7(1)
        ydis = count(i -> (p = d.lch[i]; c = col[d.lt[i]]; (c.y[p] > 0) != (c.d[p] > 0)), eachindex(d.lt))
        yall = count(t -> (c = col[t]; length(c.acting) == 1 && t >= T0 && (c.y[c.acting[1]] > 0) != (c.d[c.acting[1]] > 0)), keys(col))
        two = count(t -> length(col[t].acting) > 1, keys(col))
        ansRec = count(d.lans); ansCnt = count(i -> col[d.lt[i]].y[d.lch[i]] > 0, eachindex(d.lt))
        (key = "$law $arm u$u", n = n, bad = bad, badsh = badsh, ydis = ydis, yall = yall, two = two, ansRec = ansRec, ansCnt = ansCnt)
    end
    for x in D7
        say("D7 ", x.key, ": drawer records ", x.n, ", step-by-step mismatches with the separate count (step, patch, y[p] > 0): ", x.bad,
            " | answered recorded ", x.ansRec, " / recounted ", x.ansCnt, " | y[p] > 0 vs d[p] > 0 disagree at drawer steps: ", x.ydis,
            ", at all single-act steps from T0: ", x.yall, ", steps with two acts: ", x.two, "   neg: records shifted by one step, mismatches (must be > 0): ", x.badsh)
    end
    res["D7"] = all(x -> x.n > 0 && x.bad == 0 && x.badsh > 0 && x.ansRec == x.ansCnt, D7)
    res["D7 y-d disagreements"] = sum(x.ydis for x in D7)
    say("D7: ", res["D7"], " (y[p] > 0 vs d[p] > 0 disagreements at drawer steps, all runs: ", res["D7 y-d disagreements"], ")")
    summary = Dict(k => res[k] for k in ("F", "D1", "D2", "D3", "D4", "D4b", "D5", "D6", "D7"))
    say("== summary ", JSON.json(summary))
    write(joinpath(EXP, "results-draw-conf-gates.out"), join(GL, "\n") * "\n")
    write(joinpath(EXP, "results-draw-conf-gates.json"), JSON.json(merge(summary, Dict("notes" => NOTES, "D7 y-d disagreements" => res["D7 y-d disagreements"])), 2))
end

# ---------------- code freeze ----------------
const FZ = joinpath(EXP, "freeze-draw-conf-code.txt")
codefiles() = vcat(["draw_conf_grid.jl", "check_draw_conf.jl", "check_draw.jl", "synth_world.jl", "../core/circuit.jl", "../core/body_org.jl",
                    "results-draw-conf-gates.out", "draw-bits/unit-d4b.bits", "draw-bits/SHA256SUMS-d4b", "draw-conf-bits/SHA256SUMS"],
                   ["draw-conf-bits/" * n for n in bitnames()])
function freeze()
    isfile(FZ) && error("freeze-draw-conf-code.txt exists; not overwritten")
    g = JSON.parsefile(joinpath(EXP, "results-draw-conf-gates.json"))
    all(k -> g[k] == true, ("F", "D1", "D2", "D3", "D4", "D4b", "D5", "D6", "D7")) || error("gates not all true")
    freeze_ok()[1] || error("spec or predictions differ from freeze 1")
    open(FZ, "w") do io
        println(io, "# S57 code freeze (after the gates, before the pilot; ", Libc.strftime("%Y-%m-%d %H:%M", time()), ")")
        for f in codefiles(); println(io, sha(normpath(joinpath(EXP, f))), "  ", f); end
    end
    println(read(FZ, String))
end
function code_ok(; pilot = false)
    isfile(FZ) || error("needs freeze-draw-conf-code.txt")
    ref = read_sums(FZ)
    for f in codefiles()
        (haskey(ref, f) && sha(normpath(joinpath(EXP, f))) == ref[f]) || error("code freeze: $f differs or is missing")
    end
    bits_ok(; extra = ref) || error("bit files differ from the rule, SHA256SUMS or the code freeze")
    pilot || return nothing
    f = "results-draw-conf-pilot.json"
    (haskey(ref, f) && sha(joinpath(EXP, f)) == ref[f]) || error("code freeze: the pilot block is missing or differs")
    adm = Dict{String,Bool}(); p2 = Dict{String,Bool}()
    for l in eachline(FZ)
        m = match(r"^# admit (\S+) (true|false) pb2 (true|false)$", l)
        m === nothing || (adm[m.captures[1]] = m.captures[2] == "true"; p2[m.captures[1]] = m.captures[3] == "true")
    end
    P = JSON.parsefile(joinpath(EXP, f))
    all(law -> haskey(adm, law) && adm[law] == P["admit"][law] && p2[law] == P["pb2admit"][law], LAWS) || error("code freeze: the pilot decision differs")
    return adm
end

# ---------------- pilot and evaluation ----------------
function summ(r)
    d = r["drawer"]; dr = drawlog(d)
    di = CJ.drawn_idx(dr)
    grp = sum((1 + dr["rej"][i] for i in di); init = 0); rj = sum((dr["rej"][i] for i in di); init = 0)
    Dict{String,Any}("death" => r["death"], "countAt" => r["countAt"], "final" => r["final"], "answered" => r["rep"]["answered"],
        "nActs" => r["rep"]["nActs"], "drawSteps" => length(di), "bitsUsed" => d.pos,
        "rejShare" => grp == 0 ? nothing : rj / grp,
        "agreeDET" => isempty(di) ? nothing : count(i -> dr["chosen"][i] == dr["det"][i], di) / length(di), "draws" => dr)
end
function runall(dir, c)
    mkpath(joinpath(OUTDIR, dir))
    flock = ReentrantLock()
    rs = tmap(c) do (law, arm, u)
        s = summ(run_arm(law, arm, u))
        write(joinpath(OUTDIR, dir, "$(law)_$(arm)_u$(u).json"), JSON.json(s))
        delete!(s, "draws"); s
    end
    return rs
end
function pilot()
    code_ok()
    freeze_ok()[1] || error("spec or predictions differ from freeze 1")
    occursin("results-draw-conf-pilot.json", read(FZ, String)) && error("the pilot block is already in the code freeze; not rerun")
    say(NOTES)
    c = [(law, arm, u) for law in LAWS for arm in ARMS for u in PILOT]
    t0 = time()
    rs = runall("pilot", c)
    runs = Dict{String,Any}(law => Dict{String,Any}(arm => Dict{String,Any}() for arm in ARMS) for law in LAWS)
    for (i, (law, arm, u)) in enumerate(c); runs[law][arm][string(u)] = rs[i]; end
    admit = Dict{String,Any}(); pb2 = Dict{String,Any}()
    for law in LAWS
        ok = true
        for arm in ARMS
            v = [runs[law][arm][string(u)] for u in PILOT]
            nal = count(x -> x["death"] === nothing || x["death"] > T0 + 2000, v); nd = [x["drawSteps"] for x in v]
            m = nal >= 3 && minimum(nd) >= 200
            ok = ok && m
            say("pilot ", law, " ", rpad(arm, 4), ": alive at T0+2000 ", nal, "/4, drawing steps per window ", join(nd, " "), " (min ", minimum(nd), ")",
                " | death ", join([x["death"] === nothing ? "-" : x["death"] for x in v], " "), " -> ", m ? "meets" : "does not meet")
        end
        nu = [CJ.n_unequal(JSON.parsefile(joinpath(OUTDIR, "pilot", "$(law)_CONF_u$(u).json"))["draws"]) for u in PILOT]
        pb2[law] = all(>=(100), nu)
        admit[law] = ok
        say("pilot ", law, " CONF drawing steps with unequal weights per window: ", join(nu, " "), " -> ", pb2[law] ? "meets" : "does not meet")
        say("pilot decision ", law, ": ", ok ? "admit (all three arms to the evaluation windows)" : "not admit (cannot be measured)",
            "; PB2 ", pb2[law] ? "admissible" : "below the pre-set admission condition")
    end
    out = Dict{String,Any}("windows" => collect(PILOT), "admit" => admit, "pb2admit" => pb2, "notes" => NOTES, "runs" => runs)
    pf = joinpath(EXP, "results-draw-conf-pilot.json")
    write(pf, JSON.json(out))
    write(joinpath(EXP, "results-draw-conf-pilot.out"), join(GL, "\n") * "\nwall $(round(time() - t0; digits = 1)) s, threads $(Threads.nthreads())\n")
    open(FZ, "a") do io
        println(io, "# S57 pilot block (after the pilot, before the evaluation; ", Libc.strftime("%Y-%m-%d %H:%M", time()), ")")
        println(io, sha(pf), "  results-draw-conf-pilot.json")
        for law in LAWS; println(io, "# admit ", law, " ", admit[law], " pb2 ", pb2[law]); end
    end
end
function evalrun()
    adm = code_ok(; pilot = true)
    freeze_ok()[1] || error("spec or predictions differ from freeze 1")
    say(NOTES)
    for law in LAWS; adm[law] || say("law ", law, ": not admitted by the pilot -> not run (cannot be measured)"); end
    c = [(law, arm, u) for law in LAWS if adm[law] for arm in ARMS for u in EVALS
         if !isfile(joinpath(OUTDIR, "eval", "$(law)_$(arm)_u$(u).json"))]
    say("tasks ", length(c), ", threads ", Threads.nthreads())
    t0 = time()
    runall("eval", c)
    say("eval: wall ", round(time() - t0; digits = 1), " s")
    open(joinpath(EXP, "results-draw-conf-eval-run.out"), "a") do io; println(io, join(GL, "\n")); end
end

if MODE in ("gates", "freeze", "pilot", "eval")
    MODE == "gates" && make_bits()
    isdir(BITDIR) || error("no bit files; run gates first")
    if MODE != "freeze"
        for u in BITU; BITS[u] = DJ.load_bits(bitfile(u)); end
        for u in PILOT; BBITS[u] = DJ.load_bits(bitfile(u; biased = true)); end
    end
    MODE == "gates" ? gates() : MODE == "freeze" ? freeze() : MODE == "pilot" ? pilot() : evalrun()
else
    error("mode gates | freeze | pilot | eval")
end
