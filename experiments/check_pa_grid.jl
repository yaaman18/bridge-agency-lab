# S47 judgment (discussion/specs/S47-synth-grid.md r3 §5, §7; predictions-pa-grid.md). Reads results-pa-grid-<mode>.json.
# Usage (from experiments/): julia --project=.. check_pa_grid.jl main    -> results-pa-grid-main-check.json / .out
#                            julia --project=.. check_pa_grid.jl smoke   -> runs on the smoke file; writes the full output
#                            to a temporary directory and prints only the structure (no effect or p value is shown).
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
include(joinpath(@__DIR__, "synth_world.jl"))

const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode smoke | main")
const T0 = 800; const STEPS = 10000; const TAUS = (500, 2000, 9200); const MAIN = 2
const NPERM = 10000; const PERMSEED = 4747
const LAWS = ("L2", "L2+SF")

recs = Dict{String,Any}()
const INFILE = length(ARGS) >= 2 ? ARGS[2] : joinpath(LAB, "experiments", "results-pa-grid-$(MODE).json")
for l in eachline(INFILE)
    d = try JSON.parse(l) catch; nothing end
    d === nothing || (recs[d["key"]] = d)
end
pkeys = unique([split(k, " | ")[1] for k in keys(recs)])

# ---- (b): the row x column table ----
mat(rows) = (n = length(rows); [Float64(rows[i][j]) for i in 1:n, j in 1:n])
function dstat(S, perm)
    n = size(S, 1); dg = sum(S[perm[j], j] for j in 1:n)
    return dg / n - (sum(S) - dg) / (n * n - n)
end
function shuffle_in!(v, idx, r)
    for a in length(idx):-1:2
        b = floor(Int, r() * a) + 1
        v[idx[a]], v[idx[b]] = v[idx[b]], v[idx[a]]
    end
end
# strata: a list of index groups (one group = the plain permutation of rows)
function permtest(S, strata)
    n = size(S, 1); D = dstat(S, collect(1:n)); r = Mulberry(PERMSEED); ge = 0; le = 0; v = collect(1:n)
    for _ in 1:NPERM
        v .= 1:n
        for g in strata; shuffle_in!(v, g, r); end
        x = dstat(S, v); x >= D && (ge += 1); x <= D && (le += 1)
    end
    return D, (ge + 1) / (NPERM + 1), (le + 1) / (NPERM + 1)
end
judge_b(D, p, prev) = D > 0 && p <= 0.05 ? "成立" : D < 0 && prev <= 0.05 ? "逆" : "検出不能"
# the intervention condition (S28b): the median over window pairs of the share of steps in [T0, T0 + tau) where the yields differ
function mismatch(pt, evals, tau)
    g = Dict(u => synth_table(u, pt["P"], pt["sigma"], pt["L"], Float64(pt["M"])) for u in evals); f = Float64[]
    for a in eachindex(evals), b in a+1:length(evals)
        ga = g[evals[a]]; gb = g[evals[b]]
        push!(f, count(s -> ga[s, 1] != gb[s, 1] || ga[s, 2] != gb[s, 2], 1:tau) / tau)
    end
    sort!(f); m = length(f)
    return isodd(m) ? f[(m + 1) ÷ 2] : (f[m ÷ 2] + f[m ÷ 2 + 1]) / 2
end
function table_b(rec, name, x, strata)
    S = mat(rec[name][x]); D, p, pr = permtest(S, [collect(1:size(S, 1))])
    out = Dict{String,Any}("D" => D, "p" => p, "prev" => pr, "judge" => judge_b(D, p, pr))
    if strata !== nothing
        nperm = prod(factorial(big(length(g))) for g in strata)
        if nperm < 20
            out["strat"] = "判定できず"
        else
            Ds, ps, prs = permtest(S, strata); out["strat"] = Dict("p" => ps, "prev" => prs, "judge" => judge_b(Ds, ps, prs), "nperm" => string(nperm))
        end
    end
    return out
end

# ---- (c): sign tests ----
function signtest(a, b)
    pos = count(i -> a[i] > b[i], eachindex(a)); neg = count(i -> a[i] < b[i], eachindex(a)); n = pos + neg
    n < 8 && return Dict("pos" => pos, "neg" => neg, "judge" => "検出不能")
    k = min(pos, neg); p = min(1.0, 2 * sum(binomial(big(n), i) for i in 0:k) / big(2)^n)
    j = p <= 0.05 ? (pos > neg ? "上積みあり" : "上積みなし") : "検出不能"
    return Dict("pos" => pos, "neg" => neg, "p" => Float64(p), "judge" => j)
end
life(r) = r["death"] === nothing ? STEPS : r["death"]
size_at(r, x) = r["countAt"][x]
function compare_c(A, B, us; x = MAIN)
    a = [size_at(A[u], x) for u in us]; b = [size_at(B[u], x) for u in us]
    dead = [u for u in us if A[u]["death"] !== nothing || B[u]["death"] !== nothing]
    return Dict("size" => signtest(a, b), "life" => signtest([life(A[u]) for u in dead], [life(B[u]) for u in dead]), "n" => length(us))
end
pred_c(K, j) = K === nothing ? (j == "上積みなし" ? "一致" : j == "上積みあり" ? "不一致" : "判定できず") :
               K == 2000 ? (j == "上積みあり" ? "一致" : j == "上積みなし" ? "不一致" : "判定できず") : "予測なし"
mean(v) = isempty(v) ? NaN : sum(v) / length(v)
repmeans(R, us) = Dict(k => (k == "yieldMean" ? [mean([R[u]["rep"][k][i] for u in us]) for i in 1:2] : mean([Float64(R[u]["rep"][k]) for u in us]))
                       for k in ("yieldMean", "capSteps", "nActs", "answered", "moved", "spent", "upkeep"))

rows = Any[]
for pk in sort(pkeys)
    gk = pk * " | GREEDY"; haskey(recs, gk) || continue
    g = recs[gk]; pt = g["point"]; evals = [string(u) for u in g["evals"]]; ev = Int.(g["evals"])
    mm = [mismatch(pt, ev, tau) for tau in TAUS]
    G = g["GREEDY"]
    gb = [table_b(g, "table", x, nothing) for x in eachindex(TAUS)]; gnc = table_b(g, "nc", MAIN, nothing)
    for law in LAWS
        lk = pk * " | " * law; haskey(recs, lk) || continue
        r = recs[lk]; O = r["ORG"]; F = r["ORG-FIX"]; Sl = r["ORG-SIL"]; KC = r["GREEDY-KC"]
        types = [O[u]["type"] for u in evals]; tset = unique(types)
        strata = [[i for i in eachindex(types) if types[i] == t] for t in tset]
        ob = [table_b(r, "table", x, x == MAIN ? strata : nothing) for x in eachindex(TAUS)]
        onc = table_b(r, "nc", MAIN, nothing)
        intervene = mm[MAIN] >= 0.2
        aliveOrg = [u for u in evals if size_at(O[u], MAIN) > 0]
        orgDeadKC = [u for u in evals if size_at(O[u], MAIN) == 0]
        cG = compare_c(O, G, evals); cKC = compare_c(O, KC, evals); cKCsens = compare_c(O, KC, aliveOrg)
        cFIX = compare_c(O, F, evals); cFG = compare_c(F, G, evals)
        pa1 = [(u, size_at(Sl[u], MAIN), size_at(O[u], MAIN)) for u in evals]
        push!(rows, Dict{String,Any}("point" => pk, "pt" => pt, "law" => law, "mismatch" => mm, "intervene" => intervene,
            "types" => length(tset), "aliveORG" => length(aliveOrg),
            "b_ORG" => ob, "b_GREEDY" => gb, "nc_ORG" => onc, "nc_GREEDY" => gnc,
            "judge_b_ORG" => intervene ? ob[MAIN]["judge"] : "判定不能", "judge_b_GREEDY" => intervene ? gb[MAIN]["judge"] : "判定不能",
            "Delta" => ob[MAIN]["D"] - gb[MAIN]["D"],
            "c_ORG_GREEDY" => cG, "c_pred" => pred_c(pt["K"], cG["size"]["judge"]), "c_ORG_KC" => cKC, "c_ORG_KC_sens_aliveORG" => cKCsens, "orgDeadBeforeTau" => length(orgDeadKC),
            "c_ORG_FIX" => cFIX, "c_FIX_GREEDY" => cFG,
            "agreeFIX" => mean([F[u]["agree"] for u in evals]),
            "agreeFIXAlive" => mean([F[u]["agreeAlive"] for u in evals if F[u]["agreeAlive"] !== nothing]),
            "agreeFIXAliveExcluded" => count(u -> F[u]["agreeAlive"] === nothing, evals), "keptConstFIX" => all(F[u]["keptConst"] for u in evals),
            "pa1_viol" => [x for x in pa1 if x[2] > x[3] || (x[2] == x[3] && x[3] > 0)],
            "rep" => Dict("ORG" => repmeans(O, evals), "ORG-FIX" => repmeans(F, evals), "ORG-SIL" => repmeans(Sl, evals),
                          "GREEDY" => repmeans(G, evals), "GREEDY-KC" => repmeans(KC, evals)),
            "keptRLE" => Dict(u => O[u]["keptRLE"] for u in evals)))
    end
end

# ---- NC and the predictions ----
ncO = count(x -> x["nc_ORG"]["p"] <= 0.05, rows); ncG = count(x -> x["nc_GREEDY"]["p"] <= 0.05, rows) ÷ 2   # GREEDY tables are shared by the two laws
nTab = length(rows); nGTab = nTab ÷ 2
ncBad = ncO > 0.15 * nTab
isK(x, k) = x["pt"]["K"] == k
isS0(x) = x["pt"]["sigma"] == 0
sel(f) = [x for x in rows if f(x)]
st(ok) = ok ? "成立" : "外れ"
PA = Dict{String,Any}()
PA["PA1"] = st(all(isempty(x["pa1_viol"]) for x in rows))
b8 = sel(x -> isK(x, nothing) && isS0(x))
PA["PA2"] = ncBad ? "確かめられず（NC 要調査）" : st(count(x -> x["judge_b_ORG"] == "成立", b8) >= 5)
PA["PA2_sigma2L300"] = Dict(j => count(x -> x["judge_b_ORG"] == j, sel(x -> x["pt"]["sigma"] == 2 && x["pt"]["L"] == 300)) for j in ("成立", "逆", "検出不能", "判定不能"))
for law in LAWS
    PA["PA3 " * law] = st(count(x -> x["c_ORG_GREEDY"]["size"]["judge"] == "上積みあり", sel(x -> x["law"] == law && isK(x, nothing))) == 0)
    k2 = sel(x -> x["law"] == law && isK(x, 2000))
    PA["PA4 " * law] = st(count(x -> x["c_ORG_GREEDY"]["size"]["judge"] == "上積みあり", k2) > length(k2) / 2)
    PA["PA4 " * law * " no-gain majority"] = count(x -> x["c_ORG_GREEDY"]["size"]["judge"] == "上積みなし", k2) > length(k2) / 2
end
PA["PA5"] = any(x -> isnan(x["agreeFIXAlive"]), b8) ? "確かめられず（両方が生きている歩のない点）" :
    st(all(x["agreeFIX"] >= 0.9 for x in b8) && all(x["agreeFIXAlive"] >= 0.9 for x in b8))
g4 = [x for x in b8 if x["law"] == LAWS[1]]
PA["PA6"] = ncBad ? "確かめられず（NC 要調査）" : st(count(x -> x["judge_b_GREEDY"] == "成立", g4) >= 3)
kn = sel(x -> isK(x, nothing))
PA["PA7"] = st(count(x -> x["c_ORG_KC"]["size"]["judge"] == "上積みなし", kn) < count(x -> x["c_ORG_GREEDY"]["size"]["judge"] == "上積みなし", kn))
PA["NC"] = Dict("ORG" => "$(ncO)/$(nTab)", "GREEDY" => "$(ncG)/$(nGTab)", "ORG要調査" => ncBad, "GREEDY要調査" => ncG > 0.15 * nGTab)
PA["KC three-way"] = Dict(law => Dict(j => count(x -> x["c_ORG_KC"]["size"]["judge"] == j, sel(x -> x["law"] == law)) for j in ("上積みあり", "上積みなし", "検出不能")) for law in LAWS)

res = Dict("rows" => rows, "predictions" => PA, "nperm" => NPERM, "permseed" => PERMSEED)
fmt(x) = x isa AbstractFloat ? string(round(x; digits = 3)) : string(x)
lines = String[]
for x in rows
    push!(lines, "$(rpad(x["point"], 28)) $(rpad(x["law"], 6)) types $(x["types"]) aliveORG $(x["aliveORG"]) mismatch $(fmt(x["mismatch"][MAIN]))  " *
        "b ORG D $(fmt(x["b_ORG"][MAIN]["D"])) p $(fmt(x["b_ORG"][MAIN]["p"])) $(x["judge_b_ORG"])  b GREEDY D $(fmt(x["b_GREEDY"][MAIN]["D"])) $(x["judge_b_GREEDY"])  Δ $(fmt(x["Delta"]))  " *
        "c $(x["c_ORG_GREEDY"]["size"]["judge"])/$(x["c_pred"]) life $(x["c_ORG_GREEDY"]["life"]["judge"])  KC $(x["c_ORG_KC"]["size"]["judge"])  FIX $(x["c_ORG_FIX"]["size"]["judge"]) agree $(fmt(x["agreeFIX"])) alive $(fmt(x["agreeFIXAlive"])) excl $(x["agreeFIXAliveExcluded"])  KC(sens) $(x["c_ORG_KC_sens_aliveORG"]["size"]["judge"])")
end
push!(lines, "predictions: " * JSON.json(PA))
if MODE == "main"
    write(joinpath(LAB, "experiments", "results-pa-grid-main-check.json"), JSON.json(res, 2))
    write(joinpath(LAB, "experiments", "results-pa-grid-main-check.out"), join(lines, "\n") * "\n")
    foreach(println, lines)
else
    d = mktempdir(); write(joinpath(d, "check.json"), JSON.json(res)); write(joinpath(d, "check.out"), join(lines, "\n") * "\n")
    println("check ran on $(MODE): $(length(rows)) point x law rows, $(length(PA)) prediction entries, full output (not to be read) in $(d)")
    println("row keys: ", join(sort(collect(keys(rows[1]))), ", "))
    println("prediction keys: ", join(sort(collect(keys(PA))), ", "))
end
