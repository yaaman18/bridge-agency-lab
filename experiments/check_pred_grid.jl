# S46 checker (spec discussion/specs/S46-pred-grid.md r2 §3, §5): gates, and on the confirm stage the primary comparisons.
# Usage: STAGE=smoke|explore|confirm julia --project=.. check_pred_grid.jl
using JSON, SHA
const DIR = @__DIR__
const STAGE = get(ENV, "STAGE", "smoke")
R = JSON.parsefile(joinpath(DIR, "results-pred-grid-$STAGE.json"))
gates = Tuple{String,Bool}[]
gate(n, ok) = (push!(gates, (n, ok)); println("GATE ", ok ? "ok  " : "FAIL", " ", n))
const FREEZE = joinpath(DIR, STAGE == "confirm" ? "freeze-pred-grid.txt" : "freeze-pred-grid-smoke.txt")
for l in readlines(FREEZE)
    (startswith(l, "#") || isempty(strip(l))) && continue
    h, f = split(l; limit = 2); f = strip(f)
    gate("freeze sha $f", bytes2hex(sha256(read(joinpath(DIR, f)))) == h)
end
rp = R["replay"]; nexp = 8 * count(s -> s <= 540, vcat(R["train"], R["explore"], R["confirm"]))
gate("replay: natural runs match g1_school.jl's record (seeds <= 540: $nexp)", rp["checked"] == nexp && rp["match"] == nexp)
gate("the natural branch equals the natural run for all its updates and the death time", R["natural_branch_equal"]["n"] > 0 && R["natural_branch_equal"]["ok"] == R["natural_branch_equal"]["n"])
sl = R["silence"]
gate("mX only: no other motor acts in any branch; all silenced: no act", sl["n"] > 0 && sl["ok"] == sl["n"] && sl["allsil_no_act"])
gate("negative: the m0-only plan without silencing fails the silence gate, at every fork whose natural branch has an act of m1 or m2 ($(length(sl["negative_nosil_caught"])) forks)", !isempty(sl["negative_nosil_caught"]) && all(sl["negative_nosil_caught"]))
gate("common noise: r5 equal across the 5 plans on every update where all are alive (compared > 0)", R["r5_common"]["compared_updates"] > 0 && R["r5_common"]["mismatch"] == 0)
gate("key source times <= t; the negative (a key reading t+1) is caught", R["key_times_ok"] && R["key_times_negative_caught"])
gate("leak: tables unchanged when non-train records are rewritten" * (R["leak_tables_unchanged"] === nothing ? " (no non-train seeds in this stage: not tested)" : ""),
     R["leak_tables_unchanged"] === nothing ? STAGE == "smoke" : R["leak_tables_unchanged"])
gate("bootstrap unit: all positive excludes 0, half and half includes 0", all(values(R["boot_unit"])))
gate("the confirm losses only on the confirm stage", R["confirm_computed"] == (STAGE == "confirm") && (STAGE == "confirm") == haskey(R, "primary_confirm"))
if haskey(R, "primary_confirm") || haskey(R, "primary_explore")
    pk = haskey(R, "primary_confirm") ? "primary_confirm" : "primary_explore"; P = R[pk]
    ss = [P["PH4"][k]["n"] for k in ("S5", "S10", "S20")]
    gate("PH4: the same evaluation examples for the three training sizes ($pk)", length(unique(ss)) == 1 && ss[1] == P["PH2"]["n"])
end
allok = all(last, gates)
v(x) = x === nothing ? "判定不能" : x ? "的中" : "外れ"
if STAGE == "confirm"
    P = R["primary_confirm"]
    ph1 = P["PH1"]["pairs"] == 0 ? nothing : P["PH1"]["frac_k8"] > P["PH1"]["frac_k1"]
    println("PH1 (C2): pairs $(P["PH1"]["pairs"]), rb disagreement k=1 $(P["PH1"]["frac_k1"]) k=8 $(P["PH1"]["frac_k8"]) by kind $(P["PH1"]["by_kind"]): ", v(ph1))
    ph2 = P["PH2"]["diff_mean"] >= 0.005 && P["PH2"]["ci"][1] > 0
    println("PH2 (C3): L_H4 $(P["PH2"]["L_H4"]) L_H4plan $(P["PH2"]["L_H4plan"]) diff $(P["PH2"]["diff_mean"]) CI $(P["PH2"]["ci"]) n $(P["PH2"]["n"]): ", v(ph2))
    ph3 = P["PH3"]["L_R"] - P["PH3"]["L_H4"] >= 0.05
    println("PH3 (C1): r6 k=1 L_R $(P["PH3"]["L_R"]) L_H4 $(P["PH3"]["L_H4"]): ", v(ph3))
    L = [P["PH4"][k]["L"] for k in ("S5", "S10", "S20")]
    ph4 = L[1] >= L[2] >= L[3] && L[1] - L[3] >= 0.002
    println("PH4 (C4): L(S5) $(L[1]) L(S10) $(L[2]) L(S20) $(L[3]): ", v(ph4))
    p5 = P["PH5"]; ph5 = p5["diff_mean"] >= 0.005 && p5["ci"][1] > 0
    println("PH5 (C3, added after the exploration): rb k=32 L_R $(p5["L_R"]) L_Rplan $(p5["L_Rplan"]) diff $(p5["diff_mean"]) CI $(p5["ci"]) n $(p5["n"]): ", v(ph5))
    println("each primary is judged on its own; no overall success is declared (no multiplicity correction is claimed)")
    nt = P["natural_transfer"]
    println("natural transfer (only if PH2 holds): n $(nt["n"]) L_H4 $(nt["L_H4"]) L_H4plan $(nt["L_H4plan"]) -> ",
            !ph2 ? "（PH2 不成立のため問わない）" : nt["L_H4plan"] < nt["L_H4"] ? "自然条件へ移行した" : "自然条件への移行は成立しなかった")
end
println("all gates: ", allok ? "ok" : "FAIL"); allok || exit(1)
