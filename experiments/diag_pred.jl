# Diagnostic (read-only, exploratory, item 152): why does the current act add almost nothing to the one-step prediction
# (S45: B2 0.0497 vs B2' 0.0498)? On S45's split (train 511-530, explore 531-540; the confirm seeds 541-560 are not run).
# (a) per-receptor Brier of B2/B2'; (b) how much the act is determined by the receptors (and the core): H(A | R), H(A | R, C);
# (c) horizons k: R_{u+k} from R_u alone, with the act at u, and with the counts of the acts u..u+k-1; (d) the answer to an act.
# No predictions: a diagnostic for the discussion (D-PRED), not a claim. Writes experiments/results-diag-pred.json.
ENV["SEEDS"] = ""; ENV["OUT"] = "/dev/null"
include(joinpath(@__DIR__, "g1_school.jl"))
using JSON
const TRAIN = 511:530; const EXPLORE = 531:540
const RN = ["r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "rb"]; const MN = ["m0", "m1", "m2"]
const POSTD = Ref{Any}(nothing); const WATCHD = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (st === WATCHD[] && (POSTD[] = (acting = copy(o.acting), answered = copy(o.answered))))
function record(s, p, sch)
    st = AS.initial_state(s, p); b = s.b; ri = [LC.unit(b, r) for r in RN]; mi = [LC.unit(b, m) for m in MN]; ci = [LC.unit(b, "c1"), LC.unit(b, "c2")]
    R = falses(H, 9); C = falses(H, 2); A = fill(4, H); ans = fill(-1, H); alive = falses(H)
    for u in 1:H
        WATCHD[] = st; POSTD[] = nothing; AS.step!(st, s, p, sch, Set{Int}()); WATCHD[] = nothing
        o = POSTD[]
        if o !== nothing
            act = [m for m in o.acting if m in mi]
            if !isempty(act)
                A[u] = findfirst(==(act[1]), mi)
                ans[u] = haskey(o.answered, act[1]) ? Int(o.answered[act[1]]) : -1   # -1: not a patch motor (m0) or none
            end
        end
        R[u, :] = st.active[ri]; C[u, :] = st.active[ci]; alive[u] = !st.dead
    end
    (R = R, C = C, A = A, ans = ans, alive = alive)
end
su = LBA.setup_with(H); p = su.params
recs = Dict{Symbol,Vector{Any}}(:train => Any[], :explore => Any[])
for (sp, rg) in ((:train, TRAIN), (:explore, EXPLORE)), seed in rg, cur in (:std, :swap)
    s = org_g1(seed, su, cur, school_perm(seed))
    for sch in su.survival; push!(recs[sp], record(s, p, sch)); end
end
lap(k, n) = (k + 1) / (n + 2)
"""A table predictor of the 9 receptors at u+k from key(rec, u), fit on train, Brier per receptor on explore."""
function table_eval(keyf, k)
    tab = Dict{Any,Tuple{Vector{Float64},Int}}(); on = zeros(9); n = 0
    for rec in recs[:train], u in 1:H-k
        rec.alive[u+k] || continue
        y = Float64.(rec.R[u+k, :]); on .+= y; n += 1
        kk = keyf(rec, u, k); a = get(tab, kk, (zeros(9), 0)); tab[kk] = (a[1] .+ y, a[2] + 1)
    end
    b0 = on ./ n; se = zeros(9); m = 0; seen = 0
    for rec in recs[:explore], u in 1:H-k
        rec.alive[u+k] || continue
        kk = keyf(rec, u, k); pr = haskey(tab, kk) ? (seen += 1; lap.(tab[kk][1], tab[kk][2])) : b0
        se .+= (pr .- rec.R[u+k, :]) .^ 2; m += 1
    end
    (per = se ./ m, mean = sum(se) / (9m), n = m, coverage = seen / m, keys = length(tab))
end
kR(rec, u, k) = BitVector(rec.R[u, :])
kRA(rec, u, k) = (BitVector(rec.R[u, :]), rec.A[u])
kRAk(rec, u, k) = (BitVector(rec.R[u, :]), Tuple(count(==(a), rec.A[u:u+k-1]) for a in 1:4))   # the acts over the horizon (a plan)
kRC(rec, u, k) = (BitVector(rec.R[u, :]), BitVector(rec.C[u, :]))
kRCAk(rec, u, k) = (BitVector(rec.R[u, :]), BitVector(rec.C[u, :]), Tuple(count(==(a), rec.A[u:u+k-1]) for a in 1:4))
kH4(rec, u, k) = (u < 4 ? nothing : BitVector(vec(rec.R[u-3:u, :])))                            # 4 steps of receptor history
kH4Ak(rec, u, k) = (u < 4 ? nothing : BitVector(vec(rec.R[u-3:u, :])), Tuple(count(==(a), rec.A[u:u+k-1]) for a in 1:4))
res = Dict{String,Any}("spec" => "diagnostic item 152 (D-PRED)", "train" => collect(TRAIN), "explore" => collect(EXPLORE))
# (a)(c)
hz = Dict{String,Any}()
for k in (1, 2, 4, 8, 16, 32), (nm, f) in (("R", kR), ("RA", kRA), ("RAk", kRAk), ("RC", kRC), ("RCAk", kRCAk), ("H4", kH4), ("H4Ak", kH4Ak))
    r = table_eval(f, k); hz["k$k-$nm"] = Dict("mean" => r.mean, "per" => r.per, "n" => r.n, "coverage" => r.coverage, "keys" => r.keys)
end
res["horizons"] = hz
# (b) H(A | key) on explore with the train table (plug-in, nats -> bits)
function cond_entropy(keyf)
    tab = Dict{Any,Vector{Int}}()
    for rec in recs[:train], u in 1:H; rec.alive[u] || continue; v = get!(tab, keyf(rec, u), zeros(Int, 4)); v[rec.A[u]] += 1; end
    hsum = 0.0; m = 0; unseen = 0
    for rec in recs[:explore], u in 1:H
        rec.alive[u] || continue; kk = keyf(rec, u)
        if !haskey(tab, kk); unseen += 1; continue; end
        v = tab[kk] .+ 0.5; pr = v ./ sum(v); hsum += -log2(pr[rec.A[u]]); m += 1
    end
    (bits = hsum / m, n = m, unseen = unseen)
end
pA = zeros(4); for rec in recs[:explore], u in 1:H; rec.alive[u] && (pA[rec.A[u]] += 1); end; pA ./= sum(pA)
res["act_marginal_explore"] = Dict(zip(["m0", "m1", "m2", "none"], pA))
res["H_A_marginal_bits"] = -sum(x -> x > 0 ? x * log2(x) : 0.0, pA)
res["H_A_given_R_bits"] = cond_entropy((rec, u) -> BitVector(rec.R[u, :]))
res["H_A_given_RC_bits"] = cond_entropy((rec, u) -> (BitVector(rec.R[u, :]), BitVector(rec.C[u, :])))
res["H_A_given_R_prevA_bits"] = cond_entropy((rec, u) -> (BitVector(rec.R[u, :]), u > 1 ? rec.A[u-1] : 0))
# (d) the answer to a patch act
na = count(x -> x >= 0, vcat([rec.ans for rec in recs[:explore]]...)); n1 = count(==(1), vcat([rec.ans for rec in recs[:explore]]...))
res["answer"] = Dict("patch_acts" => na, "answered" => n1)
r5 = 5
res["r5_floor_note"] = "r5 is a fair coin each step (core/circuit.jl:15): its Brier is >= 0.25 under any predictor, i.e. >= 0.0278 of the 9-receptor mean"
write(joinpath(@__DIR__, "results-diag-pred.json"), JSON.json(res))
println("act marginal ", res["act_marginal_explore"], "  H(A) ", round(res["H_A_marginal_bits"]; digits = 3), "  H(A|R) ", res["H_A_given_R_bits"],
        "  H(A|R,C) ", res["H_A_given_RC_bits"], "  H(A|R,A_prev) ", res["H_A_given_R_prevA_bits"])
println("answer ", res["answer"])
for k in (1, 2, 4, 8, 16, 32)
    println("k=$k ", join(["$nm $(round(hz["k$k-$nm"]["mean"]; digits = 4)) (cov $(round(hz["k$k-$nm"]["coverage"]; digits = 2)))" for nm in ("R", "RA", "RAk", "RC", "RCAk", "H4", "H4Ak")], "  "))
end
for nm in ("R", "RA", "RAk"); println("per receptor k=1 $nm ", round.(hz["k1-$nm"]["per"]; digits = 3)); end
for nm in ("R", "RAk"); println("per receptor k=8 $nm ", round.(hz["k8-$nm"]["per"]; digits = 3)); end
