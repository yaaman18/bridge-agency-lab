# S55 (A0) drawing among the candidate motors (discussion/specs/S55-draw.md r3; predictions-draw.md r2; freeze-draw.txt freeze 2).
# World of item 155 (synth_world.jl: P = 1000, sigma = 1, L = 300, M = 2.5, no crossing), laws L2 and L2+SF, 10000 steps.
# Arms DET (the rank of core/circuit.jl), UNI (uniform over the choosing set), FIXP (weights 5 / 3 / 2 for the motors of
# patch 1 / patch 2 / m0). The raising (to T0 = 800) is DET in every arm; the draw is used from T0.
# core/ is not changed: step_draw! is made from the source text of core/circuit.jl's step! (renamed; one keyword and one
# insertion at anchors that must each occur once) and body_org_run_draw from core/body_org.jl's body_org_run (it calls
# step_draw!, carries the drawer with its bit position in its run state, can save that run state at a step and resume
# from it). Both are evaluated into LabCore.
# Bits: one frozen file per window (draw-bits/u<u>.bits, 400000 ASCII '0'/'1'): bit i = the least significant bit of the
# i-th output of Mulberry(1000003 u + 55). D5 files (draw-bits/u<u>-biased.bits): a 0 of the window's bits becomes 1
# when the i-th output of Mulberry(1000003 u + 56) is below 0.2 (about 60 % ones). draw-bits/SHA256SUMS lists them.
# Usage (from experiments/):
#   julia --project=.. -t 4 draw_grid.jl gates   F, D1-D5 on the pilot windows 670-673 (writes the bit files if absent)
#   julia --project=.. -t 4 draw_grid.jl pilot   pilot windows 670-673, PA1 and the admission per law
#   julia --project=.. -t 4 draw_grid.jl main    evaluation windows 674-685 (needs freeze-draw-code.txt; admitted laws only)
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON, SHA
include(joinpath(@__DIR__, "synth_world.jl"))
include(joinpath(@__DIR__, "check_draw.jl"))
using .DrawJudge
const DJ = DrawJudge

const LAB = normpath(joinpath(@__DIR__, ".."))
const EXP = joinpath(LAB, "experiments")
const BITDIR = joinpath(EXP, "draw-bits")
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode gates | pilot | main")
const T0 = 800; const STEPS = 10000
const COUNTAT = [T0 + x for x in (500, 2000, 9200)]
const STATEAT = T0 + 2000
const BASE = (U = 0.02, MCOST = 0.004, STEPS = STEPS, FEED = true, KC = 0.002, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
const LAWS = ("L2", "L2+SF")
law_opts(law) = law == "L2" ? BASE : merge(BASE, (SEDFADE = true,))
const WP = (P = 1000, sigma = 1, L = 300, M = 2.5)
world_opts(u) = (SCHED = synth_sched(u, WP.P, WP.sigma, WP.L, WP.M),)
const ARMS = ("DET", "UNI", "FIXP")
const PILOT = 670:673; const EVALS = 674:685
const NBITS = DJ.NBITS

# ---------------- bit files ----------------
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
# every run: the bit files equal the rule and their shas equal SHA256SUMS (and, in main, the code freeze)
function bits_ok(; extra = nothing)
    ref = read_sums(joinpath(BITDIR, "SHA256SUMS"))
    okS = all(n -> haskey(ref, n) && sha(joinpath(BITDIR, n)) == ref[n], bitnames())
    okR = all(u -> DJ.load_bits(bitfile(u)) == gen_bits(u), BITU) && all(u -> DJ.load_bits(bitfile(u; biased = true)) == gen_biased(u), PILOT)
    okX = extra === nothing || all(n -> get(extra, "draw-bits/" * n, "") == ref[n], bitnames())
    return okS && okR && okX
end
const BITS = Dict{Int,Vector{UInt8}}()
# D4b (spec r3 §8): the unit-test stream, same rule with its own constant: bit i = LSB of the i-th output of Mulberry(1000003 + 57)
const NUNIT = 1_500_000
const UNITFILE = joinpath(BITDIR, "unit-d4b.bits"); const UNITSUMS = joinpath(BITDIR, "SHA256SUMS-d4b")
gen_unit() = (r = Mulberry(1_000_003 + 57); UInt8[lsb(r()) for _ in 1:NUNIT])
function make_unit()
    isfile(UNITFILE) && return false
    write(UNITFILE, gen_unit() .+ UInt8('0')); write(UNITSUMS, sha(UNITFILE) * "  unit-d4b.bits\n")
    return true
end
function load_unit()
    v = read(UNITFILE); length(v) == NUNIT && all(c -> c == UInt8('0') || c == UInt8('1'), v) || error("unit bit file")
    return v .- UInt8('0')
end
unit_ok() = get(read_sums(UNITSUMS), "unit-d4b.bits", "") == sha(UNITFILE) && load_unit() == gen_unit()
const NOTES = "Decisions accepted by the coordinator (2026-11-15): PA4 state = world (A, B, C, port, counters), pools, circuit state, " *
    "noise RNG; the draw mechanism and the records are excluded. D5 second stream: a 0 becomes 1 where Mulberry(1000003u+56) < 0.2; " *
    "D5 judged per law. Bit files are ASCII '0'/'1'. Spec r3 §8: the body has no m0, the candidate set is {m1, m2}, W = 2 (UNI) and " *
    "8 (FIXP), so no rejection occurs in a life; the rejection path is exercised only in the unit test D4b."
const BBITS = Dict{Int,Vector{UInt8}}()

# ---------------- step_draw!: core/circuit.jl's step! with the draw ----------------
function rep1(f, anchor, new)
    n = length(findall(anchor, f)); n == 1 || error("anchor occurs $n times: $anchor")
    return replace(f, anchor => new)
end
const CIRCUIT_SRC = read(joinpath(LAB, "core", "circuit.jl"), String)
function draw_step_source(src)
    i = findfirst("function step!(st::CState, b::Circuit, y;", src); i === nothing && error("anchor: function step!")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    f = src[i[1]:j[end]]
    f = rep1(f, "function step!(st::CState, b::Circuit, y;", "function step_draw!(st::CState, b::Circuit, y;")
    f = rep1(f, "rest_off = false, body_flag = nothing)", "rest_off = false, body_flag = nothing, draw = nothing)")
    a = "        for m in cand; m != win && (nw[m] = false); end\n"
    f = rep1(f, a, """
        if draw !== nothing   # S55 (draw_grid.jl): one draw from the choosing set (the idle ones if any, else all); win is the rank's
            dcs = cand
            if idle_first; didl = [m for m in cand if now - st.lastM[m] > FORGET]; isempty(didl) || (dcs = didl); end
            win = draw(cand, dcs, win, key, b)
        end
""" * a)
    return f
end
const STEP_DRAW_SRC = draw_step_source(CIRCUIT_SRC)
Core.eval(LabCore, Meta.parse(STEP_DRAW_SRC))
const step_draw! = LabCore.step_draw!

# ---------------- body_org_run_draw: core/body_org.jl's body_org_run calling step_draw! ----------------
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
    f = rep1(f, "function body_org_run(cond::String", "function body_org_run_draw(cond::String")
    a = "TRACE = _opt(o, :TRACE, false) == true\n"
    f = rep1(f, a, a * """
    DRAW = _opt(o, :DRAW); SAVEAT = _opt(o, :SAVEAT); RESUME = _opt(o, :RESUME); STATEAT = _opt(o, :STATEAT); PRESTEP = _opt(o, :PRESTEP)
    DRAWFROM = _opt(o, :DRAWFROM, 800); drawer = DRAW; saved = nothing; stateAt = nothing   # S55 (draw_grid.jl)
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
            out = step_draw!(circuit, b, [yin[1], yin[2], 0.0]; """)
    f = rep1(f, "sil = silset)\n", "sil = silset, draw = (drawer !== nothing && t >= DRAWFROM) ? drawer : nothing)\n")
    f = rep1(f, "\"log\" => logv, \"acts\" => acts, ", "\"log\" => logv, \"acts\" => acts, \"drawer\" => drawer, \"saved\" => saved, \"stateAt\" => stateAt, ")
    return f
end
const RUN_DRAW_SRC = draw_run_source(BODY_ORG_SRC)
Core.eval(LabCore, Meta.parse(RUN_DRAW_SRC))
const body_org_run_draw = LabCore.body_org_run_draw

# ---------------- the drawer (spec §2) ----------------
mutable struct Drawer
    arm::String
    bits::Vector{UInt8}
    pos::Int          # bits used so far (0-based position of the next bit)
    t::Int            # the body step (set by the run before each circuit step)
    lt::Vector{Int}; lcand::Vector{Vector{Int}}; lcs::Vector{Vector{Int}}; lkeys::Vector{Vector{Int}}
    ldet::Vector{Int}; lch::Vector{Int}; lpos::Vector{Int}; lnb::Vector{Int}; lrej::Vector{Int}
end
Drawer(arm, bits) = Drawer(arm, bits, 0, -1, Int[], Vector{Int}[], Vector{Int}[], Vector{Int}[], Int[], Int[], Int[], Int[], Int[])
# Called by step_draw! when there are two or more candidates. cs is ordered by (patch, unit index); with fewer than two
# in cs, or DET, no bit is used and the rank's win is kept.
function (d::Drawer)(cand, cs, win, key, b)
    s = sort(cs; by = m -> (b.patch[m], m))
    pats = [b.patch[m] for m in s]
    push!(d.lt, d.t); push!(d.lcand, copy(cand)); push!(d.lcs, pats); push!(d.lkeys, [key(m) for m in s]); push!(d.ldet, b.patch[win])
    pos0 = d.pos; nb = 0; rej = 0; ch = win
    if length(s) >= 2 && d.arm != "DET"
        w = DJ.draw_weights(d.arm, pats); W = sum(w)
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
    push!(d.lch, b.patch[ch]); push!(d.lpos, pos0); push!(d.lnb, nb); push!(d.lrej, rej)
    return ch
end
drawlog(d::Drawer) = Dict{String,Any}("t" => d.lt, "ncand" => length.(d.lcand), "cs" => d.lcs, "det" => d.ldet, "chosen" => d.lch,
                                      "pos" => d.lpos, "nb" => d.lnb, "rej" => d.lrej)

bitsfor(u; biased = false) = biased ? BBITS[u] : BITS[u]
function run_arm(law, arm, u; bits = nothing, extra = (;))
    d = Drawer(arm, bits === nothing ? bitsfor(u) : bits)
    return body_org_run_draw("ORG", u, merge(law_opts(law), world_opts(u), (COUNTAT = COUNTAT, REPORT = true, STATEAT = STATEAT, DRAW = d), extra))
end

# ---------------- comparison helpers ----------------
function deq(a, b)
    (a isa AbstractDict && b isa AbstractDict) && return Set(keys(a)) == Set(keys(b)) && all(deq(a[k], b[k]) for k in keys(a))
    typeof(a) == typeof(b) || return false
    if a isa AbstractArray
        return size(a) == size(b) && all(deq(a[i], b[i]) for i in eachindex(a))
    elseif a isa AbstractDict
        return Set(keys(a)) == Set(keys(b)) && all(deq(a[k], b[k]) for k in keys(a))
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
# sha256 of a canonical serialization (PA4 state at T0 + 2000)
function ser!(io, x)
    if x === nothing
        write(io, UInt8('N'))
    elseif x isa AbstractString
        write(io, UInt8('S'), Int64(sizeof(x)), x)
    elseif x isa Number
        write(io, UInt8('n'), x)
    elseif x isa AbstractArray
        write(io, UInt8('A'), Int64(length(x))); for y in x; ser!(io, y); end
    elseif x isa Tuple || x isa NamedTuple
        write(io, UInt8('T'), Int64(length(x))); for y in x; ser!(io, y); end
    else
        write(io, UInt8('O'), string(typeof(x))); for f in fieldnames(typeof(x)); ser!(io, getfield(x, f)); end
    end
end
digest(x) = (io = IOBuffer(); ser!(io, x); bytes2hex(sha256(take!(io))))
alive_at(r, x) = r["death"] === nothing || r["death"] > T0 + x

const GL = String[]
say(x...) = (s = string(x...); println(s); push!(GL, s); flush(stdout))
function freeze_ok()
    ref = Dict{String,String}()
    for l in eachline(joinpath(EXP, "freeze-draw.txt"))
        startswith(l, "# S55 freeze 2") && empty!(ref)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    return length(ref) == 2 && all(sha(joinpath(EXP, f)) == h for (f, h) in ref), ref
end
function tmap(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads for i in eachindex(xs); out[i] = f(xs[i]); end
    return out
end
spread(v, n) = length(v) <= n ? v : v[unique(round.(Int, range(1, length(v); length = n)))]
stepkw(law) = (contrast = :bin3, idle_first = true, core_gate = true, seen_both = false, sed_fade = law == "L2+SF")
function keys_from(st0, b, drove, cs)
    n = length(b.names); tot = zeros(Int, n); conf = zeros(Int, n); hab = zeros(Int, n)
    for (k, (a, c, w)) in enumerate(b.edges)
        drove[k] || continue
        tot[c] += w
        if st0.q[k] >= 1; conf[c] += w; elseif st0.sg[k] >= 1; hab[c] += w; end
    end
    return [conf[m] * 1_000_000 + hab[m] * 1_000 + tot[m] for m in cs]
end

# ---------------- gates ----------------
function gates()
    res = Dict{String,Any}()
    say(NOTES)
    say("D4b unit bit file ", make_unit() ? "written" : "present")
    made = make_bits()
    say("bit files ", made ? "written" : "present", " in ", BITDIR)
    okF, ref = freeze_ok()
    okB = bits_ok()
    # negative control of the bit check: one flipped bit differs from the rule
    nb = copy(DJ.load_bits(bitfile(670))); nb[1000] = 0x01 - nb[1000]
    negB = nb == gen_bits(670)
    # chi-square self-test (known values)
    cst = [abs(DJ.chi2p(4.0, 2) - exp(-2.0)) < 1e-12, abs(DJ.chi2p(3.841458820694124, 1) - 0.05) < 1e-9,
           abs(DJ.chi2p(7.814727903251178, 3) - 0.05) < 1e-9, abs(DJ.chi2p(0.5, 1) - 0.4795001221869535) < 1e-9]
    say("F: spec and predictions equal freeze 2 of freeze-draw.txt: ", okF, "  ", ref)
    say("F: bit files equal the rule and SHA256SUMS: ", okB, "   neg: a flipped bit equals the rule (must be false): ", negB,
        "   chi-square p self-test: ", cst)
    okU = unit_ok()
    say("F: D4b unit bit file equals its rule and SHA256SUMS-d4b: ", okU)
    res["F"] = okF && okB && !negB && all(cst) && okU
    res["shas"] = Dict("core/circuit.jl" => sha(joinpath(LAB, "core", "circuit.jl")), "core/body_org.jl" => sha(joinpath(LAB, "core", "body_org.jl")),
                       "synth_world.jl" => sha(joinpath(EXP, "synth_world.jl")))
    TR = (TRACE = true,)
    # D1: DET through the copy = body_org_run at every step (both laws, pilot windows); neg: UNI differs
    c1 = [(law, u) for law in LAWS for u in PILOT]
    D1 = tmap(c1) do (law, u)
        o = merge(law_opts(law), world_opts(u), (COUNTAT = COUNTAT, REPORT = true), TR)
        a = body_org_run("ORG", u, o)
        dd = body_org_run_draw("ORG", u, merge(o, (DRAW = Drawer("DET", BITS[u]),)))
        du = body_org_run_draw("ORG", u, merge(o, (DRAW = Drawer("UNI", BITS[u]),)))
        ks = collect(keys(a))
        (key = "$law u$u", eq = deq(a, Dict(k => dd[k] for k in ks)), neg = deq(a, Dict(k => du[k] for k in ks)), nDraw = count(>=(2), length.(dd["drawer"].lcs)))
    end
    for x in D1; say("D1 ", x.key, ": DET copy = body_org_run at every step: ", x.eq, " (steps with two or more in the choosing set: ", x.nDraw, ")   neg: UNI = body_org_run (must be false): ", x.neg); end
    res["D1"] = all(x -> x.eq && !x.neg, D1)
    say("D1: ", res["D1"])
    # D2 (a): the state at T0 of UNI and FIXP = DET (saved run state at T0 without the drawer); neg: drawing from step 0
    c2 = [(law, arm, u) for law in LAWS for arm in ("UNI", "FIXP") for u in PILOT]
    D2a = tmap(c2) do (law, arm, u)
        sd = run_arm(law, "DET", u; extra = (SAVEAT = T0, TRACE = true))["saved"]
        sa = run_arm(law, arm, u; extra = (SAVEAT = T0, TRACE = true))["saved"]
        sx = run_arm(law, arm, u; extra = (SAVEAT = T0, TRACE = true, DRAWFROM = 0))["saved"]
        (key = "$law $arm u$u", eq = deq(without(sd, :drawer), without(sa, :drawer)), neg = deq(without(sd, :drawer), without(sx, :drawer)),
         nb = sa[:drawer].pos)
    end
    for x in D2a; say("D2a ", x.key, ": run state at T0 = DET (bits used before T0: ", x.nb, "): ", x.eq, "   neg: drawing from step 0 equal (must be false): ", x.neg); end
    # D2 (b): one-step comparison with core's step! from states taken during the UNI / FIXP runs
    D2b = tmap(c2) do (law, arm, u)
        r = run_arm(law, arm, u)
        dl = r["drawer"]; dset = Set(dl.lt)
        e = r["death"] === nothing ? STEPS : r["death"]
        A = spread([t for t in T0:e-1 if !(t in dset)], 50); B = spread(dl.lt, 50)
        want = Set(vcat(A, B)); cap = Dict{Int,Any}()
        r2 = run_arm(law, arm, u; extra = (PRESTEP = x -> (x.t in want && (cap[x.t] = deepcopy(x))),))
        kw = stepkw(law)
        okA = Bool[]; okB = Bool[]; negA = Bool[]; full = Bool[]
        for t in A
            x = cap[t]; p = deepcopy(x); q = deepcopy(x); z = deepcopy(x)
            o1 = step!(p.circuit, p.b, p.yin; noise = p.noise, sil = p.sil, kw...)
            q.drawer.t = t
            o2 = step_draw!(q.circuit, q.b, q.yin; noise = q.noise, sil = q.sil, draw = q.drawer, kw...)
            push!(okA, deq(o1, o2) && deq(p.circuit, q.circuit) && deq(p.noise, q.noise) && deq(p.b, q.b) && q.drawer.pos == x.drawer.pos)
            z.yin[1] = 5.0 - z.yin[1]
            o3 = step_draw!(z.circuit, z.b, z.yin; noise = z.noise, sil = z.sil, draw = z.drawer, kw...)
            push!(negA, deq(o1, o3) && deq(p.circuit, z.circuit))
        end
        for t in B
            x = cap[t]; p = deepcopy(x); q = deepcopy(x)
            o1 = step!(p.circuit, p.b, p.yin; noise = p.noise, sil = p.sil, kw...)
            q.drawer.t = t; n0 = length(q.drawer.lt)
            o2 = step_draw!(q.circuit, q.b, q.yin; noise = q.noise, sil = q.sil, draw = q.drawer, kw...)
            d = q.drawer
            ok = length(d.lt) == n0 + 1 && o1.choice !== nothing && d.lcand[end] == o1.choice.cand && deq(o1.drove, o2.drove) &&
                 d.ldet[end] == x.b.patch[o1.choice.win] && deq(o1.choice, o2.choice) && deq(p.noise, q.noise)
            if ok
                ord = sort(o1.choice.cand; by = m -> (x.b.patch[m], m))
                dcs = [m for m in ord if x.b.patch[m] in d.lcs[end]]
                ok = d.lkeys[end] == keys_from(x.circuit, x.b, o1.drove, dcs)
            end
            push!(okB, ok)
            d.lch[end] == d.ldet[end] && push!(full, deq(o1, o2) && deq(p.circuit, q.circuit))
        end
        (key = "$law $arm u$u", nA = length(A), nB = length(B), okA = all(okA), okB = all(okB), negA = all(negA), full = all(full), nFull = length(full))
    end
    for x in D2b
        say("D2b ", x.key, ": ", x.nA, " steps with one candidate or none: output and next state equal step!: ", x.okA,
            " | ", x.nB, " steps with two or more: candidates, keys, DET's choice equal step!: ", x.okB,
            " (and full equality where the draw chose DET's motor, ", x.nFull, " steps: ", x.full, ")   neg: input y1 altered equal (must be false): ", x.negA)
    end
    res["D2"] = all(x -> x.eq && !x.neg, D2a) && all(x -> x.okA && x.okB && x.full && !x.negA && x.nA > 0 && x.nB > 0, D2b)
    say("D2: ", res["D2"])
    # D3 replay / resume, D4 balance
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
        okn, badn = DJ.replay(dr, fb, arm)
        dsh = deepcopy(dr); dsh["pos"] = [p + 1 for p in dsh["pos"]]
        _, badsh = DJ.replay(dsh, fb, arm)
        d = a["drawer"]
        used = sum(d.lnb[i] * (1 + d.lrej[i]) for i in eachindex(d.lt); init = 0)
        contig = all(d.lpos[i+1] == d.lpos[i] + d.lnb[i] * (1 + d.lrej[i]) for i in 1:length(d.lt)-1) && (isempty(d.lt) || d.lpos[1] == 0)
        bal = d.pos == used && contig
        rj = copy(d.lrej); lb = findlast(>(0), d.lnb); lb === nothing || (rj[lb] += 1)   # spec r3 §8: the last record with b > 0
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
    # D4 exhaustion: a 20-bit file stops the run
    c4 = [(law, arm) for law in LAWS for arm in ("UNI", "FIXP")]
    D4x = tmap(c4) do (law, arm)
        msg = try
            run_arm(law, arm, 670; bits = BITS[670][1:20]); "no error"
        catch err
            sprint(showerror, err)
        end
        (key = "$law $arm u670", stopped = occursin("exhausted", msg), msg = first(msg, 120))
    end
    for x in D4x; say("D4 exhaustion ", x.key, " (20-bit file): stopped with an error: ", x.stopped, "  (", x.msg, ")"); end
    res["D3"] = all(x -> x.rerun && x.resume && x.replayBad == 0 && x.replayOk > 0 && !x.negResume && x.negShiftBad > 0, D3)
    res["D4"] = all(x -> x.bal && !x.negBal, D3) && all(x -> x.stopped, D4x)
    # D4b (spec r3 §8): the draw function alone, W = 3 (UNI over three) and W = 10 (FIXP 5:3:2), 100000 draws each
    ub = load_unit(); fb = newborn(false; rest = true)
    tri = [LabCore.unit(fb, "m1"), LabCore.unit(fb, "m2"), LabCore.unit(fb, "m0")]
    d4b = Bool[]; pos = 0
    for arm in ("UNI", "FIXP")
        d = Drawer(arm, ub); d.pos = pos; d.t = T0
        for _ in 1:100_000; d(tri, tri, tri[1], m -> 0, fb); end
        p0 = pos; pos = d.pos
        dr = drawlog(d); rs = DJ.recs_of(dr)
        j = DJ.judge_sets(rs, arm; minn = 400)
        rejn = sum(d.lrej)
        used = sum(d.lnb[i] * (1 + d.lrej[i]) for i in eachindex(d.lt))
        contig = d.lpos[1] == p0 && all(d.lpos[i+1] == d.lpos[i] + d.lnb[i] * (1 + d.lrej[i]) for i in 1:length(d.lt)-1)
        bal = d.pos - p0 == used && contig
        okr, badr = DJ.replay(dr, ub, arm)
        rj = copy(d.lrej); rj[findlast(>(0), d.lnb)] += 1
        negBal = d.pos - p0 == sum(d.lnb[i] * (1 + rj[i]) for i in eachindex(d.lt))
        wrong = DJ.judge_sets(rs, arm == "UNI" ? "FIXP" : "UNI"; minn = 400)
        row = j["rows"][1]
        say("D4b ", arm, " W = ", sum(DJ.draw_weights(arm, [1, 2, 4])), ": draws ", length(d.lt), ", rejections ", rejn, ", shares ", round.(row["share"]; digits = 4),
            " vs ", round.(row["spec"]; digits = 4), ", p ", round(row["p"]; digits = 4), ", PA2 rule: ", j["verdict"], ", bits ", used, " = sum b (1 + rej), contiguous: ", bal,
            ", replayed ", okr, " ok / ", badr, "   neg: one rejection added balances (must be false): ", negBal,
            ", judged against the other arm's weights (must be miss): ", wrong["verdict"])
        push!(d4b, rejn > 0 && j["verdict"] == "holds" && bal && badr == 0 && !negBal && wrong["verdict"] == "miss")
    end
    say("D4b: this path (W not a power of 2, rejections) is exercised only in this unit test; no life in S55 has three candidates.")
    res["D4b"] = all(d4b)
    say("D3: ", res["D3"], "   D4: ", res["D4"])
    # D5: biased bits, UNI, the PA2 rule with lower bound 100, per law: at least one judged set does not match
    c5 = [(law, u) for law in LAWS for u in PILOT]
    D5r = tmap(c5) do (law, u)
        r = run_arm(law, "UNI", u; bits = BBITS[u]); DJ.recs_of(drawlog(r["drawer"]))
    end
    d5 = Bool[]
    for law in LAWS
        rs = reduce(vcat, [D5r[i] for i in eachindex(c5) if c5[i][1] == law])
        j = DJ.judge_sets(rs, "UNI"; minn = 100)
        nm = count(r -> r["judged"] && !r["matches"], j["rows"])
        for r in j["rows"]
            say("D5 ", law, " biased UNI set ", r["cs"], ": n ", r["n"], ", shares ", round.(r["share"]; digits = 3), ", p ", r["p"], ", judged ", r["judged"],
                r["judged"] ? string(", Holm reject ", r["holmReject"], ", within 0.05 ", r["withinBand"]) : "")
        end
        push!(d5, j["nJudged"] > 0 && nm >= 1)
        say("D5 ", law, ": judged sets ", j["nJudged"], ", not matching ", nm, " -> ", d5[end])
        res["D5 " * law] = j
    end
    res["D5"] = all(d5)
    say("D5: ", res["D5"])
    summary = Dict(k => res[k] for k in ("F", "D1", "D2", "D3", "D4", "D4b", "D5"))
    say("== summary ", JSON.json(summary))
    write(joinpath(EXP, "results-draw-gates.out"), join(GL, "\n") * "\n")
    write(joinpath(EXP, "results-draw-gates.json"), JSON.json(merge(summary, Dict("notes" => NOTES, "shas" => res["shas"], "D5 L2" => res["D5 L2"], "D5 L2+SF" => res["D5 L2+SF"])), 2))
end

# ---------------- pilot and main runs ----------------
function summ(r, arm)
    d = r["drawer"]; dr = drawlog(d)
    di = DJ.drawn_idx(dr)
    grp = sum((1 + dr["rej"][i] for i in di); init = 0); rj = sum((dr["rej"][i] for i in di); init = 0)
    Dict{String,Any}("death" => r["death"], "countAt" => r["countAt"], "final" => r["final"], "answered" => r["rep"]["answered"],
        "nActs" => r["rep"]["nActs"], "drawSteps" => length(di), "bitsUsed" => d.pos,
        "rejShare" => grp == 0 ? nothing : rj / grp,
        "agreeDET" => isempty(di) ? nothing : count(i -> dr["chosen"][i] == dr["det"][i], di) / length(di),
        "stateAt" => digest(r["stateAt"]), "draws" => dr)
end
function pilot()
    bits_ok() || error("bit files differ from the rule or SHA256SUMS")
    say(NOTES)
    freeze_ok()[1] || error("spec or predictions differ from freeze 2 of freeze-draw.txt")
    c = [(law, arm, u) for law in LAWS for arm in ARMS for u in PILOT]
    t0 = time()
    rs = tmap(c) do (law, arm, u); summ(run_arm(law, arm, u), arm); end
    runs = Dict{String,Any}(law => Dict{String,Any}(arm => Dict{String,Any}() for arm in ARMS) for law in LAWS)
    for (i, (law, arm, u)) in enumerate(c); runs[law][arm][string(u)] = rs[i]; end
    admit = Dict{String,Any}()
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
        admit[law] = ok
        say("pilot decision ", law, ": ", ok ? "admit (all three arms to the evaluation windows)" : "not admit (cannot be measured)")
    end
    out = Dict{String,Any}("windows" => collect(PILOT), "admit" => admit, "notes" => NOTES, "runs" => runs, "wall" => time() - t0)
    write(joinpath(EXP, "results-draw-pilot.json"), JSON.json(out))
    write(joinpath(EXP, "results-draw-pilot.out"), join(GL, "\n") * "\nwall $(round(time() - t0; digits = 1)) s, threads $(Threads.nthreads())\n")
end

function code_freeze()
    fz = joinpath(EXP, "freeze-draw-code.txt")
    isfile(fz) || error("main needs freeze-draw-code.txt")
    ref = read_sums(fz)
    need = vcat(["draw_grid.jl", "check_draw.jl", "synth_world.jl", "../core/circuit.jl", "../core/body_org.jl", "results-draw-pilot.json", "draw-bits/unit-d4b.bits", "draw-bits/SHA256SUMS-d4b", "draw-bits/SHA256SUMS"],
                ["draw-bits/" * n for n in bitnames()])
    for f in need
        (haskey(ref, f) && sha(normpath(joinpath(EXP, f))) == ref[f]) || error("code freeze: $f differs or is missing")
    end
    bits_ok(; extra = ref) || error("bit files differ from the rule, SHA256SUMS or the code freeze")
    adm = Dict{String,Bool}()
    for l in eachline(fz)
        m = match(r"^# admit (\S+) (true|false)$", l)
        m === nothing || (adm[m.captures[1]] = m.captures[2] == "true")
    end
    P = JSON.parsefile(joinpath(EXP, "results-draw-pilot.json"))
    all(law -> haskey(adm, law) && adm[law] == P["admit"][law], LAWS) || error("code freeze: the pilot decision differs")
    return adm
end
function main()
    adm = code_freeze()
    say(NOTES)
    freeze_ok()[1] || error("spec or predictions differ from freeze 2 of freeze-draw.txt")
    file = joinpath(EXP, "results-draw-main.json")
    done = Set{String}()
    if isfile(file)
        for l in eachline(file)
            d = try JSON.parse(l) catch; nothing end
            d === nothing || push!(done, d["key"])
        end
    end
    todo = [(law, u) for law in LAWS if adm[law] for u in EVALS if !("$law u$u" in done)]
    for law in LAWS; adm[law] || say("law ", law, ": not admitted by the pilot -> not run (cannot be measured)"); end
    say("tasks ", length(todo), ", done ", length(done), ", threads ", Threads.nthreads())
    isempty(todo) && return
    ch = Channel{Any}(length(todo)); for x in todo; put!(ch, x); end; close(ch)
    flock = ReentrantLock(); n = Threads.Atomic{Int}(0); t0 = time()
    @sync for _ in 1:Threads.nthreads()
        Threads.@spawn for (law, u) in ch
            A = Dict{String,Any}()
            for arm in ARMS
                a = run_arm(law, arm, u; extra = (TRACE = true,)); a2 = run_arm(law, arm, u; extra = (TRACE = true,))
                s = summ(a, arm); s["rerunIdentical"] = deq(a, a2); A[arm] = s
            end
            r = Dict{String,Any}("key" => "$law u$u", "law" => law, "u" => u, "arms" => A)
            lock(flock) do
                open(file, "a") do io; println(io, JSON.json(r)); end
                Threads.atomic_add!(n, 1)
                say(n[], "/", length(todo), "  ", r["key"], "  ", round(time() - t0; digits = 1), " s")
            end
        end
    end
    open(joinpath(EXP, "results-draw-main.out"), "a") do io; println(io, join(GL, "\n")); println(io, "main: wall $(round(time() - t0; digits = 1)) s, threads $(Threads.nthreads())"); end
end

if MODE in ("gates", "pilot", "main")
    MODE == "gates" && make_bits()
    isdir(BITDIR) || error("no bit files; run gates first")
    for u in BITU; BITS[u] = DJ.load_bits(bitfile(u)); end
    for u in PILOT; BBITS[u] = DJ.load_bits(bitfile(u; biased = true)); end
    MODE == "gates" ? gates() : MODE == "pilot" ? pilot() : main()
else
    error("mode gates | pilot | main")
end
