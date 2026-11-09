# S36: gates first (no verdicts if one fails), then TP1-TP4 (predictions-transplant.md) and the description.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-transplant.json")))
R = r["runs"]
pick(v) = [x for x in R if x["variant"] == v]
key(x) = (x["seed"], x["schedule"])
t0 = all(arm -> begin b = Dict(key(x) => x["record"] for x in pick("base_$arm")); length(b) == length(pick("T0_$arm")) && all(x -> haskey(b, key(x)) && isequal(x["record"], b[key(x)]), pick("T0_$arm")) end, ("std", "swap"))
same = all(x -> x["same_circuit_as_first_seed"], R)
# I-R 2026-11-09 #2: every variant has each planned (seed, schedule) exactly once, H is 392, the seeds are 431-440, 4 schedules
VARIANTS = ("base_std", "T0_std", "T1_std<-swap", "T2_std", "base_swap", "T0_swap", "T1r_swap<-std", "T2r_swap")
# I-R 2 #2: the schedules are the planned (frozen) four, by name, each once; the canonical list is here, not in the results
SCHEDULES = ["p1-high", "p2-high", "p1-then-p2", "p2-then-p1"]
H = r["H"]; want = sort([(s, c) for s in r["seeds"] for c in SCHEDULES])
# SEEDS is set only for the smoke test on used seeds
complete = H == 392 && r["seeds"] == parse.(Int, split(get(ENV, "SEEDS", join(431:440, ",")), ",")) && r["schedules"] == SCHEDULES && allunique(r["seeds"]) && length(want) == 4 * length(r["seeds"]) &&
           all(v -> sort(key.(pick(v))) == want, VARIANTS) && length(R) == length(want) * length(VARIANTS) && Set(x["variant"] for x in R) == Set(VARIANTS)
mapg = r["G_permute_map"] && r["G_transplant_map"] && r["G_interventions_change_state"] && r["G_deq_pend"]
println("G complete (each (seed, schedule) once per variant, H=392, planned seeds) $complete  G maps edge by edge $mapg  G interventions change the state $(r["G_interventions_change_state"])")
println("G involution $(r["G_permute_involution"])  G self-transplant state $(r["G_self_transplant_state"])  TP0 T0 records = base $t0  (raised circuits equal to the first seed's: $same)")
ok = r["G_permute_involution"] && r["G_self_transplant_state"] && t0 && complete && mapg
get(ENV, "NEGTEST", "0") == "1" && (ok = false)
ok || (println("GATE FAILED: no verdicts"); exit(1))
same || println("NOTE: the raised circuits differ across seeds; the 'trial-side variation only' reading is withdrawn (predictions unchanged)")
surv(v) = count(x -> x["death"] === nothing, pick(v)); n(v) = length(pick(v))
early(v) = count(x -> x["death"] !== nothing && x["death"] < H, pick(v))   # I-R #1: "die before H" means death < H
v(b) = b ? "的中" : "外れ"
println("TP1 T1 (std <- swap) all survive: ", v(surv("T1_std<-swap") == n("T1_std<-swap")), " ($(surv("T1_std<-swap"))/$(n("T1_std<-swap")))")
println("TP2 T2 (std, pairs swapped) all survive: ", v(surv("T2_std") == n("T2_std")), " ($(surv("T2_std"))/$(n("T2_std")))")
println("TP3 T1r (swap <- std) all die before H: ", v(early("T1r_swap<-std") == n("T1r_swap<-std")), " ($(early("T1r_swap<-std"))/$(n("T1r_swap<-std")) die before H, $(surv("T1r_swap<-std")) survive)")
println("TP4 T2r (swap, pairs swapped) all die before H: ", v(early("T2r_swap") == n("T2r_swap")), " ($(early("T2r_swap"))/$(n("T2r_swap")) die before H, $(surv("T2r_swap")) survive)")
for vv in ("base_std", "T1_std<-swap", "T2_std", "base_swap", "T1r_swap<-std", "T2r_swap")
    xs = pick(vv); d = sort(unique(filter(!isnothing, [x["death"] for x in xs])))
    on = sum(x -> x["n_on"], xs); off = sum(x -> x["n_off"], xs)
    println(rpad(vv, 15), " survive $(surv(vv))/$(n(vv)) deaths $d intake steps $(sum(x -> x["intake_steps"], xs)) m0|on $(on == 0 ? NaN : round(sum(x -> x["m0_on"], xs) / on; digits = 3)) m0|off $(off == 0 ? NaN : round(sum(x -> x["m0_off"], xs) / off; digits = 3))")
end
