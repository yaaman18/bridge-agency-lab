# Diagnosis (read-only, no rule changed; item 75) of why L2 stays false for body_org with bin3 + idle_first (item 74):
# (A) ValueNeeded: silencing the value-tracking units r2, r8 does not cost survival; (B) core_enables_action: silencing the
# core c1, c2 does not change the choice in both choice schedules. The runs are the AGENCY-001 trajectories of
# experiments/variant_horizon.jl (H = 392), observed step by step. Counterfactual settings (another rule, another
# silencing) are measurements for the diagnosis, not proposals. Usage: julia --project=. experiments/diag/diag_l2.jl
include(joinpath(@__DIR__, "..", "variant_horizon.jl"))
using JSON
const LC = LabCore
const H = 392
su = LBA.setup_with(H); p, pc = su.params, su.choice_params
body(st) = sum(st.strength)   # :constituents reading: sites of the body's constituents

"""Run one AGENCY-001 trajectory and observe it: the steps each patch motor is on, the first step each is on after the
schedule's switch, whether it was idle (no act for more than FORGET steps) when it came on, and the body's size."""
function observe(s, pp, sch; silenced = Set{Int}())
    st = AS.initial_state(s, pp); S = s.side[st]; b = s.b
    m = Dict(n => LC.unit(b, n) for n in ("m1", "m2"))
    on = Dict("m1" => 0, "m2" => 0); first_after = Dict{String,Any}("m1" => nothing, "m2" => nothing)
    idle_on = Dict("m1" => 0, "m2" => 0); minbody = body(st); deathstep = nothing
    for t in 1:pp.horizon
        lm = S.c.lastM === nothing ? nothing : copy(S.c.lastM); now = S.c.t + 1
        AS.step!(st, s, pp, sch, silenced)
        st.dead && deathstep === nothing && (deathstep = t)
        for (n, u) in m
            st.active[u] || continue
            on[n] += 1
            (lm !== nothing && now - lm[u] > LC.FORGET) && (idle_on[n] += 1)
            (t > sch.switch && first_after[n] === nothing) && (first_after[n] = t)
        end
        minbody = min(minbody, body(st))
    end
    delete!(s.side, st)
    Dict("on" => on, "first_on_after_switch" => first_after, "on_while_idle" => idle_on, "min_body" => minbody,
         "end_body" => body(st), "death" => deathstep, "alive" => AS.alive(vcat(fill(st, p.alive_window)), s, pp))
end

out = Dict{String,Any}()
println("== A. ValueNeeded: survival schedules, H = $H, seed 1, intact vs r2,r8 silenced (bin3 + idle_first)")
for (rule, ct, idle) in (("bin3+idle", :bin3, true), ("bin3", :bin3, false))
    s = LBA.BodyOrg(1; abundant_r0 = pc.resource0, contrast = ct, idle_first = idle)
    T = Set(LC.unit(s.b, n) for n in ("r2", "r8"))
    for x in su.survival, (lab, sil) in (("intact", Set{Int}()), ("r2,r8 off", T))
        r = observe(s, p, x; silenced = sil); out["A $rule $(x.name) $lab"] = r
        println(rpad("$rule $(x.name) $lab", 32), " alive ", AS.survives(s, p, x; silenced = sil), " on ", r["on"], " idle-on ", r["on_while_idle"],
                " first after switch(t>$(x.switch)) ", r["first_on_after_switch"], " body min ", r["min_body"], " end ", r["end_body"])
    end
end
# The same body without any act (every unit silenced): how long it lives on what it has.
s = LBA.BodyOrg(1; abundant_r0 = pc.resource0, contrast = :bin3, idle_first = true)
for x in su.survival
    r = observe(s, p, x; silenced = Set(1:AS.nunits(s))); out["A nothing acts $(x.name)"] = r
    println(rpad("every unit silenced $(x.name)", 32), " death step ", r["death"], " body min ", r["min_body"])
end
println("seeds 1-10, bin3+idle, r2,r8 silenced, first step m2 is on in p2-high / after the switch in p1-then-p2:")
for seed in 1:10
    local s = LBA.BodyOrg(seed; abundant_r0 = pc.resource0, contrast = :bin3, idle_first = true)
    T = Set(LC.unit(s.b, n) for n in ("r2", "r8"))
    a = observe(s, p, su.survival[2]; silenced = T); b2 = observe(s, p, su.survival[3]; silenced = T)
    println("  seed $seed: p2-high m2 on ", a["on"]["m2"], " (idle ", a["on_while_idle"]["m2"], "), death ", a["death"],
            "; p1-then-p2 first m2 after switch ", b2["first_on_after_switch"]["m2"], ", death ", b2["death"])
end

println("\n== B. core_enables_action: choice schedules, window 5-15, seed 1 (bin3 + idle_first)")
s = LBA.BodyOrg(1; abundant_r0 = pc.resource0, contrast = :bin3, idle_first = true)
core = Set(LC.unit(s.b, n) for n in ("c1", "c2"))
fname(u) = s.b.kind[u] == 'R' ? s.b.names[u] * "(" * LC.FEATURES[s.b.perm[s.b.feat[u]]][1] * ")" : s.b.names[u]
for mn in ("m1", "m2")
    mu = LC.unit(s.b, mn)
    println("edges into $mn after raising (q, sediment): ", [(fname(a), s.raised.q[k], s.raised.sg[k]) for (k, (a, c, _)) in enumerate(s.b.edges)
        if c == mu && (s.raised.q[k] > 0 || s.raised.sg[k] > 0)])
end
for x in su.choice
    for (lab, sil) in (("intact", Set{Int}()), ("core off", core), ("r7 off", Set([LC.unit(s.b, "r7")])), ("r8 off", Set([LC.unit(s.b, "r8")])),
                       ("r7,r8 off", Set([LC.unit(s.b, "r7"), LC.unit(s.b, "r8")])))
        ch = sort([s.names[u] for u in AS.choice(s, pc, x, su.choice_window; silenced = sil)])
        out["B $(x.name) $lab"] = ch
        println(rpad("$(x.name) $lab", 22), " choice ", ch)
    end
end
println("core units active in the window (intact, c1-better): ",
    let tr = AS.run_trajectory(s, pc, su.choice[1]); [sort([s.names[u] for u in core if tr[t+1].active[u]]) for t in su.choice_window] end)
write(joinpath(@__DIR__, "diag_l2.json"), JSON.json(out, 2))

println("\n== A2. falsification of the redundancy reading: r2, r8 and the empty-patch receptors r3, r4 silenced (seed 1)")
let s = LBA.BodyOrg(1; abundant_r0 = pc.resource0, contrast = :bin3, idle_first = true)
    for (lab, names) in (("r3,r4 off", ("r3", "r4")), ("r2,r3,r4,r8 off", ("r2", "r3", "r4", "r8")))
        T = Set(LC.unit(s.b, n) for n in names)
        for x in su.survival
            r = observe(s, p, x; silenced = T); out["A2 $(x.name) $lab"] = r
            println(rpad("$(x.name) $lab", 30), " alive ", AS.survives(s, p, x; silenced = T), " on ", r["on"], " idle-on ", r["on_while_idle"], " death ", r["death"], " body min ", r["min_body"])
        end
    end
end
write(joinpath(@__DIR__, "diag_l2.json"), JSON.json(out, 2))
