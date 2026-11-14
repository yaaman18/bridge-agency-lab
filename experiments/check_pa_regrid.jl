# S47b judgment (discussion/specs/S47b-regrid.md r1 §3-§5; predictions-pa-regrid.md PB1-PB3). Reads results-pa-regrid-<mode>.json.
# Usage (from experiments/): julia --project=.. check_pa_regrid.jl main    -> results-pa-regrid-main-check.json / .out
#                            julia --project=.. check_pa_regrid.jl smoke   -> runs on the smoke file; writes the full output
#                            to a temporary directory and prints only the structure (no effect or p value is shown).
# signtest and compare_c are copied from check_pa_grid.jl (S47 r3 §5 (c)).
using JSON

const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode smoke | main")
const T0 = 800; const STEPS = 10000; const TAUS = (2000, 4000, 9200)
const LAWS = ("L2", "L2+SF")
# candidates: (name, K, index of the reading step in TAUS)
const CANDS = (("C1", 2000, 2), ("C2", 2000, 3), ("C3", 1000, 1))
const JUDGES = ("上積みあり", "上積みなし", "検出不能")

recs = Dict{String,Any}()
const INFILE = joinpath(LAB, "experiments", "results-pa-regrid-$(MODE).json")
for l in eachline(INFILE)
    d = try JSON.parse(l) catch; nothing end
    d === nothing || (recs[d["key"]] = d)
end
pkeys = unique([split(k, " | ")[1] for k in keys(recs)])

function signtest(a, b)
    pos = count(i -> a[i] > b[i], eachindex(a)); neg = count(i -> a[i] < b[i], eachindex(a)); n = pos + neg
    n < 8 && return Dict("pos" => pos, "neg" => neg, "judge" => "検出不能")
    k = min(pos, neg); p = min(1.0, 2 * sum(binomial(big(n), i) for i in 0:k) / big(2)^n)
    j = p <= 0.05 ? (pos > neg ? "上積みあり" : "上積みなし") : "検出不能"
    return Dict("pos" => pos, "neg" => neg, "p" => Float64(p), "judge" => j)
end
life(r) = r["death"] === nothing ? STEPS : r["death"]
size_at(r, x) = r["countAt"][x]
function compare_c(A, B, us; x)
    a = [size_at(A[u], x) for u in us]; b = [size_at(B[u], x) for u in us]
    dead = [u for u in us if A[u]["death"] !== nothing || B[u]["death"] !== nothing]
    return Dict("size" => signtest(a, b), "life" => signtest([life(A[u]) for u in dead], [life(B[u]) for u in dead]), "n" => length(us))
end
mean(v) = isempty(v) ? NaN : sum(v) / length(v)
repmeans(R, us) = Dict(k => (k == "yieldMean" ? [mean([R[u]["rep"][k][i] for u in us]) for i in 1:2] : mean([Float64(R[u]["rep"][k]) for u in us]))
                       for k in ("yieldMean", "capSteps", "nActs", "answered", "moved", "spent", "upkeep"))

# one row per (point-K, law, reading step); K none is read at all three steps, K 2000 at T0+4000 and T0+9200, K 1000 at T0+2000
function readings(K)
    K === nothing && return [("ref", x) for x in eachindex(TAUS)]
    return [(c[1], c[3]) for c in CANDS if c[2] == K]
end
rows = Any[]
for pk in sort(pkeys)
    gk = pk * " | GREEDY"; haskey(recs, gk) || continue
    g = recs[gk]; pt = g["point"]; K = pt["K"]; evals = [string(u) for u in g["evals"]]
    G = g["GREEDY"]
    for law in LAWS
        lk = pk * " | " * law; haskey(recs, lk) || continue
        r = recs[lk]; O = r["ORG"]; F = r["ORG-FIX"]; KC = r["GREEDY-KC"]
        types = unique([O[u]["type"] for u in evals])
        for (cand, x) in readings(K)
            aliveOrg = [u for u in evals if size_at(O[u], x) > 0]
            push!(rows, Dict{String,Any}("point" => pk, "pt" => pt, "law" => law, "cand" => cand, "readStep" => T0 + TAUS[x],
                "types" => length(types),
                "alive" => Dict("ORG" => length(aliveOrg), "ORG-FIX" => count(u -> size_at(F[u], x) > 0, evals),
                                "GREEDY" => count(u -> size_at(G[u], x) > 0, evals), "GREEDY-KC" => count(u -> size_at(KC[u], x) > 0, evals)),
                "crossBefore" => Dict("ORG" => unique([O[u]["crossBefore"][x] for u in evals]), "ORG-FIX" => unique([F[u]["crossBefore"][x] for u in evals]),
                                      "GREEDY" => unique([G[u]["crossBefore"][x] for u in evals]), "GREEDY-KC" => unique([KC[u]["crossBefore"][x] for u in evals])),
                "c_ORG_GREEDY" => compare_c(O, G, evals; x = x), "c_ORG_KC" => compare_c(O, KC, evals; x = x),
                "c_ORG_KC_sens_aliveORG" => compare_c(O, KC, aliveOrg; x = x), "c_ORG_FIX" => compare_c(O, F, evals; x = x),
                "rep" => Dict("ORG" => repmeans(O, evals), "ORG-FIX" => repmeans(F, evals), "GREEDY" => repmeans(G, evals), "GREEDY-KC" => repmeans(KC, evals))))
        end
    end
end

sel(f) = [x for x in rows if f(x)]
st(ok) = ok ? "成立" : "外れ"
jc(xs, key) = Dict(j => count(x -> x[key]["size"]["judge"] == j, xs) for j in JUDGES)
jl(xs, key) = Dict(j => count(x -> x[key]["life"]["judge"] == j, xs) for j in JUDGES)
# the tables: candidate (and the K-none reference per reading step) x law
TAB = Dict{String,Any}()
for law in LAWS
    for (c, _, _) in CANDS
        xs = sel(x -> x["law"] == law && x["cand"] == c)
        TAB[c * " " * law] = Dict("n" => length(xs), "ORG vs GREEDY" => jc(xs, "c_ORG_GREEDY"), "ORG vs GREEDY-KC" => jc(xs, "c_ORG_KC"),
            "ORG vs GREEDY-KC (ORG alive)" => jc(xs, "c_ORG_KC_sens_aliveORG"), "ORG vs ORG-FIX" => jc(xs, "c_ORG_FIX"),
            "life ORG vs GREEDY" => jl(xs, "c_ORG_GREEDY"), "life ORG vs GREEDY-KC" => jl(xs, "c_ORG_KC"), "life ORG vs ORG-FIX" => jl(xs, "c_ORG_FIX"))
    end
    for x in eachindex(TAUS)
        xs = sel(r -> r["law"] == law && r["cand"] == "ref" && r["readStep"] == T0 + TAUS[x])
        TAB["K none T0+$(TAUS[x]) " * law] = Dict("n" => length(xs), "ORG vs GREEDY" => jc(xs, "c_ORG_GREEDY"), "ORG vs GREEDY-KC" => jc(xs, "c_ORG_KC"),
            "ORG vs GREEDY-KC (ORG alive)" => jc(xs, "c_ORG_KC_sens_aliveORG"), "ORG vs ORG-FIX" => jc(xs, "c_ORG_FIX"),
            "life ORG vs GREEDY" => jl(xs, "c_ORG_GREEDY"), "life ORG vs GREEDY-KC" => jl(xs, "c_ORG_KC"), "life ORG vs ORG-FIX" => jl(xs, "c_ORG_FIX"))
    end
end

PB = Dict{String,Any}()
for law in LAWS, (c, _, _) in CANDS
    t = TAB[c * " " * law]
    PB["PB1 " * c * " " * law] = st(t["ORG vs GREEDY"]["上積みあり"] > 10)
    PB["PB3 " * c * " " * law] = st(t["ORG vs GREEDY-KC"]["上積みなし"] == 0)
end
for law in LAWS, x in eachindex(TAUS)
    PB["PB2 K none T0+$(TAUS[x]) " * law] = st(TAB["K none T0+$(TAUS[x]) " * law]["ORG vs GREEDY"]["上積みあり"] == 0)
end
# spec §5: which row of "result -> what changes" applies (6 cells = 3 candidates x 2 laws, 20 points each)
cells = [TAB[c * " " * law]["ORG vs GREEDY"] for (c, _, _) in CANDS for law in LAWS]
row5 = all(t -> t["上積みあり"] > 10, cells) ? "3 案とも、両法則で K ありの過半が上積みあり" :
       all(t -> t["上積みなし"] > 10, cells) ? "3 案とも、上積みなしが過半" : "割れる・検出不能が過半"
PB["spec5 row"] = row5
# R2 on the main records: crossings before each reading step for every arm and window
r2want(K, x) = K === nothing ? 0 : count(t -> t > T0 && (t - T0) % K == 0, 0:T0+TAUS[x]-1)
PB["R2 on main records"] = all(x -> all(a -> x["crossBefore"][a] == [r2want(x["pt"]["K"], findfirst(==(x["readStep"] - T0), TAUS))], keys(x["crossBefore"])), rows)

res = Dict("rows" => rows, "tables" => TAB, "predictions" => PB)
fmt(x) = x isa AbstractFloat ? string(round(x; digits = 3)) : string(x)
cj(c) = "$(c["size"]["judge"]) ($(c["size"]["pos"])+/$(c["size"]["neg"])-)"
lines = String[]
for x in sort(rows; by = r -> (r["cand"], r["readStep"], r["law"], r["point"]))
    push!(lines, "$(rpad(x["cand"], 4)) T$(x["readStep"]) $(rpad(x["point"], 26)) $(rpad(x["law"], 6)) types $(x["types"]) alive $(JSON.json(x["alive"]))  " *
        "G $(cj(x["c_ORG_GREEDY"])) life $(x["c_ORG_GREEDY"]["life"]["judge"])  KC $(cj(x["c_ORG_KC"])) KC(sens) $(x["c_ORG_KC_sens_aliveORG"]["size"]["judge"])  FIX $(cj(x["c_ORG_FIX"]))")
end
for k in sort(collect(keys(TAB))); push!(lines, "table $(rpad(k, 22)) " * JSON.json(TAB[k])); end
push!(lines, "predictions: " * JSON.json(PB))
if MODE == "main"
    write(joinpath(LAB, "experiments", "results-pa-regrid-main-check.json"), JSON.json(res, 2))
    write(joinpath(LAB, "experiments", "results-pa-regrid-main-check.out"), join(lines, "\n") * "\n")
    foreach(println, lines)
else
    d = mktempdir(); write(joinpath(d, "check.json"), JSON.json(res)); write(joinpath(d, "check.out"), join(lines, "\n") * "\n")
    println("check ran on $(MODE): $(length(rows)) rows, $(length(TAB)) tables, $(length(PB)) prediction entries, full output (not to be read) in $(d)")
    println("row keys: ", join(sort(collect(keys(rows[1]))), ", "))
    println("prediction keys: ", join(sort(collect(keys(PB))), ", "))
    println("R2 on the smoke records: ", PB["R2 on main records"])
end
