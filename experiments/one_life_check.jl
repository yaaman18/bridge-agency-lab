# S48 check (discussion/specs/S48-one-life.md r2 §5-6; predictions-one-life.md, freeze-one-life.txt).
# Gates G2-G7 with their negative controls (smoke only), predictions P1, P3, P4, P5.
# Usage: cd experiments && julia --project=.. one_life_check.jl smoke   (seeds 589-590, N = 10000)
#        cd experiments && julia --project=.. one_life_check.jl main    (seeds 591-600, N = 10000, run once)
#        cd experiments && julia --project=.. one_life_check.jl dev <N> (seeds 589-590, shorter horizon, no files)
include(joinpath(@__DIR__, "one_life_resume.jl"))
using JSON, SHA, Random

const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = ARGS[1]
const N = MODE == "dev" ? parse(Int, ARGS[2]) : 10000
const SEEDS = MODE == "main" ? (591:600) : MODE in ("smoke", "dev") ? (589:590) : error("mode smoke | main | dev <N>")
const LAWS = ("L2", "L2+SF")
const DRIVES = ("D1", "D2")
const TMP = mktempdir()
const LINES = String[]
say(x...) = (s = string(x...); println(s); push!(LINES, s); flush(stdout))

# ---------- the reference (body_org_run) ----------
function ref_opts(law, kind)
    o = (U = 0.02, MCOST = 0.004, STEPS = N, KC = 0.002, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
    law == "L2+SF" && (o = merge(o, (SEDFADE = true,)))
    return merge(o, (FEED = kind == "D1",))
end
# E_t: the end-of-step snapshot taken in place (encoded to bytes at once; the noise as its int32 state), hashed.
function ref_run(seed, law, kind)
    o = ref_opts(law, kind); H = Vector{Vector{UInt8}}(); A = Vector{Vector{Int}}()
    obs(i) = (push!(H, sha256(onelife_inner_bytes(i.circuit, i.b, i.b.perm, state_int32(i.noise), i.w, i.pool))); push!(A, copy(i.acting)))
    r = body_org_run("ORG", seed, merge(o, (ON_STEP = obs,)))
    drive_ok = all(t -> Float64[ol_drive(kind, t)...] == bo_season_at_(t, o), 0:N-1)
    return r["death"], H, A, drive_ok
end
bo_season_at_(t, o) = LabCore.bo_season_at(t, o)

function save_points(d)
    p = Set(floor(Int, k * N / 20) for k in 0:19)
    if d !== nothing; for x in (d, d + 1, d + 2); x <= N && push!(p, x); end; end
    return sort(collect(p))
end

# ---------- P1 (and the saves for P4, P5) ----------
function life_run(seed, law, kind, d, H, A)
    L = ol_law(law); s = onelife_birth(seed, L); pts = save_points(d); want = Set(vcat(pts, N))
    saves = Dict{Int,Vector{UInt8}}(); 0 in want && (saves[0] = onelife_save(s))
    T = d === nothing ? N : d; first_bad = nothing; err_any = false; det_ok = nothing
    for n in 0:N-1
        prev = s
        s, e = onelife_step(s, ol_drive(kind, n)); err_any |= e
        if n < T
            ok = !s.dead && s.t == n + 1 && sha256(onelife_inner_bytes(s)) == H[n+1] && onelife_acts(s) == A[n+1]
            if !ok && first_bad === nothing; first_bad = n; end
        elseif n == T
            det_ok = !prev.dead && s.dead && s.death == d && s.t == d && onelife_inner_bytes(s) == onelife_inner_bytes(prev) && isempty(A[d+1])
        end
        (n + 1) in want && (saves[n+1] = onelife_save(s))
    end
    end_ok = nothing; last_empty = nothing
    if d === nothing
        last_empty = _empty_body(s); s2, e2 = onelife_step(s, (0, 0))
        end_ok = !s.dead && !e2 && s2.dead == last_empty && (!last_empty || s2.death == N)
    end
    p1 = first_bad === nothing && !err_any && (d === nothing ? end_ok == true : det_ok == true)
    return (p1 = p1, first_bad = first_bad, err_any = err_any, det_ok = det_ok, end_ok = end_ok, last_empty = last_empty,
            pts = pts, saves = saves, final = s)
end

# ---------- P3 ----------
function after_death(L, sav)
    s = ol_load(L, sav); err = false
    for _ in 1:10000; s, e = onelife_step(s, (5, 5)); err |= e; end
    s, e = onelife_step(s, (7, -1)); err |= e
    return s.dead && !err && onelife_save(s) == sav
end
function emptied(seed, L)
    s = onelife_birth(seed, L); c = deepcopy(s); c.w.C .= 0
    z = OneLife{L}(c.circuit, c.b, c.perm, c.noise, c.w, c.pool, 0, false, nothing)
    d, e = onelife_step(z, (5, 5))
    return d, d.dead && d.death == 0 && d.t == 0 && !e && onelife_inner_bytes(d) == onelife_inner_bytes(z)
end

# ---------- P4 (the other process) ----------
function resume_check(tag, law, kind, r)
    segs = Any[]; pts = r.pts
    file(n) = joinpath(TMP, "$(tag)_$(n).bin")
    for n in vcat(pts, N); write(file(n), r.saves[n]); end
    for (i, n) in enumerate(pts)
        to = i < length(pts) ? pts[i+1] : N
        push!(segs, Dict("from" => n, "to" => to, "from_file" => file(n), "to_file" => file(to)))
    end
    man = joinpath(TMP, "$(tag)_man.json"); out = joinpath(TMP, "$(tag)_out.json")
    write(man, JSON.json(Dict("law" => law, "drive" => kind, "segments" => segs)))
    run(`$(Base.julia_cmd()) --project=$LAB $(joinpath(@__DIR__, "one_life_resume.jl")) resume $man $out`)
    res = JSON.parsefile(out)
    ok = res["pid"] != getpid() && length(res["rows"]) == length(segs) && all(x -> x["same"] == true && x["error"] == false, res["rows"])
    return ok, length(segs)
end

# ---------- P5 ----------
function corruption(seed, L, sav)
    r = Mulberry(seed); nb = 8 * length(sav); accepted = 0
    for _ in 1:200
        pos = floor(Int, r() * nb); c = copy(sav); c[pos÷8+1] ⊻= UInt8(1) << (pos % 8)
        got = nothing
        try; got = ol_load(L, c); catch; end
        got === nothing || (accepted += 1)
    end
    other = nothing
    try; other = ol_load(L === LawL2 ? LawL2SF : LawL2, sav); catch; end
    return accepted == 0 && other === nothing, accepted
end

# ---------- gates ----------
strip_comments(src) = join([replace(l, r"#.*$" => "") for l in split(src, '\n')], '\n')
const BAD_ANY = r"\bENV\b|\bglobal\b|\btime\b|\brand\b|\bRef\b|\bopen\(|\breadline|\bread\(|\bwrite\(|\bisfile\(|\breaddir\(|\bpwd\(|\bcd\("
const BAD_SER = r"\bENV\b|\bglobal\b|\btime\b|\brand\b|\bRef\b|\bopen\(|\breadline|\bisfile\(|\breaddir\(|\bpwd\(|\bcd\("
function g4_static(src)
    a = findfirst("# --- serialization", src); b = findfirst("# --- end of serialization", src)
    (a === nothing || b === nothing) && return false
    outside = strip_comments(src[1:first(a)-1] * src[last(b)+1:end]); inside = strip_comments(src[first(a):last(b)])
    return !occursin(BAD_ANY, outside) && !occursin(BAD_SER, inside)
end
function g4_reached()
    rng = [("circuit.jl", 13:26), ("circuit.jl", 104:303), ("matter.jl", 9:20), ("matter.jl", 63:130), ("jsmath.jl", 13:13), ("jsmath.jl", 108:119)]
    hits = String[]
    for (f, r) in rng
        ls = readlines(joinpath(LAB, "core", f))[r]
        for (i, l) in zip(r, ls); occursin(BAD_ANY, replace(l, r"#.*$" => "")) && push!(hits, "$f:$i"); end
    end
    w = r"(FEATURES|_NPIO2_HW|BO_CUR|RULES|ALPHA_FEATURES)\[[^\]]*\]\s*=[^=]|push!\((FEATURES|_NPIO2_HW|BO_CUR)|empty!\((FEATURES|_NPIO2_HW|BO_CUR)"
    for dir in ("core", "experiments"), f in readdir(joinpath(LAB, dir))
        endswith(f, ".jl") || continue
        for (i, l) in enumerate(readlines(joinpath(LAB, dir, f))); occursin(w, l) && push!(hits, "$dir/$f:$i"); end
    end
    return isempty(hits), hits
end
# G2 on the source: exactly two methods of onelife_step, two arguments each, one per law, and the law's call of _live
# with literal constants only.
function g2_static(src)
    ex = Meta.parseall(src); defs = Any[]
    walk(e) = if e isa Expr
        if e.head == :function && e.args[1] isa Expr && e.args[1].head == :call && e.args[1].args[1] == :onelife_step
            push!(defs, e)
        end
        foreach(walk, e.args)
    end
    walk(ex)
    length(defs) == 2 || return false
    laws = Any[]
    for d in defs
        sig = d.args[1]; length(sig.args) == 3 || return false
        a1 = sig.args[2]; (a1 isa Expr && a1.head == :(::)) || return false
        push!(laws, a1.args[2])
        calls = Any[]
        cw(e) = if e isa Expr
            (e.head == :call && e.args[1] == :_live) && push!(calls, e); foreach(cw, e.args)
        end
        cw(d.args[2])
        length(calls) == 1 || return false
        c = calls[1]; length(c.args) == 10 || return false
        all(x -> x isa Number || x isa Bool || x isa QuoteNode, c.args[4:end]) || return false
    end
    return Set(string.(laws)) == Set(["OneLife{LawL2}", "OneLife{LawL2SF}"])
end
g2_runtime() = (ms = collect(methods(onelife_step)); length(ms) == 2 && all(m -> m.nargs == 3, ms))

function mutids!(acc, x)
    (x isa String || x isa Symbol || x isa Number || x isa Char || x === nothing || x isa Function || x isa Type) && return acc
    if x isa Array
        objectid(x) in acc && return acc
        push!(acc, objectid(x)); isbitstype(eltype(x)) || foreach(e -> mutids!(acc, e), x)
    elseif ismutable(x)
        objectid(x) in acc && return acc
        push!(acc, objectid(x)); for f in fieldnames(typeof(x)); mutids!(acc, getfield(x, f)); end
    else
        for i in 1:nfields(x); mutids!(acc, getfield(x, i)); end
    end
    return acc
end
function g3(stepf, cases)
    for (s, g) in cases
        before = onelife_encode(s); o1 = stepf(s, g); after = onelife_encode(s); o2 = stepf(s, g)
        before == after || return false
        (onelife_encode(o1[1]) == onelife_encode(o2[1]) && o1[2] == o2[2]) || return false
        isempty(intersect(mutids!(Set{UInt}(), s), mutids!(Set{UInt}(), o1[1]))) || return false
        o1[1].perm !== o1[1].b.perm || return false
    end
    return true
end
function g5(loadf, sav)
    s = loadf(sav)
    return s.dead && onelife_save(s) == sav
end
g5_args() = all(f -> all(m -> m.nargs == 2 && m.sig.parameters[2] == Vector{UInt8}, methods(f)), (onelife_load_L2, onelife_load_L2SF))
function g6(loadf, sav)
    n = length(sav); tl = n - 32 - 9   # the lowest byte of t (body ends with t, dead, the tag of death)
    for p in (1, 6, 20, 44, 49, (49 + n - 32) ÷ 2, tl, n - 32, n)
        c = copy(sav); c[p] ⊻= 0x01; got = nothing
        try; got = loadf(c); catch; end
        got === nothing || return false
    end
    got = nothing
    try; got = loadf(sav[1:end-1]); catch; end
    return got === nothing
end
function g7(stepf, states)
    for s in states, g in ((6, 0), (0, 6), (-1, 0), (0, -1), (5, 5, 5), (5,), (2.5, 1), (100, 100), [6, 6])
        before = onelife_encode(s); o, e = stepf(s, g)
        (e && onelife_encode(o) == before && onelife_encode(s) == before) || return false
    end
    return true
end

function gates(seed)
    G = Dict{String,Any}(); src = read(joinpath(LAB, "core", "one_life.jl"), String)
    say("== gates (seed $seed, N $N)")
    # G2
    bad2a = replace(src, "function onelife_step(s::OneLife{LawL2}, g)" => "function onelife_step(s::OneLife{LawL2}, g, extra)")
    bad2b = replace(src, "_live(s, g, 0.02, 0.004, 0.002, :bin3, true, true, false)" => "_live(s, g, 0.02, 0.004, KCV, :bin3, true, true, false)")
    G["G2"] = g2_static(src) && g2_runtime(); G["G2_neg"] = !g2_static(bad2a) && !g2_static(bad2b) && bad2a != src && bad2b != src
    # states for G3, G5-G7
    L = LawL2SF; s0 = onelife_birth(seed, L); s = s0
    for n in 0:min(N, 1200)-1; s, _ = onelife_step(s, ol_drive("D1", n)); end
    mid = s; dz, _ = emptied(seed, L); dz2, _ = emptied(seed, LawL2)
    cases = [(s0, (5, 0)), (mid, (3, 2)), (dz, (5, 5)), (dz, (9, -9)), (mid, (9, 9)), (onelife_birth(seed, LawL2), (0, 5))]
    badmut(x, g) = (x.pool[1] += 1e-9; onelife_step(x, g))
    badshare(x, g) = (o = onelife_step(x, g); x.dead ? (x, false) : o)
    G["G3"] = g3(onelife_step, cases)
    G["G3_neg"] = !g3(badmut, deepcopy(cases)) && !g3(badshare, deepcopy(cases))
    # G4
    bad4 = replace(src, "    s.dead && return (deepcopy(s), false)\n    _empty_body(s) && return (_detect(s), false)\n    _drive_ok(g) || return (deepcopy(s), true)\n    return (_live(s, g, 0.02, 0.004, 0.002, :bin3, true, true, true), false)" =>
                         "    x = ENV[\"HOME\"]\n    s.dead && return (deepcopy(s), false)\n    _empty_body(s) && return (_detect(s), false)\n    _drive_ok(g) || return (deepcopy(s), true)\n    return (_live(s, g, 0.02, 0.004, 0.002, :bin3, true, true, true), false)")
    reach_ok, hits = g4_reached()
    G["G4_1"] = g4_static(src); G["G4_2"] = reach_ok; G["G4_2_hits"] = hits; G["G4_neg"] = bad4 != src && !g4_static(bad4)
    chains = Any[]
    for (law, kind) in (("L2+SF", "D1"), ("L2", "D2"))
        Random.seed!(12345); here = joinpath(TMP, "g4_here.json"); ol_straight(seed, law, kind, N, 12345, here)
        oa = joinpath(TMP, "g4_a.json"); ob = joinpath(TMP, "g4_b.json"); script = joinpath(@__DIR__, "one_life_resume.jl")
        ca = `$(Base.julia_cmd()) --project=$LAB $script straight $seed $law $kind $N 1 $oa`
        cb = `$(Base.julia_cmd()) --project=$LAB $script straight $seed $law $kind $N 99999 $ob`
        run(setenv(ca, merge(Dict(ENV), Dict("OL_PROBE" => "a", "TZ" => "UTC")); dir = @__DIR__))
        sleep(1.1)
        run(setenv(cb, merge(Dict(ENV), Dict("OL_PROBE" => "bbbbbb", "TZ" => "Asia/Tokyo", "LANG" => "C", "OL_EXTRA" => TMP)); dir = TMP))
        h, a, b = JSON.parsefile(here), JSON.parsefile(oa), JSON.parsefile(ob)
        push!(chains, (law, kind, h["chain"] == a["chain"] == b["chain"] && a["pid"] != b["pid"] && a["cwd"] != b["cwd"]))
    end
    G["G4_3"] = all(x -> x[3], chains)
    # G5
    dsav = onelife_save(dz)
    badload(b) = (x = onelife_load_L2SF(b); OneLife{LawL2SF}(x.circuit, x.b, x.perm, x.noise, x.w, x.pool, x.t, false, nothing))
    G["G5"] = g5(onelife_load_L2SF, dsav) && g5(onelife_load_L2, onelife_save(dz2)) && g5_args()
    G["G5_neg"] = !g5(badload, dsav)
    # G6
    msav = onelife_save(mid); other = nothing
    try; other = onelife_load_L2(msav); catch; end
    lenient(b) = onelife_decode(LawL2SF, b[49:end-32])
    G["G6"] = g6(onelife_load_L2SF, msav) && g6(onelife_load_L2SF, dsav) && other === nothing
    G["G6_neg"] = !g6(lenient, msav)
    # G7
    function nocheck(x, g)
        x.dead && return (deepcopy(x), false)
        try
            return (_live(x, g, 0.02, 0.004, 0.002, :bin3, true, true, true), false)
        catch
            return (deepcopy(x), false)
        end
    end
    G["G7"] = g7(onelife_step, [s0, mid, onelife_birth(seed, LawL2)])
    G["G7_neg"] = !g7(nocheck, [s0, mid])
    for k in sort(collect(keys(G))); say("  ", k, " ", G[k]); end
    return G
end

# ---------- main ----------
function main()
    say("S48 one_life_check mode $MODE N $N seeds $(first(SEEDS))-$(last(SEEDS))")
    out = Dict{String,Any}("mode" => MODE, "N" => N, "seeds" => collect(SEEDS))
    MODE == "main" || (out["gates"] = gates(first(SEEDS)))
    lives = Any[]; t0 = time()
    syn = Dict{String,Any}()
    for law in LAWS
        L = ol_law(law); d, ok = emptied(first(SEEDS), L)
        syn[law] = Dict("death0" => ok, "p3" => after_death(L, onelife_save(d)))
    end
    say("synthetic emptied: ", syn)
    for seed in SEEDS, law in LAWS, kind in DRIVES
        L = ol_law(law); ts = time()
        d, H, A, drive_ok = ref_run(seed, law, kind)
        r = life_run(seed, law, kind, d, H, A)
        p3 = d === nothing ? nothing : after_death(L, r.saves[d+1])
        p4, nseg = resume_check("s$(seed)_$(law == "L2" ? "L2" : "L2SF")_$kind", law, kind, r)
        p5, acc = corruption(seed, L, r.saves[N])
        row = Dict("seed" => seed, "law" => law, "drive" => kind, "death_ref" => d, "death_one" => r.final.death, "drive_ok" => drive_ok,
                   "p1" => r.p1 && drive_ok, "first_bad" => r.first_bad, "err_any" => r.err_any, "det_ok" => r.det_ok, "end_ok" => r.end_ok,
                   "last_empty" => r.last_empty, "p3" => p3, "p4" => p4, "p4_segments" => nseg, "p5" => p5, "p5_accepted" => acc)
        push!(lives, row)
        say(rpad("$seed $law $kind", 16), " death ", d, " | P1 ", row["p1"], " P3 ", p3, " P4 ", p4, " ($nseg) P5 ", p5,
            "  ", round(time() - ts; digits = 1), " s")
    end
    nd = count(x -> x["death_ref"] !== nothing, lives)
    P1 = all(x -> x["p1"], lives); P3gen = all(x -> x["p3"] !== false, lives); P3syn = all(v -> v["death0"] && v["p3"], values(syn))
    P4 = all(x -> x["p4"], lives); P5 = all(x -> x["p5"], lives)
    out["lives"] = lives; out["synthetic"] = syn; out["deaths"] = nd
    out["summary"] = Dict("P1" => P1, "P3_generated" => P3gen, "P3_synthetic" => P3syn, "P4" => P4, "P5" => P5,
                          "death_items" => nd >= 3 ? "checked" : "not checked (fewer than 3 deaths)")
    say("deaths $nd / $(length(lives))  P1 $P1  P3 generated $P3gen synthetic $P3syn  P4 $P4  P5 $P5  ($(round(time() - t0; digits = 1)) s)")
    if MODE != "dev"
        write(joinpath(@__DIR__, "results-one-life-$MODE.json"), JSON.json(out, 2))
        write(joinpath(@__DIR__, "results-one-life-$MODE.out"), join(LINES, "\n") * "\n")
        say("written results-one-life-$MODE.json / .out")
    end
end
main()
