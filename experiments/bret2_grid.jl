# S59 B2-ret measured with test N (discussion/specs/S59-bret2-norm.md r3, which differs from S58 r3 only where it says so;
# predictions-bret2-norm.md r1; freeze-bret2-norm.txt freeze 2). Same world as S58 (synth_world.jl: P = 1000, sigma = 1,
# L = 300, M = 2.5), law L2+SF, 10000 steps, T0 = 800; tp = T0 + 1000 + (u mod 300).
# Rule (spec §1): at a sed_fade decay judgment of edge k (age a multiple of FORGET, not confirmed this step), k is a
# candidate when sg[k] >= 1 just before the judgment and k was used (drove its motor while the motor acted, as SFD) at
# some step in [t - FORGET, t). Arms: A-ret (L2+SF), B2-free (every candidate restored, free), B2-ret (the first s_t
# candidates, from t mod n in edge order, restored and paid KC x FORGET each), B2-delay (s_{t-375}), B2-yoke (the s of a
# B2-ret run with another birth seed in the same window). A restored candidate keeps its sg and lastC = now.
# s_t = floor(min_{body}(B - THETA_EXIST) / (KC FORGET / |body|)), 0 if negative or dead, at the head of step t (after the
# perturbation, before the circuit step). The levy (after the circuit step and the capacity, before the upkeep) takes from
# each place min(the equal share, max(0, B - THETA_EXIST)); a place's new B is computed as max(B - share, THETA_EXIST)
# when B >= THETA_EXIST (the same amount, but no rounding can leave it below the threshold), else B is not touched.
# core/ is not changed: step_bret2! and body_org_run_bret2 are made from the source of core/circuit.jl's step! and
# core/body_org.jl's body_org_run at anchors that must each occur once, and evaluated into LabCore.
# Usage (from experiments/):
#   julia --project=.. -t 8 check_bret2.jl        gates R1-R5 (windows 726-729 of S58, partners 766-769) -> results-bret2-gates.out
#   julia --project=.. -t 8 bret2_grid.jl pilot   pilot windows 806-809 (partners 846-849) -> results-bret2-pilot.out
#   julia --project=.. -t 8 bret2_grid.jl eval    evaluation windows 810-845 (partners 850-885) -> results-bret2-eval.out
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON, SHA
include(joinpath(@__DIR__, "synth_world.jl"))

const LAB = normpath(joinpath(@__DIR__, ".."))
const EXP = joinpath(LAB, "experiments")
const OUTDIR = joinpath(EXP, "bret2-out")
const T0 = 800; const STEPS = 10000
const KC = 0.002; const FORGETN = 100; const COST = KC * FORGETN
const THETA = LabCore.MATTER_DEF.THETA_EXIST
const DELTA = 375; const TBAND = 2000
const BASE = (U = 0.02, MCOST = 0.004, STEPS = STEPS, FEED = true, KC = KC, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true, SEDFADE = true)
const WP = (P = 1000, sigma = 1, L = 300, M = 2.5)
const ARMS = ("A-ret", "B2-free", "B2-ret", "B2-delay", "B2-yoke")
const CLASSES = ("a", "b", "c", "0")
const PCLASSES = ("a", "b", "c")
const PILOT = 806:809; const PILOTP = 846:849
const EVALS = 810:845; const EVALP = 850:885
const GATEW = 726:729; const GATEP = 766:769   # S58's pilot windows, used only by the gates and trial runs
tp_of(u) = T0 + 1000 + mod(u, 300)
function partner_of(u)
    for (W, Pw) in ((PILOT, PILOTP), (EVALS, EVALP), (GATEW, GATEP))
        u in W && return Pw[u-first(W)+1]
    end
    error("no partner for $u")
end

# ---------------- the world, class c ----------------
const TABS = Dict{Int,Matrix{Float64}}(); const TABLOCK = ReentrantLock()
table(u) = lock(() -> get!(() -> synth_table(u, WP.P, WP.sigma, WP.L, WP.M; ns = SW_NS + 150), TABS, u), TABLOCK)
function sched_of(u, cls, tp)
    g = table(u); s0 = tp - T0
    cls == "c" ? ((s, k) -> s >= s0 ? g[s+151, k] : g[s+1, k]) : ((s, k) -> g[s+1, k])
end

# ---------------- step_bret2! ----------------
function rep1(f, anchor, new)
    n = length(findall(anchor, f)); n == 1 || error("anchor occurs $n times: $anchor")
    return replace(f, anchor => new)
end
const CIRCUIT_SRC = read(joinpath(LAB, "core", "circuit.jl"), String)
function step_source(src)
    i = findfirst("function step!(st::CState, b::Circuit, y;", src); i === nothing && error("anchor: function step!")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    f = src[i[1]:j[end]]
    f = rep1(f, "function step!(st::CState, b::Circuit, y;", "function step_bret2!(st::CState, b::Circuit, y;")
    f = rep1(f, "rest_off = false, body_flag = nothing)", "rest_off = false, body_flag = nothing, ret = nothing)")
    a = "        st.lastC === nothing && (st.lastC = zeros(Int, ne))\n"
    f = rep1(f, a, a * "        ret === nothing || Main.b2_select!(ret, b, drove, acting, confirmed, st, now, ne)   # S59 (bret2_grid.jl)\n")
    f = rep1(f, "            if confirmed[k] || (sed_fade_drive && drove[k] && b.edges[k][2] in acting)\n",
                "            if ret === nothing ? (confirmed[k] || (sed_fade_drive && drove[k] && b.edges[k][2] in acting)) : (confirmed[k] || ret.paidmask[k])\n")
    f = rep1(f, "                (a >= FORGET && a % FORGET == 0) && (st.sg[k] = max(st.sg[k] - 1, 0))\n", """
                if a >= FORGET && a % FORGET == 0
                    if ret !== nothing && st.sg[k] == 1
                        ret.lastsg += 1
                    end
                    st.sg[k] = max(st.sg[k] - 1, 0)
                end
""")
    a = "    now % P_FRESH == 0 && (st.fresh"
    f = rep1(f, a, "    (sed_fade && ret !== nothing) && Main.b2_after!(ret, st, now)\n" * a)
    return f
end
const STEP_SRC = step_source(CIRCUIT_SRC)
Core.eval(LabCore, Meta.parse(STEP_SRC))
const step_bret2! = LabCore.step_bret2!

const BODY_ORG_SRC = read(joinpath(LAB, "core", "body_org.jl"), String)
function run_source(src)
    i = findfirst("function body_org_run(cond::String", src); i === nothing && error("anchor: function")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    f = src[i[1]:j[end]]
    f = rep1(f, "function body_org_run(cond::String", "function body_org_run_bret2(cond::String")
    a = "TRACE = _opt(o, :TRACE, false) == true\n"
    f = rep1(f, a, a * "    BR = _opt(o, :BRET)   # S59 (bret2_grid.jl)\n")
    a = "        y = [min(5.0, floor(r / U + 1e-9)) for r in pool]\n"
    f = rep1(f, a, "        BR === nothing || Main.b2_head!(BR, t, w, pool, circuit, noise, alive)\n" * a)
    a = "        if alive && isempty(body); alive = false; death = t; end\n"
    f = rep1(f, a, a * "        BR === nothing || Main.b2_s!(BR, t, w, body, alive)\n")
    f = rep1(f, "            out = step!(circuit, b, [yin[1], yin[2], 0.0]; ",
                "            BR === nothing || Main.b2_pre!(BR, t, w, body)\n            out = step_bret2!(circuit, b, [yin[1], yin[2], 0.0]; ")
    f = rep1(f, "sil = silset)\n", "sil = silset, ret = (BR === nothing ? nothing : BR.ret))\n")
    a = "        if alive && cond == \"ORG\" && KC != 0\n"
    f = rep1(f, a, "        BR === nothing || Main.b2_bill!(BR, t, w, body, alive, circuit, blocked + lost)\n" * a)
    return f
end
Core.eval(LabCore, Meta.parse(run_source(BODY_ORG_SRC)))
const body_org_run_bret2 = LabCore.body_org_run_bret2

# ---------------- the rule (spec §1) ----------------
# Pure functions (also tested by hand in check_bret2.jl). lastUse[k] = the last step < t at which k was used.
function b2_judged(ne, confirmed, lastC, now)
    return [k for k in 1:ne if !confirmed[k] && (now - lastC[k]) >= FORGETN && (now - lastC[k]) % FORGETN == 0]
end
b2_cand(judged, sg, lastUse, t) = [k for k in judged if sg[k] >= 1 && lastUse[k] < t && t - lastUse[k] <= FORGETN]
function b2_pay(cand, t, allow, mode)
    mode == :A && return Int[]
    mode == :B2free && return copy(cand)
    n = length(cand); rot = [cand[mod(t + j, n)+1] for j in 0:n-1]
    return rot[1:min(max(allow, 0), n)]
end
mutable struct BRet
    mode::Symbol          # :A, :B2free, :B2
    t::Int; allow::Int; ran::Bool; nouse::Bool
    lastUse::Vector{Int}
    used::Vector{Int}; judged::Vector{Int}; sgBefore::Vector{Int}; cand::Vector{Int}; paid::Vector{Int}; paidmask::BitVector
    sgAfter::Vector{Int}; lcAfter::Vector{Int}; lastsg::Int
end
BRet() = BRet(:A, -1, 0, false, false, Int[], Int[], Int[], Int[], Int[], Int[], falses(0), Int[], Int[], 0)
function b2_select!(r::BRet, b, drove, acting, confirmed, st, now, ne)
    isempty(r.lastUse) && (r.lastUse = fill(-10^9, ne))
    r.used = [k for k in 1:ne if drove[k] && b.edges[k][2] in acting]
    r.judged = b2_judged(ne, confirmed, st.lastC, now)
    r.sgBefore = [st.sg[k] for k in r.judged]
    r.cand = b2_cand(r.judged, st.sg, r.lastUse, r.t)
    r.paid = b2_pay(r.cand, r.t, r.allow, r.mode)
    r.paidmask = falses(ne); r.paidmask[r.paid] .= true
    if !r.nouse
        for k in r.used; r.lastUse[k] = r.t; end   # after the judgment: the use at t counts from t + 1
    end
    return nothing
end
function b2_after!(r::BRet, st, now)
    r.sgAfter = [st.sg[k] for k in r.judged]; r.lcAfter = [st.lastC[k] for k in r.judged]
    return nothing
end

# ---------------- the run object and the body hooks ----------------
mutable struct BRun
    arm::String; cls::String; u::Int; tp::Int; delta::Int
    partner::Union{Nothing,Vector{Int}}
    brk::Symbol            # :none, or a deliberate fault for a negative control (check_bret2.jl)
    ret::BRet
    s::Vector{Int}; sread::Vector{Int}; nused::Vector{Int}; ncand::Vector{Int}; npaid::Vector{Int}; njudged::Vector{Int}
    ded::Vector{Float64}; short::Vector{Float64}; broke::Vector{Int}
    bsize::Vector{Int}; alive::Vector{Bool}; r5::Vector{Bool}; lastsg::Vector{Int}; capn::Vector{Int}; ran::Vector{Bool}
    minrem::Vector{Float64}; kept::Vector{Int}
    headB::Vector{Float64}; headBody::Vector{Int}
    pre::Any; pert::Any
    log::Union{Nothing,Vector{Any}}   # per step (t, judged, sgBefore, cand, paid, sgAfter, lcAfter, lastUse before, confirmed, allow, keptAfterCap)
    prevkept::Union{Nothing,BitVector}; vanT::Vector{Int}; nvanish::Int; nreform::Int
end
function BRun(arm, cls, u; tp = tp_of(u), delta = DELTA, partner = nothing, brk = :none, log = false)
    z(T) = zeros(T, STEPS)
    R = BRun(arm, cls, u, tp, delta, partner, brk, BRet(), z(Int), fill(-1, STEPS), z(Int), z(Int), z(Int), z(Int), z(Float64), z(Float64), z(Int),
             z(Int), fill(false, STEPS), fill(true, STEPS), z(Int), z(Int), fill(false, STEPS), fill(NaN, STEPS), fill(-1, STEPS), Float64[], Int[],
             nothing, nothing, log ? Any[] : nothing, nothing, Int[], 0, 0)
    R.ret.nouse = brk == :nouse
    return R
end
const port_give! = LabCore.port_give!
function perturb!(R::BRun, t, w, circuit)
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
function b2_head!(R::BRun, t, w, pool, circuit, noise, alive)
    t == R.tp && (R.pre = deepcopy((w = w, pool = pool, circuit = circuit, noise = noise, alive = alive)))
    tpert = R.brk == :r4 ? R.tp - 1 : R.tp
    (t == tpert && alive && R.brk != :r5) && perturb!(R, t, w, circuit)
    return nothing
end
function b2_s!(R::BRun, t, w, body, alive)
    R.alive[t+1] = alive; R.bsize[t+1] = length(body)
    if alive && !isempty(body)
        m = minimum(w.B[i] - THETA for i in body); R.minrem[t+1] = m
        R.s[t+1] = max(0, floor(Int, m / (COST / length(body))))
    else
        R.s[t+1] = 0
    end
    R.headB = copy(w.B); R.headBody = copy(body)
    return nothing
end
function b2_pre!(R::BRun, t, w, body)
    r = R.ret; r.t = t; r.ran = true; r.lastsg = 0
    if t < T0 || R.arm == "A-ret"
        r.mode = :A; r.allow = 0
    elseif R.arm == "B2-free"
        r.mode = :B2free; r.allow = 0
    else
        r.mode = :B2
        if R.arm == "B2-ret"
            r.allow = R.s[t+1]
        elseif R.arm == "B2-delay"
            lag = R.brk == :r3 ? R.delta + 1 : R.delta
            r.allow = t < T0 + R.delta ? R.s[t+1] : R.s[t-lag+1]
        elseif R.arm == "B2-yoke"
            r.allow = R.partner[t+1]
        else
            error("arm $(R.arm)")
        end
        R.sread[t+1] = r.allow
    end
    (R.brk == :r5 && t == R.tp) && perturb!(R, t, w, nothing)   # fault: the class-a cut between the head and the levy
    return nothing
end
function b2_bill!(R::BRun, t, w, body, alive, circuit, capn)
    r = R.ret
    R.r5[t+1] = isequal(w.B, R.headB) && R.headBody == body && body == [i for i in eachindex(w.C) if w.C[i] != 0]
    R.capn[t+1] = capn
    if r.ran
        R.ran[t+1] = true
        R.nused[t+1] = length(r.used); R.njudged[t+1] = length(r.judged); R.ncand[t+1] = length(r.cand); R.npaid[t+1] = length(r.paid)
        R.lastsg[t+1] = r.lastsg
        n = length(r.paid)
        if alive && n > 0 && r.mode == :B2
            nb = R.brk == :r2 ? n + 1 : n
            d = COST * nb / length(body); paid = 0.0; short = 0.0; broke = 0
            for i in body
                b0 = w.B[i]
                if R.brk == :nofloor   # fault for a negative control: S58's levy (down to 0)
                    m = min(d, b0); w.B[i] -= m
                elseif b0 >= THETA
                    nbv = max(b0 - d, THETA); m = b0 - nbv; w.B[i] = nbv
                else
                    m = 0.0
                end
                paid += m; short += d - m
                (b0 >= THETA && w.B[i] < THETA) && (broke += 1)
            end
            paid > 0 && port_give!(w.port, paid)
            R.ded[t+1] = paid; R.short[t+1] = short; R.broke[t+1] = broke
        end
        if R.log !== nothing
            kc = circuit === nothing ? Bool[] : [circuit.q[k] >= 1 || circuit.sg[k] >= 1 for k in r.paid]
            push!(R.log, (t = t, judged = copy(r.judged), sgBefore = copy(r.sgBefore), cand = copy(r.cand), paid = copy(r.paid),
                          sgAfter = copy(r.sgAfter), lcAfter = copy(r.lcAfter), allow = r.allow, mode = r.mode, keptPaid = kc, used = copy(r.used)))
        end
        r.ran = false
    end
    if alive && circuit !== nothing && t >= T0
        ne = length(circuit.q)
        kept = BitVector([circuit.q[k] >= 1 || circuit.sg[k] >= 1 for k in 1:ne]); R.kept[t+1] = count(kept)
        if R.prevkept === nothing
            R.vanT = fill(-1, ne)
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
        R.prevkept = kept
    end
    return nothing
end

# ---------------- runs ----------------
run_opts(u, cls, R; extra = (;)) = merge(BASE, (SCHED = sched_of(u, cls, R.tp), REPORT = true, BRET = R), extra)
function run_one(arm, cls, u; seed = u, partner = nothing, delta = DELTA, brk = :none, log = false, extra = (;))
    R = BRun(arm, cls, u; delta = delta, partner = partner, brk = brk, log = log)
    res = body_org_run_bret2("ORG", seed, run_opts(u, cls, R; extra = extra))
    return res, R
end

# ---------------- summaries (S58 r3 §5, S59 §6) ----------------
alive_at(r, t) = r["death"] === nothing || r["death"] > t
inb(R, t, bd) = R.alive[t+1] && bd[1] <= R.bsize[t+1] <= bd[2]
med(v) = (w = sort(v); n = length(w); isodd(n) ? w[(n+1)÷2] : (w[n÷2] + w[n÷2+1]) / 2)
function summary(res, R::BRun)
    tp = R.tp; pre = alive_at(res, tp - 1)
    bd = pre ? (minimum(R.bsize[tp-300+1:tp]), maximum(R.bsize[tp-300+1:tp])) : nothing
    outEarly = pre ? any(t -> !inb(R, t, bd), tp:tp+299) : nothing
    aliveTT = alive_at(res, tp + TBAND)
    Z = pre && aliveTT && all(t -> inb(R, t, bd), tp+TBAND-300:tp+TBAND-1) ? 1 : 0
    sums(rg) = Dict("nused" => sum(R.nused[rg]), "njudged" => sum(R.njudged[rg]), "ncand" => sum(R.ncand[rg]), "npaid" => sum(R.npaid[rg]),
                    "unpaid" => sum(R.ncand[rg]) - sum(R.npaid[rg]), "ded" => sum(R.ded[rg]), "short" => sum(R.short[rg]),
                    "stepsCand" => count(>(0), R.ncand[rg]), "stepsPaid" => count(>(0), R.npaid[rg]), "stepsUnpaid" => count(i -> R.ncand[i] > R.npaid[i], rg))
    ts = [t for t in T0:tp-1 if R.alive[t+1]]
    Dict{String,Any}("arm" => R.arm, "cls" => R.cls, "u" => R.u, "tp" => tp, "death" => res["death"], "aliveTp" => pre && R.alive[tp+1],
        "band" => bd === nothing ? nothing : [bd[1], bd[2]], "outEarly" => outEarly, "aliveTT" => aliveTT, "Z" => Z,
        "aliveOutOfBand" => aliveTT && Z == 0, "aliveEnd" => res["death"] === nothing,
        "pre" => sums(T0+1:tp), "post" => sums(tp+1:min(STEPS, tp + TBAND)), "all" => sums(T0+1:STEPS),
        "sPre" => isempty(ts) ? nothing : (v = [R.s[t+1] for t in ts]; [minimum(v), med(v), maximum(v)]),
        "minremPre" => isempty(ts) ? nothing : (v = [R.minrem[t+1] for t in ts]; [minimum(v), med(v), maximum(v)]),
        "stepsS0Pre" => count(t -> R.s[t+1] == 0, ts),
        "nvanish" => R.nvanish, "nreform" => R.nreform, "meanKept" => (v = filter(>=(0), R.kept[T0+1:end]); isempty(v) ? nothing : sum(v) / length(v)),
        "lastsg" => sum(R.lastsg), "keptEnd" => res["keptEnd"])
end
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
    return Dict{String,Any}("valid" => !early && !den0 && v1 && v2 && v3 && v4, "v1" => v1, "v2" => v2, "v3" => v3, "v4" => v4, "den0" => den0,
        "earlyDeath" => early, "nsteps" => length(ts), "paidB" => pB, "retC" => pC, "dedB" => dB, "dedC" => dC, "shortC" => sC, "meanSB" => mB, "meanSC" => mC)
end
function window(u)
    p = partner_of(u); out = Dict{String,Any}("u" => u, "partner" => p, "tp" => tp_of(u))
    part = Dict{String,Any}(); runs = Dict{String,Any}(); keep = Dict{String,Any}()
    for cls in CLASSES
        res, R = run_one("B2-ret", cls, u; seed = p)
        part[cls] = summary(res, R); keep["partner "*cls] = R.s
    end
    for arm in ARMS, cls in CLASSES
        res, R = run_one(arm, cls, u; partner = arm == "B2-yoke" ? keep["partner "*cls] : nothing)
        runs[arm*" "*cls] = summary(res, R)
        cls == "0" && arm in ("B2-ret", "B2-delay", "B2-yoke") && (keep[arm] = (res, R))
    end
    out["partnerRuns"] = part; out["runs"] = runs
    rb, Rb = keep["B2-ret"]
    out["validity"] = Dict(c => validity(Rb, rb, keep[c][2], keep[c][1]) for c in ("B2-delay", "B2-yoke"))
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
    for l in eachline(joinpath(EXP, "freeze-bret2-norm.txt"))
        startswith(l, "S59 freeze 2") && (inblk = true; empty!(ref))
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        (inblk && m !== nothing) && (ref[m.captures[2]] = m.captures[1])
    end
    return length(ref) == 2 && all(sha(joinpath(LAB, f)) == h for (f, h) in ref), ref
end
const CODEFILES = ["experiments/bret2_grid.jl", "experiments/check_bret2.jl", "experiments/synth_world.jl", "core/LabCore.jl", "core/jsmath.jl",
                   "core/circuit.jl", "core/life.jl", "core/matter.jl", "core/evo.jl", "core/body_org.jl", "core/dc.jl"]
function code_ok()
    fz = joinpath(EXP, "freeze-bret2-norm-code.txt"); isfile(fz) || return false
    ref = Dict{String,String}()
    for l in eachline(fz)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l); m === nothing || (ref[m.captures[2]] = m.captures[1])
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
q3(v) = v === nothing ? "-" : string(round.(v; sigdigits = 4))

# ---------------- pilot (S58 r3 §6 with S59 §4) ----------------
function pilot()
    okF, _ = freeze_ok(); okF || error("spec or predictions differ from freeze 2 of freeze-bret2-norm.txt")
    code_ok() || error("code differs from freeze-bret2-norm-code.txt")
    G = JSON.parsefile(joinpath(EXP, "results-bret2-gates.json")); all(G["summary"][k] for k in ("F", "R1", "R2", "R3", "R4", "R5")) || error("gates not passed")
    t0 = time()
    W = tmap(window, collect(PILOT))
    mkpath(OUTDIR)
    open(joinpath(OUTDIR, "pilot-windows.jsonl"), "w") do io; for w in W; println(io, JSON.json(w)); end; end
    say("S59 pilot, windows ", PILOT, " (partners ", PILOTP, "), tp = ", [w["tp"] for w in W])
    p1 = true
    for arm in ARMS
        n = count(w -> w["runs"][arm*" 0"]["aliveTp"], W)
        say("p1 ", rpad(arm, 8), ": alive at tp in ", n, "/4 windows   deaths ", [w["runs"][arm*" 0"]["death"] for w in W])
        p1 = p1 && n >= 3
    end
    say("p1: ", p1)
    nok = 0
    for w in W
        x = w["runs"]["B2-ret 0"]["pre"]
        ok = x["ncand"] >= 10 && x["unpaid"] >= 3 && x["npaid"] >= 3; ok && (nok += 1)
        say("p2 u", w["u"], " B2-ret T0..tp-1: candidates ", x["ncand"], " (steps ", x["stepsCand"], "), unpaid ", x["unpaid"], " (steps ", x["stepsUnpaid"],
            "), paid ", x["npaid"], " (steps ", x["stepsPaid"], ") -> ", ok)
    end
    p2 = nok >= 3
    say("p2: windows meeting ", nok, "/4 -> ", p2)
    keepc = String[]; p3 = Dict{String,Any}()
    for c in PCLASSES
        n = count(w -> w["runs"]["B2-ret "*c]["outEarly"] == true, W)
        p3[c] = n >= 2; p3[c] && push!(keepc, c)
        say("p3 class ", c, ": B2-ret out of the band in tp..tp+299 in ", n, "/4 windows -> ", p3[c] ? "kept" : "dropped")
    end
    stop = !(p1 && p2) || isempty(keepc)
    "c" in keepc || say("note: class (c) is dropped; the claim does not include the class the design of M does not anticipate")
    say("== facts (B2-ret class 0, T0..tp-1 alive steps; descriptive)")
    for w in W
        x = w["runs"]["B2-ret 0"]
        say("u", w["u"], ": judged ", x["pre"]["njudged"], ", s_t min/median/max ", q3(x["sPre"]), " (steps with s = 0: ", x["stepsS0Pre"], "), smallest place remainder B - 0.2 min/median/max ", q3(x["minremPre"]))
    end
    say("pilot decision: ", stop ? "STOP (cannot be measured; the evaluation is not run)" : "go, classes kept " * join(keepc, ","))
    out = Dict{String,Any}("p1" => p1, "p2" => p2, "p2windows" => nok, "p3" => p3, "kept" => keepc, "stop" => stop, "wall" => time() - t0)
    write(joinpath(EXP, "results-bret2-pilot.json"), JSON.json(out, 2))
    write(joinpath(EXP, "results-bret2-pilot.out"), join(GL, "\n") * "\nwall $(round(time() - t0; digits = 1)) s, threads $(Threads.nthreads())\n")
end

# ---------------- evaluation (S58 r3 §3, §5; S59; predictions PM0-PM4) ----------------
function evaluation()
    okF, _ = freeze_ok(); okF || error("spec or predictions differ from freeze 2 of freeze-bret2-norm.txt")
    code_ok() || error("code differs from freeze-bret2-norm-code.txt")
    P = JSON.parsefile(joinpath(EXP, "results-bret2-pilot.json")); P["stop"] && error("pilot stopped the evaluation")
    G = JSON.parsefile(joinpath(EXP, "results-bret2-gates.json"))
    K = String.(P["kept"])
    t0 = time()
    W = tmap(window, collect(EVALS))
    mkpath(OUTDIR)
    open(joinpath(OUTDIR, "eval-windows.jsonl"), "w") do io; for w in W; println(io, JSON.json(w)); end; end
    Z(w, arm, c) = w["runs"][arm*" "*c]["Z"]
    say("S59 evaluation, windows ", EVALS, " (partners ", EVALP, "), classes kept by the pilot: ", join(K, ","))
    say("== validity (T0..tp-1, both alive; v1 restored 0.5-2x, v2 levied 0.5-2x, v3 shortfall share <= 0.2, v4 |mean s diff| <= 50%)")
    J = Dict{String,Any}()
    for c in ("B2-delay", "B2-yoke")
        V = [w["validity"][c] for w in W]; nv = count(v -> v["valid"], V)
        say(c, ": valid windows ", nv, "/36; failing v1 ", count(v -> !v["v1"], V), ", v2 ", count(v -> !v["v2"], V), ", v3 ", count(v -> !v["v3"], V),
            ", v4 ", count(v -> !v["v4"], V), ", B2-ret denominator 0 ", count(v -> v["den0"], V), ", early death ", count(v -> v["earlyDeath"], V))
        D = [sum(Z(w, "B2-ret", k) - Z(w, c, k) for k in K) for w in W]
        vm = [v["valid"] for v in V]
        s1 = signtest(D[vm]); s2 = signtest(D)
        excl = [(u = W[i]["u"], D = D[i], ZB = [Z(W[i], "B2-ret", k) for k in K], ZC = [Z(W[i], c, k) for k in K]) for i in eachindex(W) if !vm[i]]
        dir(s) = sign(s["pos"] - s["neg"]); opposite = dir(s1) * dir(s2) < 0
        reserved = nv < 27 || opposite
        say(c, " main D = sum over ", join(K, ","), " (Z_B2-ret - Z_ctrl): (1) valid windows: D>0 ", s1["pos"], ", D<0 ", s1["neg"], ", D=0 ", s1["zero"], ", p ", s1["p"], " -> ", s1["judge"])
        say(c, "   (2) all 36 windows: D>0 ", s2["pos"], ", D<0 ", s2["neg"], ", D=0 ", s2["zero"], ", p ", s2["p"], " -> ", s2["judge"])
        say(c, "   (3) excluded windows (u, D, Z_B2-ret by class, Z_ctrl by class): ", join(["u$(e.u) D=$(e.D) B$(e.ZB) C$(e.ZC)" for e in excl], "; "))
        say(c, "   attribution reserved: ", reserved, " (valid < 27: ", nv < 27, ", (1)/(2) directions opposite: ", opposite, ")")
        for k in K
            d = [Z(w, "B2-ret", k) - Z(w, c, k) for w in W]
            say(c, "   class ", k, " (all 36): B2-ret wins ", count(>(0), d), ", losses ", count(<(0), d), ", ties ", count(==(0), d))
        end
        d0 = [Z(w, "B2-ret", "0") - Z(w, c, "0") for w in W]; s0 = signtest(d0)
        say(c, "   class 0 (no perturbation) same quantity: D>0 ", s0["pos"], " D<0 ", s0["neg"], " p ", s0["p"], " -> ", s0["judge"])
        sh(k) = sum(w["runs"][c*" "*k]["post"]["short"] for w in W)
        say(c, "   shortfall (unpaid restorations, KC units): before tp ", round(sum(v["shortC"] for v in V) / KC; digits = 2), ", tp..tp+T by class ", [round(sh(k) / KC; digits = 2) for k in CLASSES])
        J[c] = Dict("nvalid" => nv, "valid" => s1, "all" => s2, "reserved" => reserved, "opposite" => opposite, "class0" => s0,
                    "win" => !reserved && s1["judge"] == "win", "loss" => s1["judge"] == "loss")
    end
    qual = J["B2-delay"]["win"] && J["B2-yoke"]["win"]
    say("qualification (B2-ret wins against both controls on their valid windows, not reserved): ", qual)
    say("== descriptive (not test N; all 36 windows)")
    rate = Dict{String,Float64}()
    for arm in ARMS
        zs = [Z(w, arm, k) for w in W for k in K]; rate[arm] = sum(zs) / length(zs)
        rr(c) = [w["runs"][arm*" "*c] for w in W]; x0 = rr("0")
        say(rpad(arm, 8), ": in-band survival T after tp (", join(K, ","), ") ", round(rate[arm]; digits = 3), " (", sum(zs), "/", length(zs), "), class 0 ", sum(Z(w, arm, "0") for w in W), "/36",
            "; alive at tp+T a/b/c/0 ", [count(x -> x["aliveTT"], rr(c)) for c in CLASSES], "; alive out of band ", [count(x -> x["aliveOutOfBand"], rr(c)) for c in CLASSES],
            "; alive at end ", [count(x -> x["aliveEnd"], rr(c)) for c in CLASSES])
        say("          class 0 from T0: mean kept ", round(sum(x["meanKept"] === nothing ? 0.0 : x["meanKept"] for x in x0) / 36; digits = 2),
            ", candidates ", sum(x["all"]["ncand"] for x in x0), " (steps ", sum(x["all"]["stepsCand"] for x in x0), "), restored ", sum(x["all"]["npaid"] for x in x0),
            ", unpaid ", sum(x["all"]["unpaid"] for x in x0), " (steps ", sum(x["all"]["stepsUnpaid"] for x in x0), "), levied ", round(sum(x["all"]["ded"] for x in x0) / KC; digits = 1),
            " KC, shortfall ", round(sum(x["all"]["short"] for x in x0) / KC; digits = 2), " KC, vanished ", sum(x["nvanish"] for x in x0), ", re-formed within FORGET ", sum(x["nreform"] for x in x0))
    end
    say("== secondary (selected after the perturbation; pairs not matched; not used for the judgment)")
    for arm in ("B2-ret", "B2-delay", "B2-yoke", "B2-free", "A-ret")
        xs = [w["runs"][arm*" "*k] for w in W for k in K]; o = filter(x -> x["outEarly"] == true, xs)
        say(rpad(arm, 8), ": out of the band in tp..tp+299 ", length(o), "/", length(xs), ", of which Z = 1: ", count(x -> x["Z"] == 1, o))
    end
    for c in ("B2-delay", "B2-yoke")
        say("window-classes where only one of B2-ret / ", c, " left the band: ", sum(count(k -> (w["runs"]["B2-ret "*k]["outEarly"] == true) != (w["runs"][c*" "*k]["outEarly"] == true), K) for w in W))
    end
    say("== predictions")
    pm0 = all(G["summary"][k] for k in ("R1", "R2", "R3", "R4", "R5"))
    say("PM0 (R1-R5 hold): ", pm0 ? "holds" : "fails")
    pm1 = P["p1"] && !P["p2"] && P["p3"]["a"] && P["p3"]["b"] && P["p3"]["c"]
    say("PM1 (p1 holds, p2 does not, p3 holds for a, b, c): ", pm1 ? "holds" : "fails", "  (p1 ", P["p1"], ", p2 ", P["p2"], ", p3 ", P["p3"], ")")
    pm2 = J["B2-delay"]["nvalid"] >= 27 && J["B2-yoke"]["nvalid"] < 27
    say("PM2 (delay valid >= 27, yoke valid < 27): ", pm2 ? "holds" : "fails", "  (", J["B2-delay"]["nvalid"], ", ", J["B2-yoke"]["nvalid"], ")")
    pm3 = !qual && !J["B2-delay"]["loss"] && !J["B2-yoke"]["loss"]
    say("PM3 (no qualification; B2-ret does not lose significantly): ", pm3 ? "holds" : "fails",
        "  (qualification ", qual, ", delay ", J["B2-delay"]["valid"]["judge"], ", yoke ", J["B2-yoke"]["valid"]["judge"], ")")
    pm4 = rate["B2-free"] >= rate["B2-ret"] && rate["B2-free"] >= rate["A-ret"]
    say("PM4 (B2-free >= B2-ret and B2-free >= A-ret; kept classes, all 36): ", pm4 ? "holds" : "fails",
        "  (A-ret ", round(rate["A-ret"]; digits = 3), ", B2-free ", round(rate["B2-free"]; digits = 3), ", B2-ret ", round(rate["B2-ret"]; digits = 3), ")")
    write(joinpath(OUTDIR, "eval-judgment.json"), JSON.json(Dict("J" => J, "qual" => qual, "rate" => rate, "PM" => [pm0, pm1, pm2, pm3, pm4]), 2))
    write(joinpath(EXP, "results-bret2-eval.out"), join(GL, "\n") * "\nwall $(round(time() - t0; digits = 1)) s, threads $(Threads.nthreads())\n")
end

if abspath(PROGRAM_FILE) == @__FILE__
    mode = length(ARGS) >= 1 ? ARGS[1] : error("mode pilot | eval")
    mode == "pilot" ? pilot() : mode == "eval" ? evaluation() : error("mode pilot | eval")
end
