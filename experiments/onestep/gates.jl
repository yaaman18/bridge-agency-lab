# S69 gates U1..U11 (discussion/specs/S69-onestep-contract-julia.md r2). Usage (from experiments/):
#   julia --project=.. -t 1 onestep/gates.jl all        run the gates, write onestep/out/gates.out
#   julia --project=.. -t N onestep/gates.jl digest     print the digest of a fixed run (U5, called by the driver)
include(joinpath(@__DIR__, "onestep.jl"))
include(joinpath(@__DIR__, "..", "one_life_resume.jl"))   # ol_drive
const OUT = joinpath(@__DIR__, "out"); mkpath(OUT)
const MODE = length(ARGS) >= 1 ? ARGS[1] : "all"
const SEEDS = (690101, 690102, 690103, 690104)

# deterministic rand_u64 stream (SplitMix64) for the test inputs
function splitmix(seed::UInt64, n::Int)
    x = seed; out = Vector{UInt64}(undef, n)
    for i in 1:n
        x += 0x9e3779b97f4a7c15; z = x
        z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9; z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
        out[i] = z ⊻ (z >> 31)
    end
    return out
end
drive_inputs(n; seed = 1) = (r = splitmix(UInt64(seed), n); [AueInput(ol_drive("D1", t)..., r[t+1]) for t in 0:n-1])

results = Tuple{String,String,String}[]   # (name, "PASS" | "FAIL" | "NOT_RUN", note)
function record(name, status, note)
    push!(results, (name, status, note)); println(rpad(name, 6), rpad(status, 8), note)
end
gate(name, ok::Bool, note = "") = record(name, ok ? "PASS" : "FAIL", note)
not_run(name, note) = record(name, "NOT_RUN", note)

if MODE == "digest"   # U5 (called in separate processes with -t 1 and -t 8)
    s = aue_birth(SEEDS[1], LawL2, TracePred()); r = run_audited(s, drive_inputs(2000; seed = 5))
    println(bytes2hex(sha256(join(r.lines, "\n") * aue_digest(r.state)))); exit(0)
end

const N = 2000
const BP_DIR = joinpath(homedir(), "bridge-protocol")
const BP_HEAD0 = strip(read(Cmd(`git rev-parse HEAD`; dir = BP_DIR), String)); const BP_STATUS0 = read(Cmd(`git status --short`; dir = BP_DIR), String)

# ---------- U1: the copy equals core's onelife_step when no draw hook is given ----------
function u1()
    ok = true; note = String[]
    for law in (LawL2, LawL2SF), seed in SEEDS[1:2]
        c = onelife_birth(seed, law); a = AueState(onelife_birth(seed, law), NullPred()); bad = 0
        for t in 0:N-1
            g = ol_drive("D1", t)
            c, _ = onelife_step(c, g)
            a, _ = aue_step(a, AueInput(g..., 0x0); use_draw = false)
            onelife_save(c) == onelife_save(a.life) || (bad += 1; bad == 1 && push!(note, "first diff law=$(law) seed=$seed t=$t"))
        end
        ok &= bad == 0
    end
    # negative control: one rounding changed in the copy (the cost constant by one ulp) must be detected
    mut = f -> rep1(f, "cost = KC * nk;", "cost = (KC * nk) * (1.0 + 2.0^-20);")
    Core.eval(Main, Meta.parse(_live_source("_live_neg"; mutate = mut)))
    c = onelife_birth(SEEDS[1], LawL2); a = AueState(onelife_birth(SEEDS[1], LawL2), NullPred()); caught = false
    for t in 0:N-1
        g = ol_drive("D1", t); c, _ = onelife_step(c, g)
        a, _ = aue_step(a, AueInput(g..., 0x0); use_draw = false, live = Main._live_neg)
        if onelife_save(c) != onelife_save(a.life); caught = true; break; end
    end
    gate("U1", ok && caught, "2 laws x 2 seeds x $N steps bit-identical to onelife_step: $ok; negative control (cost x (1+2^-20)) caught: $caught $(join(note, "; "))")
end

# ---------- U2: no leak of the current step's drive ----------
struct LeakPred <: Pred end
const PEEK = Ref(0.0)
predict(::LeakPred, R) = (LeakPred(), clamp(0.5 + 0.4 * PEEK[], 0.01, 0.99), 1 - clamp(0.5 + 0.4 * PEEK[], 0.01, 0.99))
update(p::LeakPred, a, ans) = p
pred_bytes(::LeakPred) = UInt8[0x02]
function u2()
    nex = 25; same = 0; sens = 0; used = 0; leak_caught = 0
    for ex in 1:nex
        s = aue_birth(690200 + ex, LawL2, TracePred()); rs = splitmix(UInt64(ex), 400)
        for t in 0:399
            g = ol_drive("D1", t); inp = AueInput(g..., rs[t+1])
            if t >= 300
                a, ra = aue_step(s, inp); b, rb = aue_step(s, AueInput(5 - g[1], 5 - g[2], rs[t+1]))   # the current drive flipped
                if ra.drawn
                    used += 1
                    same += (ra.p1 === rb.p1 && ra.p2 === rb.p2 && ra.pi1 === rb.pi1 && ra.patch == rb.patch) ? 1 : 0
                    sens += (aue_digest(a) != aue_digest(b)) ? 1 : 0
                    PEEK[] = g[1] / 5; sl = AueState(s.life, LeakPred()); _, la = aue_step(sl, inp)   # negative control: a predictor that reads the drive
                    PEEK[] = (5 - g[1]) / 5; _, lb = aue_step(sl, inp)
                    leak_caught += (la.p1 !== lb.p1) ? 1 : 0
                    break
                end
            end
            s, _ = aue_step(s, inp)
        end
    end
    gate("U2", used == nex && same == nex && sens >= nex ÷ 2 && leak_caught == nex,
         "$used/$nex examples drew; p,pi,a identical under the flipped drive: $same/$nex; next state differs (test is sensitive): $sens/$nex; LEAK control caught: $leak_caught/$nex")
end

# ---------- U3: replay from the audit text only; a doctored input line is found ----------
function u3()
    inputs = drive_inputs(N; seed = 3)
    r = run_audited(aue_birth(SEEDS[1], LawL2, TracePred()), inputs)
    r2 = run_audited(aue_birth(SEEDS[1], LawL2, TracePred()), parse_inputs(r.lines))
    ok = r2.lines == r.lines && aue_digest(r2.state) == aue_digest(r.state)
    bad = copy(r.lines); k = findfirst(l -> startswith(l, "input 1000 "), bad); f = split(bad[k]); f[3] = string((parse(Int, f[3]) + 1) % 6); bad[k] = join(f, " ")
    r3 = run_audited(aue_birth(SEEDS[1], LawL2, TracePred()), parse_inputs(bad))
    cr = filter(l -> startswith(l, "commit "), r.lines); cr3 = filter(l -> startswith(l, "commit "), r3.lines)
    d = first_diff(cr, cr3)
    gate("U3", ok && d > 0, "replay of $N steps from the text reproduces every line and the final state: $ok; doctored input 1000 (g1+1 mod 6): first differing commit is the #$d one ($(d > 0 ? join(split(cr3[d])[1:2], " ") : "none"))")
end

# ---------- U4: resume from a saved state equals the straight run ----------
function u4()
    inputs = drive_inputs(N; seed = 4); s0 = aue_birth(SEEDS[2], LawL2SF, TracePred())
    full = run_audited(s0, inputs); allok = true; notes = String[]
    for k in (0, 1, 777, 1999)
        pre = run_audited(s0, inputs[1:k]); nl = length(onelife_save(pre.state.life))
        loaded = aue_load(LawL2SF, aue_save(pre.state), nl)
        post = run_audited(loaded, inputs[k+1:end]; start_n = k, prev = pre.last_hash)
        ok = vcat(pre.lines, post.lines) == full.lines && aue_digest(post.state) == aue_digest(full.state)
        allok &= ok; push!(notes, "k=$k:$(ok)")
    end
    gate("U4", allok, join(notes, " "))
end

# ---------- U6: core untouched, input state not mutated, core/check, bridge-protocol ----------
function u6()
    s = aue_birth(SEEDS[3], LawL2, TracePred()); before = aue_save(s)
    for t in 0:200; aue_step(s, AueInput(ol_drive("D1", t)..., 0x1)); end
    nomut = aue_save(s) == before
    dirty = read(Cmd(`git status --short core rust/being-core rust/being-tools rust/trm-det`; dir = OS_LAB), String)
    chk = success(pipeline(Cmd(`sh core/check/run.sh`; dir = OS_LAB); stdout = joinpath(OUT, "core-check.out"), stderr = joinpath(OUT, "core-check.err")))
    bp = joinpath(homedir(), "bridge-protocol")
    bpdiff = read(Cmd(`git diff`; dir = bp), String); bphead = strip(read(Cmd(`git rev-parse HEAD`; dir = bp), String))
    bpsame = bphead == BP_HEAD0 && read(Cmd(`git status --short`; dir = bp), String) == BP_STATUS0   # other processes stage files there; this run changes nothing
    gate("U6", nomut && isempty(dirty) && chk && isempty(bpdiff) && bpsame, "input state not mutated: $nomut; core/rust frozen dirs clean: $(isempty(dirty)); core/check exit 0: $chk; bridge-protocol tracked diff empty: $(isempty(bpdiff)); its HEAD and git status identical before and after this run: $bpsame")
end

# ---------- U8: the drawn action reaches the body ----------
function u8()
    s = aue_birth(SEEDS[1], LawL2, TracePred()); found = 0; okcnt = 0; negcaught = 0; rs = splitmix(UInt64(8), 3000)
    for t in 0:2999
        g = ol_drive("D1", t); inp = AueInput(g..., rs[t+1])
        a, r = aue_step(s, inp)
        if r.drawn && r.patch != r.det_patch && found < 20
            found += 1
            pi1 = 1 / 8 + (3 / 4) * (r.p1 / (r.p1 + r.p2)); act = r.u < pi1 ? 1 : 2        # independent from S66
            acts = onelife_acts(a.life)
            okcnt += (act == r.patch && pi1 == r.pi1 && (r.patch in acts) && !(r.det_patch in acts) && r.ans == ((r.patch == 1 ? r.y1 : r.y2) > 0)) ? 1 : 0
            b, _ = aue_step(s, inp; route_det = true)                                         # negative control: records the draw, acts as DET
            negcaught += (r.patch in onelife_acts(b.life)) ? 0 : 1
        end
        s = a
    end
    gate("U8", found >= 5 && okcnt == found && negcaught == found, "$found fixtures where the draw differs from DET: body acts on the drawn patch only $okcnt/$found; misrouted control caught $negcaught/$found; (next-state bytes are not hand-computed: limit)")
end

# ---------- U10: death step and the call after it ----------
function u10()
    s = aue_birth(SEEDS[4], LawL2, TracePred()); n = 0; rs = splitmix(UInt64(10), 60000); dstep = 0; ncommit = 0
    while n < 60000
        n += 1; s2, r = aue_step(s, AueInput(0, 0, rs[n])); ncommit += r.committed ? 1 : 0; s = s2
        if s.life.dead; dstep = n; break; end
    end
    dead = s.life.dead; st_before = aue_save(s)
    s3, r3 = aue_step(s, AueInput(9, 9, 0x0))        # a drive that would be an error if it were read
    after_ok = dead && !r3.err && !r3.committed && aue_save(s3) == st_before
    gate("U10", dead && after_ok, "starved life (drive 0,0): death detected at call $dstep (t=$(s.life.death)); commits up to and including the detection: $ncommit; call after death with an invalid drive: not read, no error, no commit, state unchanged: $after_ok")
end

# ---------- U11: stale rows ----------
function u11()
    w, b = 330.0, 4.5; ok = true; diffs = 0; ign = 0
    for step in 0:2999
        fresh = c4_yields(step, w, b, false); st = c4_yields(step, w, b, true)
        x1 = (2.5 + 2.5 * SIN_TABLE_1000[(step % 1000) + 1]); x2 = (2.5 + 2.5 * SIN_TABLE_1000[((step + 500) % 1000) + 1])   # z = 0 written out
        e = (Int(clamp(round(x1, RoundNearest), 0.0, 5.0)), Int(clamp(round(x2, RoundNearest), 0.0, 5.0)))
        ok &= st == e
        diffs += fresh != st
        ign += c4_yields(step, w, b, true; honor_stale = false) != st
    end
    gate("U11", ok && diffs > 0 && ign > 0, "stale rows give the z=0 yields over 3000 steps: $ok; differs from a fresh row on $diffs steps; the variant ignoring stale differs on $ign steps (caught). Scope: the predictor does not read the radio, so the window/head are untouched by stale in this stage")
end

if MODE == "all"
    for f in (u1, u2, u3, u4, u6, u8, u10, u11); f(); end
    jl = Base.julia_cmd()
    outs = [strip(read(`$jl --project=$(OS_LAB) -t $th $(@__FILE__) digest`, String)) for th in (1, 8, 1)]
    gate("U5", length(unique(outs)) == 1, "digests (1 thread, 8 threads, 1 thread; separate processes): " * join((o[1:12] for o in outs), " "))
    not_run("U7", "NOT RUN: the TRM predictor and B_max are not in this stage (S69 H-S69-2)")
    not_run("U9", "NOT RUN: the C2 head update and its accounting order are not in this stage")
    open(joinpath(OUT, "gates.out"), "w") do io
        for (n, status, note) in sort(results; by = x -> parse(Int, x[1][2:end]))
            println(io, n, "\t", status, "\t", note)
        end
    end
end
