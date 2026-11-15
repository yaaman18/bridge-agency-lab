# S58 B-ret measured with test N (discussion/specs/S58-bret-norm.md r3; predictions-bret-norm.md r1; freeze-bret-norm.txt freeze 2).
# World of item 155 (synth_world.jl: P = 1000, sigma = 1, L = 300, M = 2.5, no crossing), law L2+SF, 10000 steps, T0 = 800.
# Arms (spec §1): A-ret (= L2+SF), AB-free (= SFD), AB-ret, B-ret, B-delay (s_{t-375}), B-yoke (the s of a B-ret run with
# another birth seed in the same window). Classes (spec §4): a (half of B of the body out), b (every other kept edge
# zeroed), c (the drive read 150 steps ahead from tp), 0 (none). tp = T0 + 3000 + (u mod 300), at the head of step tp.
# core/ is not changed: step_bret! is made from the source text of core/circuit.jl's step! (one keyword, a selection call,
# the restore condition and a counter in the sed_fade block, at anchors that must each occur once) and body_org_run_bret
# from core/body_org.jl's body_org_run (hooks at the head, after the death check, before the circuit step and before the
# upkeep). Both are evaluated into LabCore. body_org_run_sfd (core's body_org_run with sed_fade_drive = true) is the
# reference for AB-free in gate R1.
# Usage (from experiments/):
#   julia --project=.. -t 8 check_bret.jl               gates R1-R5 -> results-bret-gates.out / .json
#   julia --project=.. -t 8 bret_grid.jl pilot          pilot windows 726-729 (partners 766-769) -> results-bret-pilot.out / .json
#   julia --project=.. -t 8 bret_grid.jl eval           evaluation windows 730-765 (partners 770-805) -> results-bret-eval.out
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON, SHA
include(joinpath(@__DIR__, "synth_world.jl"))

const LAB = normpath(joinpath(@__DIR__, ".."))
const EXP = joinpath(LAB, "experiments")
const OUTDIR = joinpath(EXP, "bret-out")
const T0 = 800; const STEPS = 10000
const KC = 0.002
const DELTA = 375; const TBAND = 2000; const FORGETN = 100
const BASE = (U = 0.02, MCOST = 0.004, STEPS = STEPS, FEED = true, KC = KC, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true, SEDFADE = true)
const WP = (P = 1000, sigma = 1, L = 300, M = 2.5)
const ARMS = ("A-ret", "AB-free", "AB-ret", "B-ret", "B-delay", "B-yoke")
const CLASSES = ("a", "b", "c", "0")
const PCLASSES = ("a", "b", "c")
const PILOT = 726:729; const PILOTP = 766:769
const EVALS = 730:765; const EVALP = 770:805
tp_of(u) = T0 + 3000 + mod(u, 300)
partner_of(u) = u in PILOT ? PILOTP[u-first(PILOT)+1] : u in EVALS ? EVALP[u-first(EVALS)+1] : error("no partner for $u")

# ---------------- the world, class c ----------------
const TABS = Dict{Int,Matrix{Float64}}(); const TABLOCK = ReentrantLock()
function table(u)
    lock(TABLOCK) do
        get!(() -> synth_table(u, WP.P, WP.sigma, WP.L, WP.M; ns = SW_NS + 150), TABS, u)
    end
end
# from world time tp - 800 on, class c reads the table 150 steps ahead (the first SW_NS rows equal synth_sched's table)
function sched_of(u, cls, tp)
    g = table(u); s0 = tp - T0
    cls == "c" ? ((s, k) -> s >= s0 ? g[s+151, k] : g[s+1, k]) : ((s, k) -> g[s+1, k])
end

# ---------------- step_bret!: core/circuit.jl's step! with the age restore of the arm ----------------
function rep1(f, anchor, new)
    n = length(findall(anchor, f)); n == 1 || error("anchor occurs $n times: $anchor")
    return replace(f, anchor => new)
end
const CIRCUIT_SRC = read(joinpath(LAB, "core", "circuit.jl"), String)
function bret_step_source(src)
    i = findfirst("function step!(st::CState, b::Circuit, y;", src); i === nothing && error("anchor: function step!")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    f = src[i[1]:j[end]]
    f = rep1(f, "function step!(st::CState, b::Circuit, y;", "function step_bret!(st::CState, b::Circuit, y;")
    f = rep1(f, "rest_off = false, body_flag = nothing)", "rest_off = false, body_flag = nothing, ret = nothing)")
    a = "        st.lastC === nothing && (st.lastC = zeros(Int, ne))\n"
    f = rep1(f, a, a * "        ret === nothing || Main.bret_select!(ret, b, drove, acting, confirmed, ne)   # S58 (bret_grid.jl)\n")
    f = rep1(f, "            if confirmed[k] || (sed_fade_drive && drove[k] && b.edges[k][2] in acting)\n",
                "            if ret === nothing ? (confirmed[k] || (sed_fade_drive && drove[k] && b.edges[k][2] in acting)) : Main.bret_restore(ret, k, confirmed[k])\n")
    f = rep1(f, "                (a >= FORGET && a % FORGET == 0) && (st.sg[k] = max(st.sg[k] - 1, 0))\n", """
                if a >= FORGET && a % FORGET == 0
                    ret === nothing || Main.bret_judge!(ret, k, st.sg[k])
                    if ret !== nothing && st.sg[k] == 1
                        ret.lastsg += 1
                    end
                    st.sg[k] = max(st.sg[k] - 1, 0)
                end
""")
    return f
end
const STEP_BRET_SRC = bret_step_source(CIRCUIT_SRC)
Core.eval(LabCore, Meta.parse(STEP_BRET_SRC))
const step_bret! = LabCore.step_bret!

# ---------------- body_org_run_bret and body_org_run_sfd ----------------
const BODY_ORG_SRC = read(joinpath(LAB, "core", "body_org.jl"), String)
function run_slice(src)
    i = findfirst("function body_org_run(cond::String", src); i === nothing && error("anchor: function")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    return src[i[1]:j[end]]
end
function bret_run_source(src)
    f = run_slice(src)
    f = rep1(f, "function body_org_run(cond::String", "function body_org_run_bret(cond::String")
    a = "TRACE = _opt(o, :TRACE, false) == true\n"
    f = rep1(f, a, a * "    BR = _opt(o, :BRET)   # S58 (bret_grid.jl)\n")
    a = "        y = [min(5.0, floor(r / U + 1e-9)) for r in pool]\n"
    f = rep1(f, a, "        BR === nothing || Main.bret_head!(BR, t, w, pool, circuit, noise, alive)\n" * a)
    a = "        if alive && isempty(body); alive = false; death = t; end\n"
    f = rep1(f, a, a * "        BR === nothing || Main.bret_s!(BR, t, w, body, alive)\n")
    f = rep1(f, "            out = step!(circuit, b, [yin[1], yin[2], 0.0]; ",
                "            BR === nothing || Main.bret_pre!(BR, t, w, body)\n            out = step_bret!(circuit, b, [yin[1], yin[2], 0.0]; ")
    f = rep1(f, "sil = silset)\n", "sil = silset, ret = (BR === nothing ? nothing : BR.ret))\n")
    a = "        if alive && cond == \"ORG\" && KC != 0\n"
    f = rep1(f, a, "        BR === nothing || Main.bret_bill!(BR, t, w, body, alive, circuit, blocked + lost)\n" * a)
    f = rep1(f, "        step!(w, ())\n", "        BR === nothing ? step!(w, ()) : Main.bret_matter!(BR, t, w)\n")   # descriptive accounting only
    return f
end
# core/matter.jl's step! with accumulators (metabolism, turnover, binding, B of dying places); descriptive only
const MATTER_SRC = read(joinpath(LAB, "core", "matter.jl"), String)
function acct_source(src)
    i = findfirst("function step!(w::World, sources, ctl::Ctl = NOCTL)", src); i === nothing && error("anchor: matter step!")
    j = findnext("\nend\n", src, i[1]); f = src[i[1]:j[end]]
    f = rep1(f, "function step!(w::World, sources, ctl::Ctl = NOCTL)", "function step_acct!(w::World, sources, acc, ctl::Ctl = NOCTL)")
    f = rep1(f, "m = min(B[i], p.METAB * a); B[i] -= m; port_give!(w.port, m)", "m = min(B[i], p.METAB * a); B[i] -= m; port_give!(w.port, m); acc[1] += m")
    f = rep1(f, "r = B[i] * p.TURNOVER; B[i] -= r; A[i] += r", "r = B[i] * p.TURNOVER; B[i] -= r; A[i] += r; acc[2] += r")
    f = rep1(f, "bb = min(p.CAP - B[i], p.BIND * ba * A[i]); B[i] += bb; A[i] -= bb", "bb = min(p.CAP - B[i], p.BIND * ba * A[i]); B[i] += bb; A[i] -= bb; acc[3] += bb")
    f = rep1(f, "C[i] = 0; A[i] += B[i]; B[i] = 0.0; w.died += 1", "acc[4] += B[i]; C[i] = 0; A[i] += B[i]; B[i] = 0.0; w.died += 1")
    return f
end
Core.eval(LabCore, Meta.parse(acct_source(MATTER_SRC)))
function sfd_run_source(src)
    f = run_slice(src)
    f = rep1(f, "function body_org_run(cond::String", "function body_org_run_sfd(cond::String")
    f = rep1(f, "sed_fade = sed_fade, sil = silset)\n", "sed_fade = sed_fade, sed_fade_drive = true, sil = silset)\n")
    return f
end
const RUN_BRET_SRC = bret_run_source(BODY_ORG_SRC)
const RUN_SFD_SRC = sfd_run_source(BODY_ORG_SRC)
Core.eval(LabCore, Meta.parse(RUN_BRET_SRC))
Core.eval(LabCore, Meta.parse(RUN_SFD_SRC))
const body_org_run_bret = LabCore.body_org_run_bret
const body_org_run_sfd = LabCore.body_org_run_sfd

# ---------------- the arm inside the circuit step (spec §1) ----------------
mutable struct BRet
    mode::Symbol          # :A (confirmation), :ABfree (confirmation or use), :ABret (confirmation or paid use), :B (paid use)
    t::Int                # the body step
    allow::Int            # the number of uses that may be restored (s_t, or the s the control reads)
    ran::Bool
    used::Vector{Int}; usedmask::BitVector; tried::Vector{Int}; paid::Vector{Int}; paidmask::BitVector
    lastsg::Int
    judged::Int; judgedSg::Int; judgedUsed::Int; judgedSgUsed::Int; lastUse::Vector{Int}   # descriptive (decay judgments)
end
BRet() = BRet(:A, -1, 0, false, Int[], falses(0), Int[], Int[], falses(0), 0, 0, 0, 0, 0, Int[])
function bret_judge!(r::BRet, k, sg)
    rec = r.t - r.lastUse[k] <= FORGETN
    r.judged += 1; rec && (r.judgedUsed += 1)
    if sg >= 1
        r.judgedSg += 1; rec && (r.judgedSgUsed += 1)
    end
    return nothing
end
function bret_select!(r::BRet, b, drove, acting, confirmed, ne)
    r.used = [k for k in 1:ne if drove[k] && b.edges[k][2] in acting]
    isempty(r.lastUse) && (r.lastUse = fill(-10^9, ne))
    r.usedmask = falses(ne); r.usedmask[r.used] .= true
    r.tried = r.mode == :B ? copy(r.used) : r.mode == :ABret ? [k for k in r.used if !confirmed[k]] : Int[]
    n = length(r.tried)
    rot = [r.tried[mod(r.t + j, n)+1] for j in 0:n-1]
    np = min(max(r.allow, 0), n)
    r.paid = rot[1:np]
    r.paidmask = falses(ne); r.paidmask[r.paid] .= true
    return nothing
end
function bret_restore(r::BRet, k, conf::Bool)
    r.mode == :A && return conf
    r.mode == :ABfree && return conf || r.usedmask[k]
    r.mode == :ABret && return conf || r.paidmask[k]
    r.mode == :B && return r.paidmask[k]
    error("mode $(r.mode)")
end

# ---------------- the run object and the body hooks ----------------
mutable struct BRun
    arm::String; cls::String; u::Int; tp::Int; delta::Int
    partner::Union{Nothing,Vector{Int}}
    brk::Symbol            # :none, or a deliberate fault for a negative control (check_bret.jl)
    from::Int              # the arm's rule from this step (T0; gate R1 also uses 0 for AB-free against core's SFD)
    ret::BRet
    s::Vector{Int}; sread::Vector{Int}; nused::Vector{Int}; ntried::Vector{Int}; npaid::Vector{Int}
    ded::Vector{Float64}; short::Vector{Float64}; cost::Vector{Float64}; clamp::Vector{Int}
    bsize::Vector{Int}; alive::Vector{Bool}; r5::Vector{Bool}; lastsg::Vector{Int}; capn::Vector{Int}; ran::Vector{Bool}
    headB::Vector{Float64}; headBody::Vector{Int}
    pre::Any; pert::Any
    prevkept::Union{Nothing,BitVector}; vanT::Vector{Int}; nvanish::Int; nreform::Int; keptSteps::Vector{Int}; keptSum::Int; keptN::Int
    sumB::Vector{Float64}; kept::Vector{Int}; acc::Matrix{Float64}; judged::Matrix{Int}   # descriptive records
end
function BRun(arm, cls, u; tp = tp_of(u), delta = DELTA, partner = nothing, brk = :none, from = T0)
    z(T) = zeros(T, STEPS)
    BRun(arm, cls, u, tp, delta, partner, brk, from, BRet(), z(Int), fill(-1, STEPS), z(Int), z(Int), z(Int), z(Float64), z(Float64), z(Float64), z(Int),
         z(Int), falses(STEPS) |> collect, fill(true, STEPS), z(Int), z(Int), falses(STEPS) |> collect, Float64[], Int[], nothing, nothing,
         nothing, Int[], 0, 0, Int[], 0, 0, zeros(STEPS), fill(-1, STEPS), zeros(4, STEPS), zeros(Int, 5, STEPS))
end
function bret_matter!(R::BRun, t, w)
    acc = zeros(4); LabCore.step_acct!(w, (), acc); R.acc[:, t+1] .= acc
    return w
end
function perturb!(R::BRun, t, w, circuit, alive)
    if R.cls == "a"
        bd = [i for i in eachindex(w.C) if w.C[i] != 0]
        B0 = copy(w.B); res0 = w.port.reservoir; given = 0.0
        for i in bd; h = w.B[i] / 2; w.B[i] -= h; given += h; end
        given > 0 && port_give!(w.port, given)
        R.pert = (t = t, body = bd, B0 = B0, B1 = copy(w.B), res0 = res0, res1 = w.port.reservoir, given = given)
    elseif R.cls == "b" && circuit !== nothing
        q0 = copy(circuit.q); s0 = copy(circuit.sg)
        kept = [k for k in eachindex(circuit.q) if circuit.q[k] >= 1 || circuit.sg[k] >= 1]
        st = mod(R.u, 2); cut = [kept[j+1] for j in 0:length(kept)-1 if mod(j, 2) == st]
        for k in cut; circuit.q[k] = 0; circuit.sg[k] = 0; end
        R.pert = (t = t, kept = kept, cut = cut, q0 = q0, s0 = s0, q1 = copy(circuit.q), s1 = copy(circuit.sg))
    end
end
const port_give! = LabCore.port_give!
function bret_head!(R::BRun, t, w, pool, circuit, noise, alive)
    t == R.tp && (R.pre = deepcopy((w = w, pool = pool, circuit = circuit, noise = noise, alive = alive)))
    tpert = R.brk == :r4 ? R.tp - 1 : R.tp
    (t == tpert && alive && R.brk != :r5) && perturb!(R, t, w, circuit, alive)
    return nothing
end
function bret_s!(R::BRun, t, w, body, alive)
    R.alive[t+1] = alive; R.bsize[t+1] = length(body)
    R.s[t+1] = (alive && !isempty(body)) ? floor(Int, minimum(w.B[i] for i in body) / (KC / length(body))) : 0
    R.headB = copy(w.B); R.headBody = copy(body)
    R.sumB[t+1] = sum((w.B[i] for i in body); init = 0.0)
    return nothing
end
function bret_pre!(R::BRun, t, w, body)
    r = R.ret; r.t = t; r.ran = true; r.lastsg = 0; r.judged = 0; r.judgedSg = 0; r.judgedUsed = 0; r.judgedSgUsed = 0
    if t < R.from || R.arm == "A-ret"
        r.mode = :A; r.allow = 0
    elseif R.arm == "AB-free"
        r.mode = :ABfree; r.allow = 0
    else
        r.mode = R.arm == "AB-ret" ? :ABret : :B
        if R.arm == "AB-ret" || R.arm == "B-ret"
            r.allow = R.s[t+1]
        elseif R.arm == "B-delay"
            lag = R.brk == :r3 ? R.delta + 1 : R.delta
            r.allow = t < T0 + R.delta ? R.s[t+1] : R.s[t-lag+1]
        elseif R.arm == "B-yoke"
            r.allow = R.partner[t+1]
        else
            error("arm $(R.arm)")
        end
        R.sread[t+1] = r.allow
    end
    (R.brk == :r5 && t == R.tp) && perturb!(R, t, w, nothing, true)   # fault: the class-a cut between the head and the levy
    return nothing
end
function bret_bill!(R::BRun, t, w, body, alive, circuit, capn)
    r = R.ret
    R.r5[t+1] = isequal(w.B, R.headB) && R.headBody == body && body == [i for i in eachindex(w.C) if w.C[i] != 0]
    R.capn[t+1] = capn
    if r.ran
        R.ran[t+1] = true
        R.nused[t+1] = length(r.used); R.ntried[t+1] = length(r.tried); R.npaid[t+1] = length(r.paid); R.lastsg[t+1] = r.lastsg
        R.judged[:, t+1] .= (r.judged, r.judgedSg, r.judgedUsed, r.judgedSgUsed, 1)
        for k in r.used; r.lastUse[k] = t; end
        n = length(r.paid)
        if alive && n > 0
            nb = R.brk == :r2 ? n + 1 : n
            cost = KC * nb; d = cost / length(body); paid = 0.0; short = 0.0; cl = 0
            for i in body
                m = min(w.B[i], d); w.B[i] -= m; paid += m
                if m < d; short += d - m; cl += 1; end
            end
            paid > 0 && port_give!(w.port, paid)
            R.ded[t+1] = paid; R.short[t+1] = short; R.cost[t+1] = KC * n; R.clamp[t+1] = cl
        end
        r.ran = false
    end
    if alive && circuit !== nothing && t >= T0
        ne = length(circuit.q)
        kept = BitVector([circuit.q[k] >= 1 || circuit.sg[k] >= 1 for k in 1:ne])
        if R.prevkept === nothing
            R.vanT = fill(-1, ne); R.keptSteps = zeros(Int, ne)
        else
            for k in 1:ne
                if R.prevkept[k] && !kept[k]
                    R.nvanish += 1; R.vanT[k] = t
                elseif !R.prevkept[k] && kept[k] && R.vanT[k] >= 0
                    t - R.vanT[k] <= FORGETN && (R.nreform += 1)
                    R.vanT[k] = -1
                end
            end
        end
        R.keptSteps .+= kept; R.keptSum += count(kept); R.keptN += 1; R.kept[t+1] = count(kept)
        R.prevkept = kept
    end
    return nothing
end

# ---------------- runs ----------------
run_opts(u, cls, R; extra = (;)) = merge(BASE, (SCHED = sched_of(u, cls, R === nothing ? tp_of(u) : R.tp), REPORT = true), R === nothing ? (;) : (BRET = R,), extra)
# arm, class, window u; seed = the birth seed (u, or the partner's for the yoke's partner run)
function run_one(arm, cls, u; seed = u, partner = nothing, delta = DELTA, brk = :none, from = T0, extra = (;))
    R = BRun(arm, cls, u; delta = delta, partner = partner, brk = brk, from = from)
    res = body_org_run_bret("ORG", seed, run_opts(u, cls, R; extra = extra))
    return res, R
end

# ---------------- per-run summaries (spec §5) ----------------
dead_or(r) = r["death"] === nothing ? STEPS : r["death"]
alive_at(r, t) = r["death"] === nothing || r["death"] > t
function band_of(R::BRun)
    v = R.bsize[R.tp-300+1:R.tp]
    return (minimum(v), maximum(v))
end
inb(R, t, bd) = R.alive[t+1] && bd[1] <= R.bsize[t+1] <= bd[2]
function summary(res, R::BRun)
    tp = R.tp; aliveTp = alive_at(res, tp - 1) && R.alive[tp+1]
    pre = alive_at(res, tp - 1)   # the band needs the steps tp-300 .. tp-1
    bd = pre ? band_of(R) : nothing
    outEarly = pre ? any(t -> !inb(R, t, bd), tp:tp+299) : nothing
    aliveTT = alive_at(res, tp + TBAND)
    Z = pre && aliveTT && all(t -> inb(R, t, bd), tp+TBAND-300:tp+TBAND-1) ? 1 : 0
    rng = T0+1:tp   # steps T0 .. tp-1 (1-based indices)
    full = T0+1:STEPS
    Dict{String,Any}("arm" => R.arm, "cls" => R.cls, "u" => R.u, "tp" => tp, "death" => res["death"], "aliveTp" => aliveTp,
        "band" => bd === nothing ? nothing : [bd[1], bd[2]], "outEarly" => outEarly, "aliveTT" => aliveTT, "Z" => Z,
        "aliveOutOfBand" => aliveTT && Z == 0, "aliveEnd" => res["death"] === nothing,
        "pre" => Dict("nused" => sum(R.nused[rng]), "ntried" => sum(R.ntried[rng]), "npaid" => sum(R.npaid[rng]), "ded" => sum(R.ded[rng]), "short" => sum(R.short[rng])),
        "all" => Dict("nused" => sum(R.nused[full]), "ntried" => sum(R.ntried[full]), "npaid" => sum(R.npaid[full]), "ded" => sum(R.ded[full]), "short" => sum(R.short[full]),
                      "unpaidUsed" => sum(R.nused[full]) - sum(R.npaid[full]), "unpaidTried" => sum(R.ntried[full]) - sum(R.npaid[full])),
        "nvanish" => R.nvanish, "nreform" => R.nreform, "meanKept" => R.keptN == 0 ? nothing : R.keptSum / R.keptN, "keptSteps" => R.keptSteps,
        "lastsg" => sum(R.lastsg), "keptEnd" => res["keptEnd"], "sfacts" => sfacts(res, R))
end
# facts for the next spec (coordinator 2026-11-16; descriptive, not used by any decision)
med(v) = (w = sort(v); n = length(w); isodd(n) ? w[(n+1)÷2] : (w[n÷2] + w[n÷2+1]) / 2)
function sfacts(res, R::BRun)
    ts = [t for t in T0:R.tp-1 if R.alive[t+1]]
    sv = [R.s[t+1] for t in ts]; kb = [KC / R.bsize[t+1] for t in ts]
    f = Dict{String,Any}("sMinMedMax" => isempty(sv) ? nothing : [minimum(sv), med(sv), maximum(sv)], "maxUsedPerStep" => maximum(R.nused),
        "kcPerPlaceMinMedMax" => isempty(kb) ? nothing : [minimum(kb), med(kb), maximum(kb)])
    if R.cls == "a" && R.alive[R.tp+1]
        a = [R.s[t+1] for t in R.tp:min(R.tp + 99, STEPS - 1) if R.alive[t+1]]
        f["sAtTp"] = R.s[R.tp+1]; f["sMinTpTo99"] = isempty(a) ? nothing : minimum(a)
    end
    d = res["death"]
    if d !== nothing && d > 0
        f["sMinLast100BeforeDeath"] = minimum(R.s[max(0, d - 100)+1:d])
    end
    return f
end
# validity of a control against B-ret in a window (spec §3), from the class-0 runs (identical before tp across classes)
function validity(Rb::BRun, rb, Rc::BRun, rc)
    ts = [t for t in T0:Rb.tp-1 if Rb.alive[t+1] && Rc.alive[t+1]]
    pB = sum((Rb.npaid[t+1] for t in ts); init = 0); dB = sum((Rb.ded[t+1] for t in ts); init = 0.0)
    pC = sum((Rc.npaid[t+1] for t in ts); init = 0); dC = sum((Rc.ded[t+1] for t in ts); init = 0.0); sC = sum((Rc.short[t+1] for t in ts); init = 0.0)
    mB = isempty(ts) ? 0.0 : sum(Rb.s[t+1] for t in ts) / length(ts)
    mC = isempty(ts) ? 0.0 : sum(Rc.sread[t+1] for t in ts) / length(ts)
    early = !alive_at(rb, T0 + DELTA + 300 - 1) || !alive_at(rc, T0 + DELTA + 300 - 1)
    den0 = pB == 0 || dB == 0 || mB == 0
    v1 = !den0 && 0.5 <= pC / pB <= 2.0
    v2 = !den0 && 0.5 <= dC / dB <= 2.0
    v3 = (dC + sC) == 0 ? true : sC / (dC + sC) <= 0.2
    v4 = !den0 && abs(mC - mB) <= 0.5 * mB
    valid = !early && !den0 && v1 && v2 && v3 && v4
    return Dict{String,Any}("valid" => valid, "v1" => v1, "v2" => v2, "v3" => v3, "v4" => v4, "den0" => den0, "earlyDeath" => early,
        "nsteps" => length(ts), "paidB" => pB, "retC" => pC, "dedB" => dB, "dedC" => dC, "shortC" => sC, "meanSB" => mB, "meanSC" => mC)
end

# all arms and classes of one window (the yoke's partner runs first)
function window(u)
    p = partner_of(u); out = Dict{String,Any}("u" => u, "partner" => p, "tp" => tp_of(u))
    part = Dict{String,Any}(); runs = Dict{String,Any}(); keep = Dict{String,Any}()
    for cls in CLASSES
        res, R = run_one("B-ret", cls, u; seed = p)
        part[cls] = summary(res, R); keep["partner " * cls] = R.s
    end
    for arm in ARMS, cls in CLASSES
        res, R = run_one(arm, cls, u; partner = arm == "B-yoke" ? keep["partner " * cls] : nothing)
        runs[arm * " " * cls] = summary(res, R)
        cls == "0" && arm in ("B-ret", "B-delay", "B-yoke") && (keep[arm] = (res, R))
    end
    out["partnerRuns"] = part; out["runs"] = runs
    rb, Rb = keep["B-ret"]
    out["validity"] = Dict(c => validity(Rb, rb, keep[c][2], keep[c][1]) for c in ("B-delay", "B-yoke"))
    return out
end

function tmap(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads for i in eachindex(xs); out[i] = f(xs[i]); end
    return out
end
sha(f) = bytes2hex(open(sha256, f))
const GL = String[]
say(x...) = (s = string(x...); println(s); push!(GL, s); flush(stdout))
function freeze_ok()
    ref = Dict{String,String}(); inblk = false
    for l in eachline(joinpath(EXP, "freeze-bret-norm.txt"))
        startswith(l, "S58 freeze 2") && (inblk = true; empty!(ref))
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        (inblk && m !== nothing) && (ref[m.captures[2]] = m.captures[1])
    end
    ok = length(ref) == 2 && all(sha(joinpath(LAB, f)) == h for (f, h) in ref)
    return ok, ref
end
const CODEFILES = ["experiments/bret_grid.jl", "experiments/check_bret.jl", "experiments/synth_world.jl", "core/LabCore.jl", "core/jsmath.jl",
                   "core/circuit.jl", "core/life.jl", "core/matter.jl", "core/evo.jl", "core/body_org.jl", "core/dc.jl"]
function code_ok()
    fz = joinpath(EXP, "freeze-bret-norm-code.txt")
    isfile(fz) || return false
    ref = Dict{String,String}()
    for l in eachline(fz)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    return all(f -> haskey(ref, f) && sha(joinpath(LAB, f)) == ref[f], CODEFILES)
end
function signtest(D)
    pos = count(>(0), D); neg = count(<(0), D); n = pos + neg
    n < 8 && return Dict{String,Any}("pos" => pos, "neg" => neg, "zero" => count(==(0), D), "p" => nothing, "judge" => "undetectable")
    k = min(pos, neg); p = Float64(min(1.0, 2 * sum(binomial(big(n), i) for i in 0:k) / big(2)^n))
    j = p <= 0.05 ? (pos > neg ? "win" : "loss") : "not significant"
    return Dict{String,Any}("pos" => pos, "neg" => neg, "zero" => count(==(0), D), "p" => p, "judge" => j)
end

# ---------------- pilot (spec §6) ----------------
function pilot()
    okF, _ = freeze_ok(); okF || error("spec or predictions differ from freeze 2")
    code_ok() || error("code differs from freeze-bret-norm-code.txt")
    G = JSON.parsefile(joinpath(EXP, "results-bret-gates.json")); all(G["summary"][k] for k in ("R1", "R2", "R3", "R4", "R5")) || error("gates not passed")
    t0 = time()
    W = tmap(window, collect(PILOT))
    mkpath(OUTDIR)
    open(joinpath(OUTDIR, "pilot-windows.jsonl"), "w") do io; for w in W; println(io, JSON.json(w)); end; end
    say("S58 pilot, windows ", PILOT, " (partners ", PILOTP, "), tp = ", [w["tp"] for w in W])
    p1 = true
    for arm in ARMS
        n = count(w -> w["runs"][arm*" 0"]["aliveTp"], W)
        say("p1 ", rpad(arm, 8), ": alive at tp in ", n, "/4 windows   deaths ", [w["runs"][arm*" 0"]["death"] for w in W])
        p1 = p1 && n >= 3
    end
    say("p1: ", p1)
    nok = 0
    for w in W
        x = w["runs"]["B-ret 0"]["pre"]; un = x["nused"] - x["npaid"]
        ok = x["nused"] >= 100 && un >= 10 && x["npaid"] >= 10; ok && (nok += 1)
        say("p2 u", w["u"], " B-ret T0..tp-1: used ", x["nused"], ", unpaid ", un, ", paid ", x["npaid"], " -> ", ok)
    end
    p2 = nok >= 3
    say("p2: windows meeting ", nok, "/4 -> ", p2)
    keepc = String[]
    p3 = Dict{String,Any}()
    for c in PCLASSES
        n = count(w -> w["runs"]["B-ret "*c]["outEarly"] == true, W)
        p3[c] = n >= 2; p3[c] && push!(keepc, c)
        say("p3 class ", c, ": B-ret out of the band in tp..tp+299 in ", n, "/4 windows -> ", p3[c] ? "kept" : "dropped")
    end
    say("== facts for the next spec (descriptive; B-ret, s_t and KC / |body| over T0..tp-1 alive steps of class 0)")
    for w in W
        f0 = w["runs"]["B-ret 0"]["sfacts"]; fa = w["runs"]["B-ret a"]["sfacts"]
        dd = [string(c, ": ", get(w["runs"]["B-ret "*c]["sfacts"], "sMinLast100BeforeDeath", "-")) for c in CLASSES]
        say("u", w["u"], ": s_t min/median/max ", f0["sMinMedMax"], ", max used edges per step ", maximum(w["runs"]["B-ret "*c]["sfacts"]["maxUsedPerStep"] for c in CLASSES),
            ", KC/|body| min/median/max ", f0["kcPerPlaceMinMedMax"] === nothing ? "-" : round.(f0["kcPerPlaceMinMedMax"]; sigdigits = 4),
            ", class a: s at tp ", get(fa, "sAtTp", "-"), ", min s tp..tp+99 ", get(fa, "sMinTpTo99", "-"),
            ", min s in the 100 steps before death by class ", join(dd, " "))
    end
    stop = !(p1 && p2) || isempty(keepc)
    "c" in keepc || say("note: class (c) is dropped; the claim does not include the class the design of M does not anticipate")
    say("pilot decision: ", stop ? "STOP (cannot be measured; the evaluation is not run)" : "go, classes kept " * join(keepc, ","))
    out = Dict{String,Any}("p1" => p1, "p2" => p2, "p2windows" => nok, "p3" => p3, "kept" => keepc, "stop" => stop, "wall" => time() - t0)
    write(joinpath(EXP, "results-bret-pilot.json"), JSON.json(out, 2))
    write(joinpath(EXP, "results-bret-pilot.out"), join(GL, "\n") * "\nwall $(round(time() - t0; digits = 1)) s, threads $(Threads.nthreads())\n")
end

# ---------------- evaluation (spec §3, §5; predictions PN0-PN5) ----------------
function evaluation()
    okF, _ = freeze_ok(); okF || error("spec or predictions differ from freeze 2")
    code_ok() || error("code differs from freeze-bret-norm-code.txt")
    P = JSON.parsefile(joinpath(EXP, "results-bret-pilot.json")); P["stop"] && error("pilot stopped the evaluation")
    G = JSON.parsefile(joinpath(EXP, "results-bret-gates.json"))
    K = String.(P["kept"])
    t0 = time()
    W = tmap(window, collect(EVALS))
    mkpath(OUTDIR)
    open(joinpath(OUTDIR, "eval-windows.jsonl"), "w") do io; for w in W; println(io, JSON.json(w)); end; end
    Z(w, arm, c) = w["runs"][arm*" "*c]["Z"]
    say("S58 evaluation, windows ", EVALS, " (partners ", EVALP, "), classes kept by the pilot: ", join(K, ","))
    say("== validity (spec §3; T0..tp-1, both alive; v1 returned 0.5-2x, v2 levied 0.5-2x, v3 shortfall share <= 0.2, v4 |mean s diff| <= 50%)")
    J = Dict{String,Any}()
    for c in ("B-delay", "B-yoke")
        V = [w["validity"][c] for w in W]; nv = count(v -> v["valid"], V)
        say(c, ": valid windows ", nv, "/36; failing v1 ", count(v -> !v["v1"], V), ", v2 ", count(v -> !v["v2"], V), ", v3 ", count(v -> !v["v3"], V),
            ", v4 ", count(v -> !v["v4"], V), ", B-ret denominator 0 ", count(v -> v["den0"], V), ", early death ", count(v -> v["earlyDeath"], V))
        say("   ratios returned/paid ", [round(v["retC"] / max(1, v["paidB"]); digits = 2) for v in V])
        say("   mean s read / B-ret mean s ", [round(v["meanSC"] / max(1e-12, v["meanSB"]); digits = 2) for v in V])
        D = [sum(Z(w, "B-ret", k) - Z(w, c, k) for k in K) for w in W]
        vm = [v["valid"] for v in V]
        s1 = signtest(D[vm]); s2 = signtest(D)
        excl = [(u = W[i]["u"], D = D[i], ZB = [Z(W[i], "B-ret", k) for k in K], ZC = [Z(W[i], c, k) for k in K]) for i in eachindex(W) if !vm[i]]
        dir(s) = sign(s["pos"] - s["neg"])
        opposite = dir(s1) * dir(s2) < 0
        reserved = nv < 27 || opposite
        say(c, " main D = sum over ", join(K, ","), " (Z_B-ret - Z_ctrl): (1) valid windows only: D>0 ", s1["pos"], ", D<0 ", s1["neg"], ", D=0 ", s1["zero"], ", p ", s1["p"], " -> ", s1["judge"])
        say(c, "   (2) all 36 windows: D>0 ", s2["pos"], ", D<0 ", s2["neg"], ", D=0 ", s2["zero"], ", p ", s2["p"], " -> ", s2["judge"])
        say(c, "   (3) excluded windows (u, D, Z_B-ret by class, Z_ctrl by class): ", join(["u$(e.u) D=$(e.D) B$(e.ZB) C$(e.ZC)" for e in excl], "; "))
        say(c, "   attribution reserved: ", reserved, " (valid < 27: ", nv < 27, ", (1)/(2) directions opposite: ", opposite, ")")
        for k in K
            d = [Z(w, "B-ret", k) - Z(w, c, k) for w in W]
            say(c, "   class ", k, " (all 36): B-ret wins ", count(>(0), d), ", losses ", count(<(0), d), ", ties ", count(==(0), d),
                "; valid only: ", count(i -> vm[i] && d[i] > 0, eachindex(d)), "/", count(i -> vm[i] && d[i] < 0, eachindex(d)), "/", count(i -> vm[i] && d[i] == 0, eachindex(d)))
        end
        d0 = [Z(w, "B-ret", "0") - Z(w, c, "0") for w in W]
        s0 = signtest(d0); s0v = signtest(d0[vm])
        say(c, "   class 0 (no perturbation) same quantity: all 36 D>0 ", s0["pos"], " D<0 ", s0["neg"], " p ", s0["p"], " -> ", s0["judge"],
            "; valid only ", s0v["pos"], "/", s0v["neg"], " -> ", s0v["judge"])
        J[c] = Dict("nvalid" => nv, "valid" => s1, "all" => s2, "reserved" => reserved, "opposite" => opposite, "class0" => s0, "class0valid" => s0v,
                    "win" => !reserved && s1["judge"] == "win", "loss" => s1["judge"] == "loss")
    end
    qual = J["B-delay"]["win"] && J["B-yoke"]["win"]
    say("qualification (B-ret wins against both controls on their valid windows, not reserved): ", qual)
    say("== descriptive (not test N; all 36 windows)")
    armsD = ("A-ret", "AB-free", "AB-ret", "B-ret", "B-delay", "B-yoke")
    rate = Dict{String,Float64}()
    for arm in armsD
        zs = [Z(w, arm, k) for w in W for k in K]; rate[arm] = sum(zs) / length(zs)
        z0 = [Z(w, arm, "0") for w in W]
        rr(c) = [w["runs"][arm*" "*c] for w in W]
        say(rpad(arm, 8), ": in-band survival T after tp (classes ", join(K, ","), ") ", round(rate[arm]; digits = 3), " (", sum(zs), "/", length(zs), "), class 0 ", sum(z0), "/36",
            "; alive at tp+T by class a/b/c/0 ", [count(x -> x["aliveTT"], rr(c)) for c in CLASSES],
            "; alive out of band ", [count(x -> x["aliveOutOfBand"], rr(c)) for c in CLASSES],
            "; alive at end ", [count(x -> x["aliveEnd"], rr(c)) for c in CLASSES])
        x0 = rr("0")
        say("          class 0 from T0: mean kept ", round(sum(x["meanKept"] === nothing ? 0.0 : x["meanKept"] for x in x0) / 36; digits = 2),
            ", used ", sum(x["all"]["nused"] for x in x0), ", tried ", sum(x["all"]["ntried"] for x in x0), ", paid/returned ", sum(x["all"]["npaid"] for x in x0),
            ", unpaid (used - paid) ", sum(x["all"]["unpaidUsed"] for x in x0), ", unpaid (tried - paid) ", sum(x["all"]["unpaidTried"] for x in x0),
            ", levied ", round(sum(x["all"]["ded"] for x in x0); digits = 4), ", shortfall ", round(sum(x["all"]["short"] for x in x0); digits = 6),
            ", vanished ", sum(x["nvanish"] for x in x0), ", re-formed within FORGET ", sum(x["nreform"] for x in x0))
    end
    ksd(arm) = (v = [w["runs"][arm*" 0"]["keptSteps"] for w in W if !isempty(w["runs"][arm*" 0"]["keptSteps"])]; isempty(v) ? Int[] : sum(v))
    kb = ksd("B-ret"); ka = ksd("A-ret")
    if length(kb) == length(ka) && !isempty(ka)
        dk = kb .- ka; ord = sortperm(abs.(dk); rev = true)[1:min(8, length(dk))]
        say("kept steps per edge, B-ret - A-ret (class 0, summed over windows), largest: ", join(["e$(k): $(dk[k])" for k in ord], ", "))
    end
    say("== secondary (selected after the perturbation; pairs not matched; not used for the judgment)")
    for arm in ("B-ret", "B-delay", "B-yoke", "A-ret")
        xs = [w["runs"][arm*" "*k] for w in W for k in K]; o = filter(x -> x["outEarly"] == true, xs)
        say(rpad(arm, 8), ": out of the band in tp..tp+299 ", length(o), "/", length(xs), ", of which Z = 1: ", count(x -> x["Z"] == 1, o))
    end
    for c in ("B-delay", "B-yoke")
        say("windows x classes where only one of B-ret / ", c, " left the band: ", count(w -> count(k -> (w["runs"]["B-ret "*k]["outEarly"] == true) != (w["runs"][c*" "*k]["outEarly"] == true), K) > 0, W),
            " windows (", sum(count(k -> (w["runs"]["B-ret "*k]["outEarly"] == true) != (w["runs"][c*" "*k]["outEarly"] == true), K) for w in W), " window-classes)")
    end
    say("== predictions")
    pn0 = all(G["summary"][k] for k in ("R1", "R2", "R3", "R4", "R5"))
    say("PN0 (R1-R5 hold): ", pn0 ? "holds" : "fails")
    pn1 = P["p1"] && P["p2"] && P["p3"]["a"] && P["p3"]["b"] && !P["p3"]["c"]
    say("PN1 (p1, p2 hold; p3 holds for a, b and not for c): ", pn1 ? "holds" : "fails", "  (p1 ", P["p1"], ", p2 ", P["p2"], ", p3 ", P["p3"], ")")
    pn2 = J["B-delay"]["nvalid"] >= 27 && J["B-yoke"]["nvalid"] < 27
    say("PN2 (delay valid >= 27, yoke valid < 27): ", pn2 ? "holds" : "fails", "  (", J["B-delay"]["nvalid"], ", ", J["B-yoke"]["nvalid"], ")")
    dl = J["B-delay"]["valid"]["judge"]
    pn3 = !qual && dl in ("undetectable", "not significant") && !J["B-delay"]["loss"] && !J["B-yoke"]["loss"]
    say("PN3 (no qualification; B-ret vs delay undetectable or not significant; B-ret does not lose significantly): ", pn3 ? "holds" : "fails",
        "  (qualification ", qual, ", delay ", dl, ", yoke ", J["B-yoke"]["valid"]["judge"], ")")
    pn4 = rate["AB-free"] >= rate["A-ret"] && rate["AB-ret"] >= rate["B-ret"] && rate["B-ret"] < rate["A-ret"]
    say("PN4 (AB-free >= A-ret, AB-ret >= B-ret, B-ret < A-ret; kept classes, all 36): ", pn4 ? "holds" : "fails",
        "  (A-ret ", round(rate["A-ret"]; digits = 3), ", AB-free ", round(rate["AB-free"]; digits = 3), ", AB-ret ", round(rate["AB-ret"]; digits = 3), ", B-ret ", round(rate["B-ret"]; digits = 3), ")")
    rf(arm) = sum(w["runs"][arm*" 0"]["nreform"] for w in W)
    pn5 = rf("B-ret") > rf("A-ret")
    say("PN5 (re-formations within FORGET: B-ret > A-ret; class 0, T0..end, 36 windows): ", pn5 ? "holds" : "fails", "  (B-ret ", rf("B-ret"), ", A-ret ", rf("A-ret"), ")")
    write(joinpath(OUTDIR, "eval-judgment.json"), JSON.json(Dict("J" => J, "qual" => qual, "rate" => rate, "PN" => [pn0, pn1, pn2, pn3, pn4, pn5]), 2))
    write(joinpath(EXP, "results-bret-eval.out"), join(GL, "\n") * "\nwall $(round(time() - t0; digits = 1)) s, threads $(Threads.nthreads())\n")
end

# ---------------- facts for the next spec (coordinator 2026-11-16; pilot windows only, A-ret and B-ret, class 0; descriptive) ----------------
function facts()
    okF, _ = freeze_ok(); okF || error("spec or predictions differ from freeze 2")
    code_ok() || error("code differs from freeze-bret-norm-code.txt")
    jobs = [(arm, u) for arm in ("A-ret", "B-ret") for u in PILOT]
    rs = tmap(jobs) do (arm, u); run_one(arm, "0", u; extra = (TRACE = true,)); end
    q(v) = isempty(v) ? "-" : string(round(minimum(v); sigdigits = 4), " / ", round(med(v); sigdigits = 4), " / ", round(maximum(v); sigdigits = 4))
    say("S58 facts, pilot windows ", PILOT, ", class 0, steps T0..tp-1 alive (head of step). Amounts in units of KC = ", KC, " per step (means).")
    say("arm u | bind in | metab | turnover | B of dying places | upkeep | act cost | repayment | sum B (KC) min/med/max | kept min/med/max | judged per step mean/max (sg>=1 mean/max) | share used in previous 100 (all / sg>=1) | sg decrements | max used | death")
    for (i, (arm, u)) in enumerate(jobs)
        res, R = rs[i]; ts = [t for t in T0:R.tp-1 if R.alive[t+1]]
        isempty(ts) && (say(arm, " u", u, ": dead before T0"); continue)
        tr = res["trace"]; m(v) = sum(v) / length(ts) / KC
        J = R.judged[:, [t + 1 for t in ts]]
        sj = sum(J[1, :]); ss = sum(J[2, :])
        say(arm, " u", u, " | ", round(m(R.acc[3, t+1] for t in ts); digits = 3), " | ", round(m(R.acc[1, t+1] for t in ts); digits = 3), " | ", round(m(R.acc[2, t+1] for t in ts); digits = 3),
            " | ", round(m(R.acc[4, t+1] for t in ts); digits = 3), " | ", round(m(tr[t+1][3] for t in ts); digits = 3), " | ", round(m(tr[t+1][2] for t in ts); digits = 3),
            " | ", round(m(R.ded[t+1] for t in ts); digits = 3), " | ", q([R.sumB[t+1] / KC for t in ts]), " | ", q([R.kept[t+1] for t in ts if R.kept[t+1] >= 0]),
            " | ", round(sj / length(ts); digits = 3), "/", maximum(J[1, :]), " (", round(ss / length(ts); digits = 3), "/", maximum(J[2, :]), ")",
            " | ", sj == 0 ? "-" : round(sum(J[3, :]) / sj; digits = 3), " / ", ss == 0 ? "-" : round(sum(J[4, :]) / ss; digits = 3),
            " | ", sum(R.lastsg[t+1] for t in ts), " | ", maximum(R.nused[t+1] for t in ts), " | ", res["death"])
    end
    say("== A-ret before its death (every 50 steps from death - 300): step, body size, sum B (KC), kept")
    for (i, (arm, u)) in enumerate(jobs)
        res, R = rs[i]; d = res["death"]
        (arm == "A-ret" && d !== nothing && d < R.tp) || continue
        say("A-ret u", u, " death ", d, ": ", join(["t$(t) n$(R.bsize[t+1]) B$(round(R.sumB[t+1] / KC; digits = 1)) k$(R.kept[t+1])" for t in max(0, d - 300):50:d], ", "))
    end
    mkpath(OUTDIR); write(joinpath(OUTDIR, "facts.out"), join(GL, "\n") * "\n")
end

if abspath(PROGRAM_FILE) == @__FILE__
    mode = length(ARGS) >= 1 ? ARGS[1] : error("mode pilot | eval | facts")
    mode == "pilot" ? pilot() : mode == "eval" ? evaluation() : mode == "facts" ? facts() : error("mode pilot | eval | facts")
end
