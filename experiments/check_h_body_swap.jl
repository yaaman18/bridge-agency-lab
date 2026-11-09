# S1 check (spec discussion/specs/S1-body-history.md r3 §3, §5): reads experiments/results-h-body-swap.json written by
# h_body_swap.jl and exits 0 iff, for all 10 seeds, S1-2 (B byte-equal), S1-1b (no shared mutable object), S1-4 (scripts
# differ only in the nursery 1-400, none in the school 401-800, length 800) and S1-5 (the :std replay agrees) hold.
# It also requires negative_control_detected: the S1-1b check must find an array object put into both arms (b.q0, c.q).
# Per seed it also shows whether S1-6 (a)(b) differ between the arms (display only, not in the exit code).
# Usage: cd experiments && julia --project=.. check_h_body_swap.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LAB = normpath(joinpath(@__DIR__, ".."))

res = JSON.parsefile(joinpath(LAB, "experiments", "results-h-body-swap.json"))
# claude-lab 2026-11-06 (codex I-R 5): the seeds must be exactly 1..10, and the negative controls must pass before any
# seed may be shown as "supported" (a failed control voids the S1-1b evidence for every seed).
seeds_ok = sort(Int.(res["seeds"])) == collect(1:10) && length(res["seeds"]) == 10 && all(haskey(res, "seed_$s") for s in 1:10)
neg = get(res, "negative_control_detected", false) === true
println("seeds exactly 1..10: ", seeds_ok, "; negative controls (detect b.q0, c.q, through an immutable struct, deep in c.pend; allow an alias inside one arm): ", neg)
function check_seed(seed)   # one seed: prints the lines and returns whether S1-2/1b/4/5 all hold
    r = res["seed_$(seed)"]; rp = r["replay_std"]
    checks = Dict(
        "S1-2" => r["B_equal"] === true,
        "S1-1b" => r["no_shared"] === true,
        "S1-4" => r["script_len"]["std"] == 800 && r["script_len"]["swap"] == 800 && isempty(r["school_diff"]) &&
                  isempty(intersect(r["script_diff"], 401:800)) && r["diff_in_nursery_only"] === true,
        "S1-5" => rp["acts_equal"] === true && rp["conf_equal"] === true && rp["B_after_equal"] === true,
    )
    ok = all(values(checks))
    acts_differ = r["school_acts"]["std"] != r["school_acts"]["swap"]
    conf_differ = r["conf"]["std"] != r["conf"]["swap"]
    println(rpad("seed $seed", 9), ok ? "ok  " : "FAIL", join([k for k in ("S1-2", "S1-1b", "S1-4", "S1-5") if !checks[k]],
            ","), " | acts(m1,m2) std ", r["school_acts"]["std"]["m1"], "/", r["school_acts"]["std"]["m2"], " swap ",
            r["school_acts"]["swap"]["m1"], "/", r["school_acts"]["swap"]["m2"], " differ ", acts_differ, " | conf std ",
            r["conf"]["std"], " swap ", r["conf"]["swap"], " differ ", conf_differ,
            " | S1-7 ", !(neg && seeds_ok) ? "void (controls failed)" : (ok && (acts_differ || conf_differ)) ? "supported under the contract" : (ok ? "not supported" : "excluded"))
    return ok
end

ok_all = seeds_ok && all([check_seed(seed) for seed in 1:10]) && neg
println(ok_all ? "S1-2/1b/4/5 all true for 10 seeds, negative control detected: exit 0" : "some check false: exit 1")
exit(ok_all ? 0 : 1)
