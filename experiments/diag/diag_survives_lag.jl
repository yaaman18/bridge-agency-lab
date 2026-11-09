# G7 check (not a prediction; an implementation-consistency check, G14): AS.survives (dead flag of the last state, and some non-sensor
# unit active in each of the last alive_window states) against "the body has a site after the last update", and against
# "the motors acted in the last alive_window updates", on SF objects (seeds 1-20, both arms, 4 survival schedules, H 392),
# intact and with m1, m2 silenced.
include(joinpath(@__DIR__, "..", "variant_horizon.jl"))
using .LabBodyAgency
const L = LabBodyAgency; const LC = L.LC
su = L.setup_with(392); p = su.params
n = 0; dis_body = Any[]; dis_motor = Any[]; core_only = 0
for seed in 1:20, cur in (:std, :swap)
    s = L.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
    M = Set(L.LC.unit(s.b, m) for m in ("m1", "m2"))
    for sch in su.survival, sil in (Set{Int}(), M)
        st = AS.initial_state(s, p); traj = [deepcopy(st)]; S = s.side[st]
        for _ in 1:p.horizon; AS.step!(st, s, p, sch, sil); push!(traj, AS.State(copy(st.active), copy(st.strength), st.resource, st.t, st.dead)); end
        body = !isempty(L.body_sites(S.w)); delete!(s.side, st)
        sv = AS.alive(traj, s, p)
        motors = all(x -> any(m -> x.active[m], M), traj[end-p.alive_window+1:end])
        global n += 1
        sv != body && push!(dis_body, (seed, cur, sch.name, isempty(sil), sv, body))
        sv && !motors && (global core_only += 1)
    end
end
println("runs $n; survives ≠ body alive after the last update: $(length(dis_body)) $(first(dis_body, 5)); survives true with no motor on in some of the last alive_window states: $core_only")
