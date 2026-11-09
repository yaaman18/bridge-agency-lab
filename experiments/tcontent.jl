# S5 (spec discussion/specs/S5-body-tcontent.md r1): what the T difference of S4 is made of. On the same objects as S4
# (RULE=sf: current rule + sed_fade, KC_trial 0.0015; seeds 21..30; H 294, 392, 588; arms :std and :swap), measures
# C0 T and choices recomputed against S4's record, C1 the receptors' activity in the choice window, C2 the receptor->motor
# confidences of the raised circuit, C3 the choice with T (and all receptors) silenced, C4 the choice on lab probe
# schedules outside the frozen ones. Writes experiments/results-tcontent.json. Predictions: predictions-tcontent.md.
# Usage: cd experiments && julia --project=.. tcontent.jl   (SEEDS=24 HORIZONS=392 for a short run)
include(joinpath(@__DIR__, "variant_horizon.jl"))   # LabBodyAgency; its own runs are under PROGRAM_FILE (not run here)
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const ASC = LBA.AS
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(21:30, ",")), ","))
const HS = parse.(Int, split(get(ENV, "HORIZONS", "294,392,588"), ","))
const S4 = JSON.parsefile(joinpath(LAB, "experiments", "results-dn-body-swap-sf.json"))
# C4: probe schedules (lab only; constant yields, switch 20 as the frozen choice schedules)
const PROBES = [("eq-high", (4, 4)), ("eq-low", (2, 2)), ("lo-1", (2, 1)), ("lo-2", (1, 2)), ("hi-1", (3, 1)), ("hi-2", (1, 3))]

# the BodyOrg of S4 (dn_body_swap.jl `fresh`, RULE=sf)
org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
"""The same BodyOrg with another raised circuit (the negative controls)."""
with_raised(S, raised) = LBA.BodyOrg(S.names, S.edges, S.motors, S.b, raised, S.noise, S.structure, S.abundant_r0, S.U, S.MCOST,
                                     S.idle_first, S.contrast, S.core_gate, S.seen_both, S.sed_fade, S.grow, S.KC, S.PER, S.w0, S.pool0, IdDict())

names_of(s, us) = sort([s.names[u] for u in us])
choice_str(s, pc, sch, w; silenced = Set{Int}()) = join(names_of(s, ASC.choice(s, pc, sch, w; silenced)), ",")
receptors(s) = [u for u in 1:length(s.names) if s.b.kind[u] == 'R']

# C2: receptor -> motor contingencies of the raised circuit (q, sg), and the confirmed ones (q >= 1)
function links(s)
    out = Dict{String,Any}()
    for (k, (a, c, _)) in enumerate(s.edges)
        s.b.kind[a] == 'R' && s.b.kind[c] == 'M' || continue
        out["$(s.names[a])->$(s.names[c])"] = Dict("q" => s.raised.q[k], "sg" => s.raised.sg[k])
    end
    out
end
# post hoc (after the short run of seed 24, spec r1 §1 C2b): every contingency into a motor (core->motor included), q and sg
motor_inputs(s) = Dict("$(s.names[a])->$(s.names[c])" => [s.raised.q[k], s.raised.sg[k]] for (k, (a, c, _)) in enumerate(s.edges) if s.b.kind[c] == 'M')
confirmed(L) = sort([k for (k, v) in L if v["q"] >= 1])

function measure(s, su)
    pc, c, w = su.choice_params, su.choice, su.choice_window
    core = ASC.endogenous_core(s, pc, su.survival[1])
    T = setdiff(ASC.value_tracking_units(s, pc, c, w), core)
    choices = Dict(x.name => choice_str(s, pc, x, w) for x in c)
    # C1: steps of the window at which each receptor is active, per choice schedule
    act = Dict{String,Any}()
    for x in c
        traj = ASC.run_trajectory(s, pc, x)
        act[x.name] = Dict(s.names[u] => count(t -> traj[t + 1].active[u], w) for u in receptors(s))
    end
    disc = sort([s.names[u] for u in receptors(s) if count(x -> act[x.name][s.names[u]] > 0, c) == 1])
    L = links(s)
    silT = Dict(x.name => choice_str(s, pc, x, w; silenced = Set(T)) for x in c)
    silR = Dict(x.name => choice_str(s, pc, x, w; silenced = ASC.sensor_units(s)) for x in c)
    probes = Dict(n => choice_str(s, pc, ASC.Schedule(n, y, y, 20), w) for (n, y) in PROBES)
    Tn = names_of(s, T)
    kind = Tn == ["r2", "r8"] ? "P2" : Tn == ["r1", "r7"] ? "P1" : Tn == ["r1", "r2", "r7", "r8"] ? "both" : "other"
    Dict("T" => Tn, "kind" => kind, "core" => names_of(s, core), "choices" => choices, "window_activity" => act,
         "discriminating_cues" => disc, "links" => L, "motor_inputs" => motor_inputs(s), "confirmed_links" => confirmed(L),
         "silenced_T" => silT, "silenced_receptors" => silR, "probes" => probes)
end
content(m) = (m["confirmed_links"], m["silenced_T"], m["probes"])

s4obs(H, seed, a) = only(x for x in S4["runs"] if x["H"] == H && x["seed"] == seed)["obs"][a]

res = Dict{String,Any}("spec" => "discussion/specs/S5-body-tcontent.md r1", "rule" => "sf", "seeds" => SEEDS, "horizons" => HS,
                       "probes" => Dict(n => collect(y) for (n, y) in PROBES), "templates_sha256" => ASC.load_templates().sha256, "runs" => Any[])
for H in HS
    su = LBA.setup_with(H)
    for seed in SEEDS
        row = Dict{String,Any}("H" => H, "seed" => seed)
        for (a, cur) in (("std", :std), ("swap", :swap))
            m = measure(org(seed, su, cur), su)
            m2 = measure(org(seed, su, cur), su)                     # C0: the repeat, on a rebuilt BodyOrg
            o = s4obs(H, seed, a)
            m["C0_repeat_equal"] = m2 == m                           # before the C0 keys are added to m
            m["C0_matches_S4"] = m["T"] == sort(String.(o["value_tracking"])) && m["choices"] == Dict(String(k) => v for (k, v) in o["choices"])
            row[a] = m
        end
        # post hoc (spec r1 §1 C2b): the fields of the raised circuit state that differ between the arms, with the values
        # of the small ones
        rs, rw = org(seed, su, :std).raised, org(seed, su, :swap).raised
        row["raised_fields_differ"] = Dict(String(f) => (length(string(getfield(rs, f))) <= 200 ? [string(getfield(rs, f)), string(getfield(rw, f))] : "long")
                                           for f in fieldnames(typeof(rs)) if string(getfield(rs, f)) != string(getfield(rw, f)))
        row["content_differs"] = content(row["std"]) != content(row["swap"])
        row["probes_differ"] = sort([n for (n, _) in PROBES if row["std"]["probes"][n] != row["swap"]["probes"][n]])
        push!(res["runs"], row)
        f(m) = "$(m["kind"]) T=$(join(m["T"], ",")) links=$(join(m["confirmed_links"], " ")) silT=$(m["silenced_T"]) probes=$(m["probes"])"
        println("H=$H seed=$seed C0=$(row["std"]["C0_matches_S4"] && row["swap"]["C0_matches_S4"]) rep=$(row["std"]["C0_repeat_equal"] && row["swap"]["C0_repeat_equal"]) differs=$(row["content_differs"]) probes_differ=$(row["probes_differ"])")
        println("  std  ", f(row["std"])); println("  swap ", f(row["swap"]))
    end
end

# negative controls (seed 24, H 392, :swap): (i) r8->m2 and r7->m1 set to q = sg = 0 must be detected by C2;
# (ii) an untouched copy of the raised circuit equals the original in C2-C4. They show the checks work, nothing more.
let su = LBA.setup_with(392), s = org(24, su, :swap)
    base = measure(s, su)
    r = deepcopy(s.raised)
    for (k, (a, c, _)) in enumerate(s.edges)
        (s.names[a], s.names[c]) in (("r8", "m2"), ("r7", "m1")) && (r.q[k] = 0; r.sg[k] = 0)
    end
    cut = measure(with_raised(s, r), su)
    clean = measure(with_raised(s, deepcopy(s.raised)), su)
    res["negative_control"] = Dict("seed" => 24, "H" => 392, "arm" => "swap",
        "i_cut_detected" => cut["confirmed_links"] != base["confirmed_links"], "i_cut_links" => cut["confirmed_links"],
        "i_cut_silenced_T" => cut["silenced_T"], "i_cut_choices" => cut["choices"], "i_cut_probes" => cut["probes"],
        "ii_clean_equal" => content(clean) == content(base) && clean["choices"] == base["choices"] &&
                            clean["links"] == base["links"] && clean["motor_inputs"] == base["motor_inputs"])   # codex I-R 8: q, sg too
    res["negative_control_detected"] = res["negative_control"]["i_cut_detected"] && res["negative_control"]["ii_clean_equal"]
    println("negative control ", res["negative_control_detected"], " cut links ", cut["confirmed_links"], " cut choices ", cut["choices"])
end
write(joinpath(LAB, "experiments", "results-tcontent.json"), JSON.json(res, 2))
println("written experiments/results-tcontent.json")
