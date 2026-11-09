# S2 check (spec discussion/specs/S2-body-dn.md r2 §3, §5): reads experiments/results-dn-body-swap.json written by
# dn_body_swap.jl and exits 0 iff the seeds are exactly 1..10, the horizons are 294, 392, 588, S2-1, S2-2 and S2-7 hold
# for every seed and horizon, and the negative controls were detected.
# Per seed it shows the choice, D and the reading of N (S2-5) of the two arms and, if they differ, "H の支持（その観測）";
# a seed that does not pass the contract is shown as "除外" with the reason (display only, not in the exit code).
# RULE=current reads results-dn-body-swap-current.json and requires its "rules.rule" to be current (S3-1); RULE=old (default,
# the file as S2) reads results-dn-body-swap.json, whose "rules" carry the old rule (no "rule" key: derived as old).
# S4-1/S4-2: RULE=sf reads results-dn-body-swap-sf.json, requires its "rules.rule" to be sf, its seeds exactly 21..30 and
# its "rules" to carry sed_fade = true and KC_trial = 0.0015. Per seed and H it also shows whether the seed is
# "H∧D∧N の例" (S4-5: H supported, both arms D true and N tested_true; display only, not in the exit code).
# A shortened run (SEEDS/HORIZONS) is expected to exit 1.
# Usage: cd experiments && julia --project=.. check_dn_body_swap.jl; RULE=sf julia --project=.. check_dn_body_swap.jl
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))

const ASKED = get(ENV, "RULE", "old")
const FILE = ASKED == "current" ? "results-dn-body-swap-current.json" :
             ASKED == "old" ? "results-dn-body-swap.json" :
             ASKED == "sf" ? "results-dn-body-swap-sf.json" : error("check_dn_body_swap: RULE must be old, current or sf, got $ASKED")
res = JSON.parsefile(joinpath(LAB, "experiments", FILE))
# claude-lab 2026-11-06: the file's recorded rule must be the asked one (the S2 record has no "rule" key and is old)
const RULE = get(get(res, "rules", Dict()), "rule", "old")
const cycles_ok = RULE == ASKED
println("file experiments/$FILE; rules.rule = ", get(get(res, "rules", Dict()), "rule", nothing), " matches RULE: ", cycles_ok)
const ASKED_SEEDS = ASKED == "sf" ? collect(21:30) : collect(1:10)
seeds_ok = sort(Int.(res["seeds"])) == ASKED_SEEDS && length(res["seeds"]) == 10
hs_ok = sort(Int.(res["horizons"])) == [294, 392, 588] && length(res["horizons"]) == 3
runs = Dict((Int(x["H"]), Int(x["seed"])) => x for x in res["runs"])
neg = get(res, "negative_control_detected", false) === true
# S4-1: the sf record carries the rule's values under "rules" (read as keys of the record)
const RULEREC = get(res, "rules", Dict())
sf_rules_ok = ASKED != "sf" || (get(RULEREC, "sed_fade", nothing) === true && get(RULEREC, "KC_trial", nothing) == 0.0015)
println("seeds exactly ", first(ASKED_SEEDS), "..", last(ASKED_SEEDS), ": ", seeds_ok, "; horizons 294/392/588: ", hs_ok,
        "; negative controls detected: ", neg, ASKED == "sf" ? "; rules sed_fade/KC_trial: $sf_rules_ok" : "")
const ARMS = ("std", "swap")
# S4-5: sf supports H only through choices, D, T or N; retain the S2/S3 comparison.
const OBS = ASKED == "sf" ? ("choices", "differentiated", "value_tracking", "value_needed", "N") :
                           ("choices", "differentiated", "value_tracking", "value_needed", "N", "survival")

function contract_failures(x)
    f = String[]
    x["S2_1"]["ok"] || push!(f, "S2-1")
    x["S2_2"]["ok"] || push!(f, "S2-2")
    x["S2_7"]["ok"] || push!(f, "S2-7")
    f
end

all_ok = seeds_ok && hs_ok && length(res["runs"]) == 30 && cycles_ok && sf_rules_ok
hdn_examples = Dict{Int,Vector{Int}}()   # S4-5, display only
for H in [294, 392, 588], seed in ASKED_SEEDS
    x = get(runs, (H, seed), nothing)
    if x === nothing
        println("H=$H seed=$seed 除外（結果なし）"); global all_ok = false; continue
    end
    fail = contract_failures(x)
    global all_ok &= isempty(fail)
    stdv, swapv = x["obs"]["std"], x["obs"]["swap"]
    if !isempty(fail)
        for a in ARMS; println("H=$H seed=$seed $a 除外（契約を通らない: $(join(fail, ","))）"); end
        continue
    end
    name = Dict("choices" => "選択", "differentiated" => "D", "value_tracking" => "T", "value_needed" => "N", "N" => "N(区分)", "survival" => "生存")
    diffobs = [name[k] for k in OBS if stdv[k] != swapv[k]]
    tag = isempty(diffobs) ? " 支持なし（腕で同じ）" : " H の支持（$(join(diffobs, ","))）"
    for a in ARMS
        o = x["obs"][a]
        chs = join([k * "=" * v for (k, v) in sort(collect(o["choices"]))], " ")
        println(rpad("H=$H seed=$seed $a", 24), " 選択 ", rpad(chs, 34), " D=", o["differentiated"], " N=", o["N"],
                " T=", isempty(o["value_tracking"]) ? "[]" : join(o["value_tracking"], ","),
                a == "swap" ? tag : "")
    end
    if ASKED == "sf"
        # S4-5: H の支持（腕の観測が違う）があり、両腕とも D 真・N が tested_true
        dn(a) = x["obs"][a]["differentiated"] === true && x["obs"][a]["N"] == "tested_true"
        ex = !isempty(diffobs) && dn("std") && dn("swap")
        ex && push!(get!(hdn_examples, H, Int[]), seed)
        println(rpad("H=$H seed=$seed 例", 24), " H∧D∧N の例=", ex, "（支持: ", isempty(diffobs) ? "なし" : join(diffobs, ","),
                "; std D∧N=", dn("std"), " swap D∧N=", dn("swap"), "）")
    end
end
if ASKED == "sf"
    for H in [294, 392, 588]
        s = sort(get(hdn_examples, H, Int[]))
        println("H=$H H∧D∧N の例: ", isempty(s) ? "なし" : join(s, ","))
    end
end
ok_all = all_ok && neg
println(ok_all ? "S2-1/S2-2/S2-7 true for 10 seeds x 3 H, negative control detected: exit 0" : "some check false: exit 1")
exit(ok_all ? 0 : 1)
