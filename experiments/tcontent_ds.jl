# S5 (spec discussion/specs/S5-body-tcontent.md §1, deepseek-lab's independent implementation): what the difference of the
# tracking set T consists of. RULE=sf (BodyOrg as in dn_body_swap.jl RULE=sf, seeds 21..30, H 294/392/588); C0 is checked
# against experiments/results-dn-body-swap-sf.json, the negative controls (i)(ii) at seed 24, H = the smallest horizon.
# Usage: cd experiments && julia --project=.. tcontent_ds.jl; SEEDS=24 HORIZONS=392 for a short run.
# Writes experiments/results-tcontent-ds.json.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const AS = LBA.AS
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(21:30, ",")), ","))
const HS = parse.(Int, split(get(ENV, "HORIZONS", "294,392,588"), ","))
const S4FILE = joinpath(LAB, "experiments", "results-dn-body-swap-sf.json")
const OUTFILE = joinpath(LAB, "experiments", "results-tcontent-ds.json")
const TRIALS = ("eq-high" => (4, 4), "eq-low" => (2, 2), "lo-1" => (2, 1), "lo-2" => (1, 2), "hi-1" => (3, 1), "hi-2" => (1, 3))
sortjoin(v) = join(sort(v), ",")

# sf: the BodyOrg of dn_body_swap.jl fresh() (same arguments, sed_fade = true, KC_trial = 0.0015)
sf_org(seed, su; cur = :std) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0,
                               idle_first = true, contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)

arm_key(n) = n == "ablate_T" ? "swap" : n   # the misfed arm plays the part of the swap arm

# C0: evaluate always; arm_name/null/expect: the copy to alter (r8->m2, r7->m1 set to q = sg = 0) and its S4 reference.
function observe(su, seed, H; arm_name = nothing, null_pair = nothing, expect = nothing, cur = :std)
    s = sf_org(seed, su; cur = cur)
    if null_pair !== nothing
        u = s.b
        for (r, m) in null_pair
            k = findfirst(e -> e[1] == LBA.LC.unit(u, r) && e[2] == LBA.LC.unit(u, m), u.edges)
            k === nothing || (s.raised.q[k] = 0; s.raised.sg[k] = 0)
        end
    end
    r = AS.evaluate(s, su)
    pc = su.choice_params
    u = s.b
    uname(k) = s.names[k]
    T = sort([uname(k) for k in setdiff(AS.value_tracking_units(s, pc, su.choice, su.choice_window),
                                        AS.endogenous_core(s, pc, su.survival[1]))])
    clocks = sort([uname(k) for k in AS.endogenous_core(s, pc, su.survival[1])])
    qn = sort([uname(k) for k in AS.value_tracking_units(s, pc, su.choice, su.choice_window)])
    choices = Dict(k => join(sort(collect(v)), ",") for (k, v) in r.choices)
    # C1: the steps each receptor is true in the window (null here, no receptors are silenced in the observation)
    act = Dict(x.name => window_activity(s, pc, x, su.choice_window) for x in su.choice)
    # C2: raised q, sg of r1..r8 -> m1, m2
    qm = Dict{String,Int}(); sm = Dict{String,Int}()
    for k in 1:8, m in ("m1", "m2")
        j = findfirst(e -> e[1] == k && e[2] == LBA.LC.unit(u, m), u.edges)
        qm["$(uname(k))->$(m)"] = j === nothing ? 0 : s.raised.q[j]
        sm["$(uname(k))->$(m)"] = j === nothing ? 0 : s.raised.sg[j]
    end
    links = sort([l for (l, v) in qm if v >= 1])
    # C3: the choice with T silenced, with every receptor silenced
    tsil = Set(findall(n -> n in T, s.names)); asen = AS.sensor_units(s)
    csil = Dict(x.name => join(sort(motornames(s, sel(s, pc, x; silenced = tsil, window = su.choice_window))), ",") for x in su.choice)
    call = Dict(x.name => join(sort(motornames(s, sel(s, pc, x; silenced = asen, window = su.choice_window))), ",") for x in su.choice)
    # C4: the trials (frozen switch 20, both halves the same; choice_params)
    probes = Dict{String,String}()
    for (pn, v) in TRIALS
        t = AS.Schedule(pn, v, v, 20)
        probes[pn] = join(sort(motornames(s, sel(s, pc, t; window = su.choice_window))), ",")
    end
    (; seed = seed, H = H, arm = arm_name, T = T, kw = qn, clocks = clocks, choices = choices, act = act, q = qm, sg = sm,
       links = links, csil = csil, call = call, probes = probes, expect = expect)
end

function kind(T)
    S = Set(T)
    S == Set(["r2", "r8"]) ? "P2" : S == Set(["r1", "r7"]) ? "P1" : S == Set(["r1", "r2", "r7", "r8"]) ? "both" : "other"
end

# C1: traj = run_trajectory (traj[1] the start state), traj[t + 1].active[m] for each t of the window
function window_activity(s, pc, sch, window)
    traj = AS.run_trajectory(s, pc, sch)
    Dict(s.names[k] => count(t -> traj[t + 1].active[k], window) for k in AS.sensor_units(s))
end
# C3/C4: with abundant resource (choice_params) the motor that ACTS on a step: core gates allow the patches, then the net
# input per patch decides (the patch of the largest positive total; ties by patch order), as core/circuit.jl acts
function sel(s, pc, sch; silenced = Set{Int}(), window)
    traj = AS.run_trajectory(s, pc, sch; silenced = silenced)
    acting = Int[]
    for t in window
        st = traj[t + 1]; net = zeros(2)
        for k in eachindex(s.b.edges)
            e = s.b.edges[k]; (e[1] in silenced || !st.active[e[1]]) && continue
            v = pc.strength0      # constituents: a kept bond counts 1
            j = s.b.patch[e[2]]
            j in (1, 2) && (net[j] += v)
            j == 3 && (net .+= v)   # the call recruits both patches
        end
        m = argmax(net)
        push!(acting, net[m] > 0 ? m : 0)
    end
    acting
end
motornames(s, patches) = [n for (u, m) in s.motors if m in patches for n in (s.names[u],)]

cues(A, B) = sort([l for l in keys(A) if (A[l] > 0) != (B[l] > 0)])   # true in one schedule only

s4diff(a, b) = Dict{String,Any}("T" => a.T == b.T, "choices" => Dict(k => a.choices[k] == join(sort(collect(b.choices[k])), ",") for k in keys(b.choices)))
# (ii) C2..C4 equal: q, sg of the links (with their values), the confirmed set, C3, C4
c2c4_equal(a, b) = a.q == b.q && a.sg == b.sg && a.links == b.links && a.csil == b.csil && a.call == b.call && a.probes == b.probes

s4 = JSON.parsefile(S4FILE)
s4run(H, seed, arm) = (i = findfirst(x -> x["H"] == H && x["seed"] == seed, s4["runs"]); i === nothing ? nothing : s4["runs"][i]["obs"][arm])

res = Dict{String,Any}("seeds" => SEEDS, "horizons" => HS, "rule" => "sf", "runs" => Any[])
# the arms of S4: std (RULE=sf) and swap (RULE=sf on the swap curriculum)
const ARMS = [("std", nothing, :std), ("swap", nothing, :swap)]
for H in HS
    su = LBA.setup_with(H)
    for seed in SEEDS
        ra = Dict(a => observe(su, seed, H; arm_name = a, cur = c) for (a, _, c) in ARMS)
        rb = Dict(a => observe(su, seed, H; arm_name = a, cur = c) for (a, _, c) in ARMS)   # the repeat (C0)
        push!(res["runs"], begin
            run = Dict{String,Any}("H" => H, "seed" => seed); C0 = Ref(true); RE = Ref(true)
            for (a, _, _) in ARMS
                x, y = ra[a], rb[a]
                ref = s4run(H, seed, a === "swap" ? "swap" : "std")
                d = s4diff(x, (; T = sort(ref["value_tracking"]), choices = Dict{String,Any}(k => [v] for (k, v) in ref["choices"])))
                run[a] = Dict("T" => x.T, "kind" => kind(x.T), "choices" => x.choices, "discriminating_cues" => cues(x.act["c1-better"], x.act["c2-better"]),
                              "window_activity" => x.act, "confirmed_links" => x.links, "silenced_T" => x.csil, "silenced_receptors" => x.call,
                              "probes" => x.probes, "C0_matches_S4" => d["T"] && all(values(d["choices"])), "C0_repeat_equal" => x.T == y.T && x.choices == y.choices,
                              "q" => x.q, "sg" => x.sg, "details" => d)
                C0[] &= d["T"] && all(values(d["choices"]))
                RE[] &= x.T == y.T && x.choices == y.choices
            end
            A, B = ra["std"], ra["swap"]
            run["content_differs"] = !(A.links == B.links && A.csil == B.csil && A.call == B.call && A.probes == B.probes)
            run["probes_differ"] = A.probes != B.probes
            run["C0_matches_S4"] = all(run[a]["C0_matches_S4"] for (a, _, _) in ARMS)
            run["C0_repeat_equal"] = all(run[a]["C0_repeat_equal"] for (a, _, _) in ARMS)
            run["type_pair"] = [kind(A.T), kind(B.T)]
            run
        end)
        println("H=$H seed=$seed T=$(ra["std"].T)/$(ra["swap"].T) kinds=$(kind(ra["std"].T))/$(kind(ra["swap"].T)) " *
                "C0=$(res["runs"][end]["C0_matches_S4"]) repeat=$(res["runs"][end]["C0_repeat_equal"]) differs=$(res["runs"][end]["content_differs"]) probes=$(ra["std"].probes == ra["swap"].probes ? "same" : "differ")")
    end
end

# the negative controls: (i) the altered copy differs in C2; (ii) the untouched copy equals in C2..C4 (q and sg included)
minus = [("r8", "m2"), ("r7", "m1")]
neg = Dict{String,Any}()
for H in HS, seed in SEEDS
    su = LBA.setup_with(H)
    for (arm, _, armcur) in ARMS
        A = observe(su, seed, H; arm_name = arm, cur = armcur); B = observe(su, seed, H; arm_name = arm, cur = armcur)
        for (r, m) in minus   # (i): a copy with r -> m's q and sg set to 0 differs in C2 from the untouched copy
            Altered = observe(su, seed, H; arm_name = arm, null_pair = [(r, m)], cur = armcur)
            neg["$(arm)_$(r)_$(m)"] = !(Altered.q == B.q && Altered.sg == B.sg && Altered.links == B.links)
        end
        neg["$(arm)_unchanged"] = c2c4_equal(A, B)
    end
end
detected_i = all(neg["$(a)_$(r)_$(m)"] for (a, _, _) in ARMS for (r, m) in minus)
detected_ii = all(neg["$(a)_unchanged"] for (a, _, _) in ARMS)
res["negative_control"] = merge(Dict("pairs" => minus, "altered_detected" => detected_i, "unchanged_equal" => detected_ii), neg)
res["negative_control_detected"] = detected_i && detected_ii

write(OUTFILE, JSON.json(res, 2, allownan = false))
println("written ", relpath(OUTFILE, LAB), "  C0 all = ", all(x -> x["C0_matches_S4"] && x["C0_repeat_equal"], res["runs"]),
        "  negative_control_detected = ", res["negative_control_detected"])
