# S45 (spec discussion/specs/S45-trm-stageA.md r2): trajectory data for a read-only TRM-type predictor, written in the
# official TinyRecursiveModels format (.npy + dataset.json), baseline predictors B0/B1/B2/B2', the e / O1 evaluator.
# G1 (g1_school.jl's org_g1 and school_perm; shared files are not edited). Splits by seed: train 511-530, explore 531-540,
# confirm 541-560 (written only; no e / O1 is computed on it here). Writes experiments/trm-data/ and results-trm-data.json.
ENV["SEEDS"] = ""; ENV["OUT"] = "/dev/null"            # g1_school.jl: definitions and its identity gate only, no runs
include(joinpath(@__DIR__, "g1_school.jl"))
using JSON

const W = 8
const TRAIN = 511:530; const EXPLORE = 531:540; const CONFIRM = 541:560
const OUTDIR = get(ENV, "TRMDATA", joinpath(@__DIR__, "trm-data"))
const RNAMES = ["r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "rb"]
const MNAMES = ["m0", "m1", "m2"]                        # action code: 1 m0, 2 m1, 3 m2, 4 none
const TOK_OFF = 1; const TOK_ON = 2; const TOK_ACT0 = 2; const TOK_Q = 7   # action tokens 3..6

# ---------------------------------------------------------------- one trial with the per-update record
const POSTA = Ref{Any}(nothing); const WATCHA = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (st === WATCHA[] && (POSTA[] = copy(o.acting)))
function record(s, p, sch)
    st = AS.initial_state(s, p); b = s.b
    ri = [LC.unit(b, r) for r in RNAMES]; mi = [LC.unit(b, m) for m in MNAMES]; ci = [LC.unit(b, "c1"), LC.unit(b, "c2")]
    R5 = LC.unit(b, "r5"); R = falses(H, 9); C = falses(H, 2); A = zeros(Int, H); alive = falses(H); nact = zeros(Int, H)
    tr = Vector{Vector{Bool}}()
    for u in 1:H
        WATCHA[] = st; POSTA[] = nothing
        AS.step!(st, s, p, sch, Set{Int}())
        WATCHA[] = nothing
        acting = POSTA[] === nothing ? Int[] : [m for m in POSTA[] if m in mi]
        nact[u] = length(acting)
        A[u] = isempty(acting) ? 4 : findfirst(==(acting[1]), mi)
        R[u, :] = st.active[ri]; C[u, :] = st.active[ci]; alive[u] = !st.dead
        push!(tr, [st.active[x] for x in eachindex(st.active) if x != R5])
    end
    (R = R, C = C, A = A, alive = alive, nact = nact, traj = string(hash(tr)))
end

"""Examples of one trajectory: for u in W:H-1 with alive[u+1], the input (indices u-W+1..u) and the teacher (u+1).
Returns the source time indices too (the leakage gate checks them)."""
function examples(rec; core = false)
    X = Vector{Vector{UInt8}}(); Y = Vector{Vector{UInt8}}(); src = Vector{Vector{Int}}(); tsrc = Int[]; us = Int[]
    for u in W:H-1
        rec.alive[u+1] || continue
        x = UInt8[]; ix = Int[]
        for v in u-W+1:u
            for i in 1:9; push!(x, rec.R[v, i] ? TOK_ON : TOK_OFF); push!(ix, v); end
            if core; for i in 1:2; push!(x, rec.C[v, i] ? TOK_ON : TOK_OFF); push!(ix, v); end; end
            push!(x, TOK_ACT0 + rec.A[v]); push!(ix, v)
        end
        append!(x, fill(UInt8(TOK_Q), 9))
        y = zeros(UInt8, length(x)); y[end-8:end] = [rec.R[u+1, i] ? TOK_ON : TOK_OFF for i in 1:9]
        push!(X, x); push!(Y, y); push!(src, ix); push!(tsrc, u + 1); push!(us, u)
    end
    (X = X, Y = Y, src = src, tsrc = tsrc, us = us)
end

# ---------------------------------------------------------------- .npy (format 1.0, little endian, C order)
function write_npy(path, A::AbstractArray{T}) where {T}
    descr = T == UInt8 ? "|u1" : T == Int32 ? "<i4" : error("dtype")
    shape = ndims(A) == 1 ? "($(length(A)),)" : "($(size(A, 1)), $(size(A, 2)))"
    h = "{'descr': '$descr', 'fortran_order': False, 'shape': $shape, }"
    pad = 64 - ((10 + length(h) + 1) % 64); pad == 64 && (pad = 0)
    h = h * " "^pad * "\n"
    open(path, "w") do io
        write(io, UInt8[0x93]); write(io, "NUMPY"); write(io, UInt8[1, 0]); write(io, htol(UInt16(length(h)))); write(io, h)
        M = ndims(A) == 1 ? A : permutedims(A)          # C order: rows contiguous
        write(io, htol.(vec(M)))
    end
end
function read_npy(path)
    io = open(path); magic = read(io, 6); ver = read(io, 2); hl = ltoh(read(io, UInt16)); h = String(read(io, hl))
    T = occursin("|u1", h) ? UInt8 : Int32
    m = match(r"'shape': \((\d+),\s*(\d*)\)", h); n1 = parse(Int, m[1]); n2 = isempty(m[2]) ? 0 : parse(Int, m[2])
    data = ltoh.(reinterpret(T, read(io))); close(io)
    n2 == 0 ? collect(data) : permutedims(reshape(collect(data), n2, n1))
end

function write_split(dir, groups)
    mkpath(dir)
    X = reduce(vcat, [permutedims(reduce(hcat, g.X)) for g in groups if !isempty(g.X)])
    Y = reduce(vcat, [permutedims(reduce(hcat, g.Y)) for g in groups if !isempty(g.Y)])
    N = size(X, 1); counts = [length(g.X) for g in groups]
    gi = Int32.(vcat(0, cumsum(counts)))
    write_npy(joinpath(dir, "all__inputs.npy"), Matrix{UInt8}(X)); write_npy(joinpath(dir, "all__labels.npy"), Matrix{UInt8}(Y))
    write_npy(joinpath(dir, "all__puzzle_identifiers.npy"), zeros(Int32, N)); write_npy(joinpath(dir, "all__puzzle_indices.npy"), Int32.(0:N))
    write_npy(joinpath(dir, "all__group_indices.npy"), gi)
    meta = Dict("pad_id" => 0, "ignore_label_id" => 0, "blank_identifier_id" => 0, "vocab_size" => 8, "seq_len" => size(X, 2),
                "num_puzzle_identifiers" => 1, "total_groups" => length(groups), "mean_puzzle_examples" => 1.0,
                "total_puzzles" => N, "sets" => ["all"])   # codex I-R 1 #3: one example = one puzzle (puzzle_indices 0..N)
    write(joinpath(dir, "dataset.json"), JSON.json(meta))
    write(joinpath(dirname(dir), "identifiers.json"), JSON.json(["<blank>"]))   # codex I-R 1 #6 (as build_sudoku_dataset.py)
    (N = N, seq_len = size(X, 2), X = X, Y = Y, gi = gi)
end

# ---------------------------------------------------------------- baselines and the evaluator (spec §4)
brier(p, r) = sum((p .- r) .^ 2) / length(r)
lap(k, n) = (k + 1) / (n + 2)
function fit_tables(recs)
    on = zeros(9); n = 0; tab2 = Dict{Tuple{BitVector,Int},Tuple{Vector{Float64},Int}}(); tab1 = Dict{BitVector,Tuple{Vector{Float64},Int}}()
    for rec in recs, u in W:H-1
        rec.alive[u+1] || continue
        r1 = Float64.(rec.R[u+1, :]); on .+= r1; n += 1
        k2 = (BitVector(rec.R[u, :]), rec.A[u]); k1 = BitVector(rec.R[u, :])
        a = get(tab2, k2, (zeros(9), 0)); tab2[k2] = (a[1] .+ r1, a[2] + 1)
        a = get(tab1, k1, (zeros(9), 0)); tab1[k1] = (a[1] .+ r1, a[2] + 1)
    end
    (b0 = on ./ n, tab2 = tab2, tab1 = tab1, n = n)
end
function predict(m, name, rec, u)
    name == "B0" && return m.b0
    name == "B1" && return Float64.(rec.R[u, :])
    if name == "B2"
        k = (BitVector(rec.R[u, :]), rec.A[u]); haskey(m.tab2, k) || return m.b0
        s, n = m.tab2[k]; return lap.(s, n)
    end
    k = BitVector(rec.R[u, :]); haskey(m.tab1, k) || return m.b0
    s, n = m.tab1[k]; lap.(s, n)
end
function entropy4(a)
    c = [count(==(k), a) for k in 1:4] ./ length(a); -sum(x -> x > 0 ? x * log2(x) : 0.0, c)
end
"""O1 = 1 - L_ehat / L_b (b = the train mean of e); L_b == 0 -> nothing (undecided)."""
function o1(e_eval, ehat_eval, b)
    Lb = sum((e_eval .- b) .^ 2) / length(e_eval); Le = sum((e_eval .- ehat_eval) .^ 2) / length(e_eval)
    Lb == 0 ? nothing : 1 - Le / Lb
end

# ---------------------------------------------------------------- run
su = LBA.setup_with(H); p = su.params
g1rec = JSON.parsefile(joinpath(@__DIR__, "results-g1-school.json"))
g1idx = Dict((r["seed"], a, sname) => t for r in g1rec["runs"] for a in ("std", "swap") for (sname, t) in r["arms"][a]["trials"])
recs = Dict{Tuple{Int,String,String},Any}(); raise_hash = Dict{Tuple{Int,String},String}()
for seed in vcat(collect(TRAIN), collect(EXPLORE), collect(CONFIRM)), cur in (:std, :swap)
    s = org_g1(seed, su, cur, school_perm(seed))
    raise_hash[(seed, String(cur))] = string(hash((s.raised.q, s.raised.sg, s.raised.lastM)))
    for sch in su.survival; recs[(seed, String(cur), sch.name)] = record(s, p, sch); end
end
keysof(rg) = sort([k for k in keys(recs) if k[1] in rg])
res = Dict{String,Any}("spec" => "discussion/specs/S45-trm-stageA.md r2", "W" => W, "train" => collect(TRAIN), "explore" => collect(EXPLORE),
                       "confirm" => collect(CONFIRM), "outdir" => OUTDIR)
# the replay against g1_school.jl's record (seeds 511-540)
res["replay"] = Dict("checked" => count(k -> haskey(g1idx, k), keys(recs)),
    "match" => count(k -> haskey(g1idx, k) && g1idx[k]["traj"] == recs[k].traj && g1idx[k]["alive"] == recs[k].alive[H], keys(recs)))
res["max_acts_per_update"] = maximum(maximum(r.nact) for r in values(recs))
res["raise_hash"] = Dict("$(k[1])-$(k[2])" => v for (k, v) in raise_hash)
res["excluded"] = Dict("$(k[1])-$(k[2])-$(k[3])" => count(u -> !recs[k].alive[u+1], W:H-1) for k in keys(recs))
# examples and the files (I_R and I_RC), the leakage data for the gate
splits = (train = TRAIN, explore = EXPLORE, confirm = CONFIRM)
res["files"] = Dict{String,Any}()
for (variant, core) in (("IR", false), ("IRC", true)), (sp, rg) in pairs(splits)
    ks = keysof(rg); groups = [examples(recs[k]; core) for k in ks]
    w = write_split(joinpath(OUTDIR, variant, String(sp)), groups)
    back = (read_npy(joinpath(OUTDIR, variant, String(sp), "all__inputs.npy")), read_npy(joinpath(OUTDIR, variant, String(sp), "all__labels.npy")),
            read_npy(joinpath(OUTDIR, variant, String(sp), "all__group_indices.npy")))
    srcok = all(g -> all(i -> all(<=(g.us[i]), g.src[i]) && g.tsrc[i] == g.us[i] + 1, eachindex(g.us)), groups)
    labok = all(r -> all(==(0), w.Y[r, 1:end-9]) && all(x -> x in (TOK_OFF, TOK_ON), w.Y[r, end-8:end]), 1:w.N)
    res["files"]["$variant/$sp"] = Dict("N" => w.N, "seq_len" => w.seq_len, "readback" => back[1] == w.X && back[2] == w.Y && back[3] == w.gi,
                                        "source_times_ok" => srcok, "labels_only_last9" => labok, "groups" => length(groups))
end
# future invariance (codex I-R 1 #4): on the longest-lived explore trajectory, for IR and IRC, rewrite R, C and A at u+1..
# of a copy, rebuild the examples and compare the same u: the input unchanged, the teacher changed
k0 = argmax(k -> count(recs[k].alive), keysof(EXPLORE)); rec0 = recs[k0]
fut = Dict{String,Any}()
for core in (false, true)
    ex0 = examples(rec0; core)
    for (i, u) in enumerate(ex0.us)
        i % 37 == 1 || continue
        R2 = copy(rec0.R); A2 = copy(rec0.A); C2 = copy(rec0.C)
        R2[u+1:end, :] .= .!R2[u+1:end, :]; C2[u+1:end, :] .= .!C2[u+1:end, :]; A2[u+1:end] .= mod.(A2[u+1:end], 4) .+ 1
        ex2 = examples((R = R2, C = C2, A = A2, alive = rec0.alive); core); j = findfirst(==(u), ex2.us)
        fut["$(core ? "IRC" : "IR")-u$u"] = j !== nothing && ex2.X[j] == ex0.X[i] && ex2.Y[j] != ex0.Y[i]
    end
end
# the negative control of the test: a builder that reads C at v+1 (a future core value) must be caught
function examples_bad(rec)
    X = Vector{Vector{UInt8}}(); us = Int[]
    for u in W:H-1
        rec.alive[u+1] || continue
        x = UInt8[]
        for v in u-W+1:u; for i in 1:9; push!(x, rec.R[v, i] ? TOK_ON : TOK_OFF); end; for i in 1:2; push!(x, rec.C[v+1, i] ? TOK_ON : TOK_OFF); end; push!(x, TOK_ACT0 + rec.A[v]); end
        push!(X, x); push!(us, u)
    end
    (X = X, us = us)
end
bad0 = examples_bad(rec0); u_t = bad0.us[1]
C2 = copy(rec0.C); C2[u_t+1:end, :] .= .!C2[u_t+1:end, :]
bad2 = examples_bad((R = rec0.R, C = C2, A = rec0.A, alive = rec0.alive))
res["future_invariance_negative_caught"] = bad2.X[1] != bad0.X[1]
res["future_invariance"] = fut
res["future_invariance_traj"] = "$(k0[1])-$(k0[2])-$(k0[3])"
# auxiliary diagnosis (spec §6): a shifted build that puts the teacher into the window fails the source-time check
ex0 = examples(rec0)
shifted_src = [collect(u-W+2:u+1) for u in ex0.us]
res["shift_diag_fails"] = !all(i -> all(<=(ex0.us[i]), shifted_src[i]), eachindex(ex0.us))
# baselines: fit on train, evaluate on explore (not on confirm)
m = fit_tables([recs[k] for k in keysof(TRAIN)])
ev = Dict{String,Any}()
for name in ("B0", "B1", "B2", "B2p")
    es = Float64[]; hit = 0; tot = 0; es_var = Float64[]
    for k in keysof(EXPLORE)
        rec = recs[k]; acts = rec.A
        for u in W:H-1
            rec.alive[u+1] || continue
            e = brier(predict(m, name, rec, u), Float64.(rec.R[u+1, :])); push!(es, e)
            w0 = ((u - 1) ÷ 32) * 32 + 1; win = acts[w0:min(w0 + 31, H)]
            entropy4(win) >= 0.5 && push!(es_var, e)
            if name == "B2"; tot += 1; hit += haskey(m.tab2, (BitVector(rec.R[u, :]), rec.A[u])); end
        end
    end
    ev[name] = Dict("mean_e" => sum(es) / length(es), "n" => length(es), "mean_e_varied" => isempty(es_var) ? nothing : sum(es_var) / length(es_var),
                    "n_varied" => length(es_var), "coverage" => name == "B2" ? hit / tot : nothing)
end
res["baselines_explore"] = ev
res["increment_B2p_minus_B2_varied"] = ev["B2p"]["mean_e_varied"] === nothing ? nothing : ev["B2p"]["mean_e_varied"] - ev["B2"]["mean_e_varied"]
# O1 evaluator check on the baseline second-order predictor (not a claim): ehat = train mean of e by (R_u, A_u) under B2
etab = Dict{Tuple{BitVector,Int},Vector{Float64}}(); etrain = Float64[]
for k in keysof(TRAIN), u in W:H-1
    rec = recs[k]; rec.alive[u+1] || continue
    e = brier(predict(m, "B2", rec, u), Float64.(rec.R[u+1, :])); push!(etrain, e); push!(get!(etab, (BitVector(rec.R[u, :]), rec.A[u]), Float64[]), e)
end
bmean = sum(etrain) / length(etrain); ee = Float64[]; eh = Float64[]
for k in keysof(EXPLORE), u in W:H-1
    rec = recs[k]; rec.alive[u+1] || continue
    push!(ee, brier(predict(m, "B2", rec, u), Float64.(rec.R[u+1, :]))); kk = (BitVector(rec.R[u, :]), rec.A[u])
    push!(eh, haskey(etab, kk) ? sum(etab[kk]) / length(etab[kk]) : bmean)
end
res["O1_baseline_explore"] = o1(ee, eh, bmean)
res["evaluator_unit"] = Dict("o1_const_is_0" => o1([0.1, 0.3], [0.2, 0.2], 0.2) == 0.0, "o1_Lb0_undecided" => o1([0.2, 0.2], [0.1, 0.3], 0.2) === nothing,
                             "o1_hand" => isapprox(o1([0.0, 0.4], [0.1, 0.3], 0.2), 1 - 0.01 / 0.04), "brier_hand" => brier([0.5, 1.0], [1.0, 1.0]) == 0.125)
res["confirm_metrics_computed"] = false
write(get(ENV, "RES", joinpath(@__DIR__, "results-trm-data.json")), JSON.json(res))
println("replay ", res["replay"], " max acts ", res["max_acts_per_update"])
println("files ", Dict(k => (v["N"], v["seq_len"], v["readback"], v["source_times_ok"], v["labels_only_last9"]) for (k, v) in res["files"]))
println("future invariance ", all(values(fut)), " (", length(fut), ")  shift diag fails ", res["shift_diag_fails"])
println("baselines (explore) ", Dict(k => (round(v["mean_e"]; digits = 4), v["mean_e_varied"] === nothing ? nothing : round(v["mean_e_varied"]; digits = 4), v["n"], v["n_varied"]) for (k, v) in ev))
println("B2 coverage ", ev["B2"]["coverage"], "  increment (B2' - B2, varied windows) ", res["increment_B2p_minus_B2_varied"], "  O1 baseline ", res["O1_baseline_explore"])
