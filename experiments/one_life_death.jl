# S48b check (discussion/specs/S48b-death-drive.md r1; predictions-one-life-b.md, freeze-one-life-b.txt).
# Drives D3 / D4 (one_life_death_resume.jl), gates H1-H2 with their negative controls (smoke only), PD1-PD5.
# The comparison is built as in one_life_check.jl (S48 r2 §5): the reference's end-of-step snapshot, the noise as its
# int32 state, the save position = the number of drives given.
# Usage: cd experiments && julia --project=.. one_life_death.jl smoke   (seeds 615-616, N = 10000)
#        cd experiments && julia --project=.. one_life_death.jl main    (seeds 617-626, N = 10000, run once)
include(joinpath(@__DIR__, "one_life_death_resume.jl"))
using JSON, SHA

const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = ARGS[1]
const N = 10000
const NDEATH = 6000
const SEEDS = MODE == "main" ? (617:626) : MODE == "smoke" ? (615:616) : error("mode smoke | main")
const LAWS = ("L2", "L2+SF")
const DRIVES = ("D3", "D4")
const TMP = mktempdir()
const LINES = String[]
say(x...) = (s = string(x...); println(s); push!(LINES, s); flush(stdout))

# ---------- the reference (body_org_run, body_org.jl unchanged) ----------
# D3: FEED true (BO_CUR for t < 800), then SCHED at world time s = t - 800; D4: FEED false, SCHED at s = t.
function ref_opts(law, kind)
    o = (U = 0.02, MCOST = 0.004, STEPS = N, KC = 0.002, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
    law == "L2+SF" && (o = merge(o, (SEDFADE = true,)))
    f = kind == "D3" ? ((s, k) -> drive_D3(s + 800)[k]) : kind == "D4" ? ((s, k) -> drive_D4(s)[k]) : error("drive $kind")
    return merge(o, (FEED = kind == "D3", SCHED = f))
end
function ref_run(seed, law, kind)
    o = ref_opts(law, kind); H = Vector{Vector{UInt8}}(); A = Vector{Vector{Int}}()
    obs(i) = (push!(H, sha256(onelife_inner_bytes(i.circuit, i.b, i.b.perm, state_int32(i.noise), i.w, i.pool))); push!(A, copy(i.acting)))
    r = body_org_run("ORG", seed, merge(o, (ON_STEP = obs,)))
    drive_ok = all(t -> Float64[death_drive(kind, t)...] == LabCore.bo_season_at(t, o), 0:N-1)
    return r["death"], H, A, drive_ok
end

function save_points(d)
    p = Set(floor(Int, k * N / 5) for k in 0:4); push!(p, NDEATH)
    if d !== nothing; for x in (d - 2, d - 1, d, d + 1, d + 2); 0 <= x <= N && push!(p, x); end; end
    return sort(collect(p))
end

# PD3: every save (or its SHA) of the sequence is the same.
pd3_ok(seq) = !isempty(seq) && all(x -> x == seq[1], seq)

# ---------- the straight run: PD2, the sequence for PD3, the saves for PD4 / PD5 ----------
function life_run(seed, law, kind, d, H, A)
    L = ol_law(law); s = onelife_birth(seed, L); pts = save_points(d); want = Set(vcat(pts, N))
    saves = Dict{Int,Vector{UInt8}}(); hs = Vector{UInt8}()
    sv = onelife_save(s); 0 in want && (saves[0] = sv); append!(hs, sha256(sv))
    T = d === nothing ? N : d; first_bad = nothing; err_any = false; det_ok = nothing; after = Vector{Vector{UInt8}}()
    dead_all = true
    for n in 0:N-1
        prev = s
        s, e = onelife_step(s, death_drive(kind, n)); err_any |= e
        if n < T
            ok = !s.dead && s.t == n + 1 && sha256(onelife_inner_bytes(s)) == H[n+1] && onelife_acts(s) == A[n+1]
            if !ok && first_bad === nothing; first_bad = n; end
        elseif n == T
            det_ok = !prev.dead && s.dead && s.death == d && s.t == d && onelife_inner_bytes(s) == onelife_inner_bytes(prev) && isempty(A[d+1])
        end
        sv = onelife_save(s); h = sha256(sv); append!(hs, h)
        (n + 1) in want && (saves[n+1] = sv)
        if d !== nothing && n >= d
            push!(after, h); dead_all &= s.dead && s.death == d
        end
    end
    end_ok = nothing
    if d === nothing
        last_empty = _empty_body(s); s2, e2 = onelife_step(s, (0, 0))
        end_ok = !s.dead && !e2 && s2.dead == last_empty && (!last_empty || s2.death == N)
    end
    pd2 = first_bad === nothing && !err_any && (d === nothing ? end_ok == true : det_ok == true)
    pd3 = d === nothing ? nothing : (pd3_ok(after) && dead_all && length(after) == N - d)
    return (pd2 = pd2, pd3 = pd3, first_bad = first_bad, err_any = err_any, det_ok = det_ok, end_ok = end_ok, pts = pts, saves = saves,
            hs = hs, after = after, final = s)
end

# ---------- PD4 (the other process) ----------
# The other processes run beside the main one (at most NPROC at a time); each is collected after the loop.
const NPROC = 6
function resume_launch(tag, law, kind, r; skip = nothing)
    file(n) = joinpath(TMP, "$(tag)_$(n).bin")
    for n in r.pts; write(file(n), r.saves[n]); end
    hf = joinpath(TMP, "$(tag)_hashes.bin"); write(hf, r.hs)
    man = joinpath(TMP, "$(tag)_man.json"); out = joinpath(TMP, "$(tag)_out.json")
    m = Dict{String,Any}("law" => law, "drive" => kind, "N" => N, "hashes" => hf,
                         "points" => [Dict("n" => n, "file" => file(n)) for n in r.pts])
    skip === nothing || (m["skip"] = skip)
    write(man, JSON.json(m))
    p = run(`$(Base.julia_cmd()) --project=$LAB $(joinpath(@__DIR__, "one_life_death_resume.jl")) resume $man $out`; wait = false)
    return (p = p, out = out, npts = length(r.pts))
end
function resume_collect(h)
    wait(h.p); success(h.p) || return false, Any[]
    res = JSON.parsefile(h.out)
    ok = res["pid"] != getpid() && length(res["rows"]) == h.npts &&
         all(x -> x["load_same"] == true && x["nbad"] == 0 && x["error"] == false, res["rows"])
    return ok, res["rows"]
end
resume_check(tag, law, kind, r; skip = nothing) = resume_collect(resume_launch(tag, law, kind, r; skip = skip))
# ---------- PD5 ----------
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
    return accepted == 0, accepted, other === nothing
end

# ---------- H1: the drives read the drive index only ----------
function collect_syms!(acc, e)
    if e isa Symbol
        push!(acc, e)
    elseif e isa QuoteNode
        collect_syms!(acc, e.value)
    elseif e isa Expr
        foreach(x -> collect_syms!(acc, x), e.args)
    end
    return acc
end
function find_defs(ex, name)
    defs = Any[]
    walk(e) = if e isa Expr
        if e.head in (:(=), :function) && e.args[1] isa Expr && e.args[1].head == :call && e.args[1].args[1] == name
            push!(defs, e)
        end
        foreach(walk, e.args)
    end
    walk(ex)
    return defs
end
const H1_ALLOWED_DRIVE = Set([:n, :<, :ol_drive])
const H1_ALLOWED_D1 = Set([:kind, :t, :g, :(==), :<, :+, :-, :LabCore, :BO_CUR, :bo_season, :isinteger, :error, :Int])
function h1_static(src, src_d1)
    ex = Meta.parseall(src)
    for name in (:drive_D3, :drive_D4)
        defs = find_defs(ex, name); length(defs) == 1 || return false
        sig = defs[1].args[1]; length(sig.args) == 2 || return false
        sig.args[2] == :(n::Int) || return false
        issubset(collect_syms!(Set{Symbol}(), defs[1].args[2]), H1_ALLOWED_DRIVE) || return false
    end
    defs = find_defs(Meta.parseall(src_d1), :ol_drive); length(defs) == 1 || return false
    sig = defs[1].args[1]; (length(sig.args) == 3 && sig.args[2] == :(kind::String) && sig.args[3] == :(t::Int)) || return false
    return issubset(collect_syms!(Set{Symbol}(), defs[1].args[2]), H1_ALLOWED_D1)
end
function h1_runtime()
    one(f) = (ms = collect(methods(f)); length(ms) == 1 && ms[1].sig == Tuple{typeof(f),Int})
    vals(k, r) = [death_drive(k, n) for n in r]
    rng_ok = all(k -> all(g -> g isa Tuple{Int,Int} && 0 <= g[1] <= 5 && 0 <= g[2] <= 5, vals(k, 0:N-1)), DRIVES)
    det_ok = all(k -> vals(k, 0:N-1) == reverse(vals(k, N-1:-1:0)), DRIVES)
    form_ok = all(n -> drive_D3(n) == (n < 2000 ? ol_drive("D1", n) : n < 6000 ? (0, 0) : (5, 5)) &&
                       drive_D4(n) == (n < 6000 ? (0, 0) : (5, 5)), 0:N-1)
    return one(drive_D3) && one(drive_D4) && rng_ok && det_ok && form_ok
end

function gates(r0, law, kind)
    G = Dict{String,Any}()
    src = read(joinpath(@__DIR__, "one_life_death_resume.jl"), String); src1 = read(joinpath(@__DIR__, "one_life_resume.jl"), String)
    say("== gates (seed $(first(SEEDS)) $law $kind, N $N)")
    bad1a = replace(src, "drive_D3(n::Int) =" => "drive_D3(n::Int, s) =")
    bad1b = replace(src, "drive_D4(n::Int) = n < 6000 ? (0, 0) : (5, 5)" => "drive_D4(n::Int) = n < 6000 ? (0, 0) : s.dead ? (0, 0) : (5, 5)")
    bad1c = replace(src1, "function ol_drive(kind::String, t::Int)" => "function ol_drive(kind::String, t::Int, s)")
    G["H1_static"] = h1_static(src, src1); G["H1_runtime"] = h1_runtime()
    G["H1_neg"] = bad1a != src && bad1b != src && bad1c != src1 && !h1_static(bad1a, src1) && !h1_static(bad1b, src1) && !h1_static(src, bad1c)
    # H2 PD3: one byte of the dead state changed in one place of the sequence
    G["H2_pd3_base"] = r0.after !== nothing && pd3_ok(r0.after)
    dsav = r0.saves[N]; alt = copy(dsav); alt[49+div(length(dsav) - 80, 2)] ⊻= 0x01
    seq = copy(r0.after); seq[div(length(seq), 2)+1] = sha256(alt)
    G["H2_pd3_neg"] = alt != dsav && !pd3_ok(seq)
    # H2 PD4: one drive of the continuation left out (a living step: at the first step after the point d-2, and at 0)
    tag = "neg_$(first(SEEDS))"
    i_dm2 = findfirst(==(r0.final.death - 2), r0.pts); i_0 = findfirst(==(0), r0.pts)
    hA = resume_launch(tag * "a", law, kind, r0; skip = Dict("point" => i_dm2, "at" => r0.pts[i_dm2]))
    hB = resume_launch(tag * "b", law, kind, r0; skip = Dict("point" => i_0, "at" => 0))
    okA, rowsA = resume_collect(hA); okB, rowsB = resume_collect(hB)
    G["H2_pd4_neg"] = !okA && !okB && length(rowsA) == length(r0.pts) && length(rowsB) == length(r0.pts) && rowsA[i_dm2]["nbad"] > 0 && rowsB[i_0]["nbad"] > 0 &&
                      all(j -> rowsA[j]["nbad"] == 0, setdiff(eachindex(rowsA), [i_dm2]))
    for k in sort(collect(keys(G))); say("  ", k, " ", G[k]); end
    return G
end

# ---------- main ----------
function verdict(rows, key)
    any(x -> x[key] === false, rows) && return "not established"
    return "established"
end
function main()
    say("S48b one_life_death mode $MODE N $N seeds $(first(SEEDS))-$(last(SEEDS))")
    out = Dict{String,Any}("mode" => MODE, "N" => N, "seeds" => collect(SEEDS))
    lives = Any[]; t0 = time(); gated = false; pending = Any[]
    for seed in SEEDS, law in LAWS, kind in DRIVES
        L = ol_law(law); ts = time()
        d, H, A, drive_ok = ref_run(seed, law, kind)
        r = life_run(seed, law, kind, d, H, A)
        dead6 = d !== nothing && d < NDEATH && r.final.dead && r.final.death == d
        if MODE == "smoke" && !gated && dead6 && d >= 2
            out["gates"] = gates(r, law, kind); gated = true
        end
        p3 = dead6 ? r.pd3 : nothing
        while count(x -> process_running(x[2].p), pending) >= NPROC; sleep(1); end
        h = resume_launch("s$(seed)_$(law == "L2" ? "L2" : "L2SF")_$kind", law, kind, r)
        p5 = nothing; acc = nothing; oth = nothing
        if dead6; p5, acc, oth = corruption(seed, L, r.saves[N]); end
        row = Dict{String,Any}("seed" => seed, "law" => law, "drive" => kind, "death_ref" => d, "death_one" => r.final.death, "drive_ok" => drive_ok,
                   "dead_before_6000" => dead6, "pd2" => r.pd2 && drive_ok, "first_bad" => r.first_bad, "err_any" => r.err_any,
                   "det_ok" => r.det_ok, "end_ok" => r.end_ok, "pd3" => p3, "pd4_points" => r.pts, "pd5" => p5, "pd5_accepted" => acc,
                   "pd5_other_law_refused" => oth)
        push!(lives, row); push!(pending, (row, h))
        say(rpad("$seed $law $kind", 16), " death ", d, " | PD2 ", row["pd2"], " PD3 ", p3, " PD5 ", p5, " (PD4 launched, ",
            length(r.pts), " pts)  ", round(time() - ts; digits = 1), " s")
    end
    for (row, h) in pending
        p4, rows = resume_collect(h)
        row["pd4_all_points"] = p4; row["pd4_rows"] = rows; row["pd4"] = row["dead_before_6000"] ? p4 : nothing
        say(rpad("$(row["seed"]) $(row["law"]) $(row["drive"])", 16), " PD4 ", row["pd4"], " (all points ", p4, ")")
    end
    MODE == "smoke" && !gated && say("gates not run: no life dead before $NDEATH with d >= 2")
    cells = Dict{String,Any}()
    for law in LAWS, kind in DRIVES
        rs = filter(x -> x["law"] == law && x["drive"] == kind, lives); dd = filter(x -> x["dead_before_6000"], rs)
        ds = [x["death_ref"] for x in dd]; nd = length(dd)
        c = Dict{String,Any}("n" => length(rs), "dead_before_6000" => nd, "d_min" => nd > 0 ? minimum(ds) : nothing,
                             "d_max" => nd > 0 ? maximum(ds) : nothing,
                             "pd2_pass" => count(x -> x["pd2"], rs), "pd2_fail" => count(x -> !x["pd2"], rs))
        for k in ("pd3", "pd4", "pd5")
            c[k*"_pass"] = count(x -> x[k] === true, dd); c[k*"_fail"] = count(x -> x[k] === false, dd)
            c[k*"_not_checked_lives"] = length(rs) - nd
            c[k] = nd < 3 ? "not checked" : verdict(dd, k)
        end
        cells["$law $kind"] = c
        say("cell $law $kind: dead<6000 $nd/$(length(rs)) d ", c["d_min"], "..", c["d_max"], " PD2 ", c["pd2_pass"], "/", length(rs),
            " PD3 ", c["pd3"], " (", c["pd3_pass"], "/", nd, ") PD4 ", c["pd4"], " (", c["pd4_pass"], "/", nd, ") PD5 ", c["pd5"],
            " (", c["pd5_pass"], "/", nd, ")")
    end
    PD1 = all(x -> x["dead_before_6000"], lives)
    PD2 = all(x -> x["pd2"], lives) ? "established" : "not established"
    agg(k) = any(c -> c[k] == "not established", values(cells)) ? "not established" :
             all(c -> c[k] == "established", values(cells)) ? "established" : "not checked in some cells"
    out["lives"] = lives; out["cells"] = cells
    out["summary"] = Dict("PD1" => PD1 ? "established" : "not established", "PD1_dead" => count(x -> x["dead_before_6000"], lives),
                          "PD2" => PD2, "PD3" => agg("pd3"), "PD4" => agg("pd4"), "PD5" => agg("pd5"),
                          "reference_out_of_scope" => "none (D3, D4 fed through FEED + SCHED as a function; body_org.jl unchanged)")
    say("summary ", out["summary"], "  (", round(time() - t0; digits = 1), " s)")
    write(joinpath(@__DIR__, "results-one-life-death-$MODE.json"), JSON.json(out, 2))
    write(joinpath(@__DIR__, "results-one-life-death-$MODE.out"), join(LINES, "\n") * "\n")
    say("written results-one-life-death-$MODE.json / .out")
end
main()
