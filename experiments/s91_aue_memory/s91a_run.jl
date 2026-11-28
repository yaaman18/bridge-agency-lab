# S91a run (discussion/specs/S91a-draft-aue-memory.md r3 §6-§7; predictions frozen in predictions.toml / experiments/freeze-s91a.txt).
# smoke: the gates only (4-seam regression on bed_mem.jl, GB-M0..GB-M6); no run metric and no E1-E3 is computed.
# run: frozen91a + out/neg_controls.out (13 NC, 5-file SHA-256) + all smoke gates, then 3 environments x 12 seeds x 5 capacities
# (4000 steps each, replay_from_audit checked) and E1-E3 to out/s91a.out. Not executed before the independent I-R.
# Fixtures and tests use only the test seeds 919001..919099; the outcome seeds 910101..910136 are read here only by GB-M0's two
# non-result checks (BO_CUR survival, rand_u64 value / lag-1 autocorrelation) and by run.
# Includes experiments/onestep/onestep.jl (GB-M1 memoryless reference), experiments/nesting_cpc_c/NestingCPCC.jl and
# experiments/aue_seam/adapter_aue_b.jl (4-seam regression) unchanged; aue_seam/bed.jl is not loaded (bed_mem.jl replaces it).
# Each gate is a function (gate_4seam, gate_gbm0 .. gate_gbm6) that throws on failure; neg_controls.jl calls them one by one.
# `inj` (a NamedTuple of AUEAMemAdapter keyword flags) is passed to every memory adapter a gate builds (negative controls only).
# phenomenal_claim = :not_certified (fixed).
# usage: julia --project=. -t 8 experiments/s91_aue_memory/s91a_run.jl [smoke|run]

using SHA
using Printf

const S91 = @__DIR__
const LAB91 = normpath(joinpath(S91, "..", ".."))
include(joinpath(LAB91, "experiments", "onestep", "onestep.jl"))           # Main: LabCore, one_life.jl, _live_aue, TracePred
include(joinpath(LAB91, "experiments", "nesting_cpc_c", "NestingCPCC.jl"))
include(joinpath(S91, "adapter_aue_a_mem.jl"))                             # bed_mem.jl as module AUESeamBed
include(joinpath(LAB91, "experiments", "aue_seam", "adapter_aue_b.jl"))
using .AUESeamBed
using .AdapterAUEB
import .AdapterAUEAMem as AM
const MC = AM.S90MemCore
const OUT91 = joinpath(S91, "out"); mkpath(OUT91)

# ================================================================ frozen inputs (spec §1.6, GB-M0)
const FROZEN91A = [
    ("experiments/s91_aue_memory/predictions.toml", "8b71677b3844d7545ce05c703c0a0c127b687fce031fda4b455ee124ae420df6"),
    ("discussion/specs/S91a-draft-aue-memory.md", "69a779f3b37b0bd0d9d4af78ad0213080d43090a1146d11c403cc9b1045a1a07"),
]
const MEMCORE_PATH = "experiments/s90_l2l_trm/mem_core.jl"
const MEMCORE_SHA = "e09341e7dfd0e8c93d935c754f169b061c5a592ecf9886b9000a8d75f4d07a08"
filesha(p) = bytes2hex(open(sha256, joinpath(LAB91, p)))

# experiments/freeze-s91a.txt: exactly the 2 lines "<sha256>  <path>" of FROZEN91A, in order; both files and the unchanged
# mem_core.jl match their SHA-256.
function frozen91a()
    lines = filter(!isempty, readlines(joinpath(LAB91, "experiments", "freeze-s91a.txt")))
    length(lines) == length(FROZEN91A) || error("frozen91a: freeze-s91a.txt has $(length(lines)) lines, expected $(length(FROZEN91A))")
    for (l, (p, h)) in zip(lines, FROZEN91A)
        l == "$h  $p" || error("frozen91a: freeze-s91a.txt line $(repr(l)) != the code constant for $p")
        filesha(p) == h || error("frozen91a: SHA-256 of $p is $(filesha(p)), frozen $h")
    end
    filesha(MEMCORE_PATH) == MEMCORE_SHA || error("frozen91a: SHA-256 of $MEMCORE_PATH is $(filesha(MEMCORE_PATH)), expected $MEMCORE_SHA")
    return true
end

# ================================================================ seeds, environments, capacities (spec §2, §5)
const SEEDS91 = 910101:910136
const ENVS91 = ((:env_stat, 910101:910112), (:env_rev, 910113:910124), (:env_depl, 910125:910136))
const MAIN_UNUSED = vcat(collect(1600:1617), collect(2860:2899))
const TEST_SEEDS = 919001:919099
const CAPS91 = AM.CAPACITIES                       # (:C0_B8, :C0_B9, :C1, :C2, :C130)
const FINCAPS91 = (:C1, :C2, :C130)
const STEPS91 = 4000
const K91 = 0.002
const U91 = 0.02

tseed(s) = (s in TEST_SEEDS) ? s : error("fixture seed $s outside the test block 919001..919099")
mkad(cap::Symbol; inj = NamedTuple(), kw...) = AM.AUEAMemAdapter(cap; inj..., kw...)
chk(c::Bool, msg) = c || error(msg)
function expect_throw(T::Type, f; want::Union{Nothing,String} = nothing)
    try
        f()
        return (false, "expected $T but succeeded")
    catch e
        e isa T || return (false, "expected $T, got $(typeof(e)): $(first(sprint(showerror, e), 300))")
        m = sprint(showerror, e)
        (want === nothing || occursin(want, m)) || return (false, "expected $T containing $(repr(want)), got: $(first(m, 300))")
        return (true, m)
    end
end
function rep1(f, anchor, new)
    n = length(findall(anchor, f)); n == 1 || error("anchor occurs $n times: $anchor")
    return replace(f, anchor => new)
end
# threaded map in index order; a job's error is rethrown unwrapped, the first failing index first (deterministic)
function tmap91(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads for i in eachindex(xs)
        out[i] = try; (true, f(xs[i])); catch e; (false, e); end
    end
    for o in out; o[1] || throw(o[2]); end
    return [o[2] for o in out]
end
g6(x) = @sprintf("%.6g", x)
gE(x) = @sprintf("%.3e", Float64(x))
mean0(v) = isempty(v) ? NaN : sum(v) / length(v)

# ---- state helpers (fixtures: copies of a state with chosen fields rewritten; production paths never use them)
withmem(st::AM.AUEAMemState, slots; life = st.life, exp_step = st.exp_step) =
    AM.AUEAMemState(life, st.pred, MC.MemoryState(collect(MC.MemSlot, slots)), st.cfg, exp_step, AM.NOPENDING, AM.NOREC)
recap(st::AM.AUEAMemState, ad::AM.AUEAMemAdapter) = AM.AUEAMemState(st.life, st.pred, MC.MemoryState(), ad.cfg, st.exp_step, AM.NOPENDING, AM.NOREC)
function famine_life(life; Bv)                     # every body cell's bound matter set to Bv, all free matter removed
    c = deepcopy(life); w = c.w
    for i in eachindex(w.C); w.C[i] != 0 && (w.B[i] = Bv); end
    fill!(w.A, 0.0)
    return c
end
function lone_cell_life(life; Bv)                  # only the first body cell kept (balance Bv); the others die into free matter
    c = deepcopy(life); w = c.w; first = true
    for i in eachindex(w.C)
        w.C[i] == 0 && continue
        if first; w.B[i] = Bv; first = false; else; w.A[i] += w.B[i]; w.B[i] = 0.0; w.C[i] = 0; end
    end
    return c
end
function with_port(life, p::Float64)
    c = deepcopy(life); c.w.port.reservoir = p; return c
end
inputs_with(seed, steps; g = nothing) = (ru = AM.rand_u64_stream(seed, steps);
    [StampedInput(s, Dict{String,Any}("g1" => g[1], "g2" => g[2], "rand_u64" => ru[s+1])) for s in 0:steps-1])
replace_ru(si::StampedInput, ru::UInt64) = StampedInput(si.step, Dict{String,Any}("g1" => si.ports["g1"], "g2" => si.ports["g2"], "rand_u64" => ru))
u_of(ru::UInt64) = Float64(ru >> 11) * 2.0^-53
ru_of(u::Float64) = (k = u * 2.0^53; (isinteger(k) && 0 <= k < 2.0^53) || error("u = $u is not on the 53-bit draw grid"); UInt64(k) << 11)
memcount(m::Vector{UInt8}) = Int(UInt32(m[1]) | (UInt32(m[2]) << 8) | (UInt32(m[3]) << 16) | (UInt32(m[4]) << 24))

# A run through the bed recording the state after every step and every Phase 2 report.
function bedrun(ad, id, st0, ins)
    states = Dict{Int,Any}(); sets = Dict{Int,Any}(); nset = Dict{Int,Int}()
    res = run_species!(ad, id, st0, ins; on_step = (s, st, d) -> (states[s] = st),
                       on_settle = (s, x) -> (sets[s] = x; nset[s] = get(nset, s, 0) + 1))
    return (res = res, states = states, sets = sets, nset = nset, st0 = st0)
end
before(r, s) = s == 0 ? r.st0 : r.states[s-1]

# Phase-2-only wrapper (GB-M2 fixtures): Phase 1 returns a copy of the state unchanged (no circuit step, no pending write), so the
# settlement runs on exactly the balances / port / memory of the fixture; every other hook is the memory adapter's.
struct P2Only <: AbstractSpeciesAdapter
    a::AM.AUEAMemAdapter
end
AUESeamBed.species_spec(p::P2Only) = species_spec(p.a)
AUESeamBed.uses_two_phase_memory(::P2Only) = true
AUESeamBed.is_run_invalid_exception(p::P2Only, e) = AUESeamBed.is_run_invalid_exception(p.a, e)
for f in (:state_digest, :is_alive, :body_cell_ids, :body_balances, :port_balance, :port_outflow, :total_matter, :memory_bytes, :digest_excl_settle)
    @eval AUESeamBed.$f(p::P2Only, st) = AUESeamBed.$f(p.a, st)
end
AUESeamBed.settle_species_memory!(p::P2Only, w, alive::Bool, b::Budget) = settle_species_memory!(p.a, w, alive, b)
function AUESeamBed.step_species_pre_settle(p::P2Only, st, si::StampedInput, ::Budget)
    mid = AM.AUEAMemState(deepcopy(st.life), st.pred, copy(st.M), st.cfg, st.exp_step + 1, AM.NOPENDING, st.last_rec)
    return (mid, AM._out(p.a, mid), StepCost(0, 0.0, 0.0, 0.0), nothing)
end

# Single-phase wrapper (4-seam negatives): the inner adapter's step with its output / cost rewritten.
struct WrapSingle <: AbstractSpeciesAdapter
    inner::AbstractSpeciesAdapter
    fout::Function
    fcost::Function
end
AUESeamBed.species_spec(w::WrapSingle) = species_spec(w.inner)
AUESeamBed.state_digest(w::WrapSingle, st) = state_digest(w.inner, st)
function AUESeamBed.step_species(w::WrapSingle, st, si::StampedInput, b::Budget)
    ns, out, c, alive, sp = step_species(w.inner, st, si, b)
    return (ns, w.fout(out), w.fcost(c), alive, sp)
end

# ================================================================ 4-seam regression (spec §6, bed_mem.jl)
const FORBIDDEN14 = ["AUE-A", "AUE-B", "AUEA", "AUEB", "OneLife", "LabCore", "NestingCPCC", "CPC-Prolif", "Runaway-Cancer",
                     "body_org", "TracePred", "R-MID", "ctx_key", "S90MemCore"]
const AUEB_TOML = joinpath(LAB91, "experiments", "aue_seam", "species_aue_b.toml")
aueb_spec(f = identity) = load_species_spec_text(f(read(AUEB_TOML, String)))
mem_text(cap = :C2) = AM.capacity_spec_text(cap)

# aueb_wrap: applied to the AUE-B adapter of the 120-step regression run (identity in production; NC-M1c only).
function gate_4seam(; io = stdout, inj = NamedTuple(), aueb_wrap = identity)
    # static invariant: zero species-specific tokens in bed_mem.jl
    src = read(joinpath(S91, "bed_mem.jl"), String)
    leaked = [t for t in FORBIDDEN14 if occursin(t, src)]
    chk(isempty(leaked), "4-seam: bed_mem.jl contains species tokens $(leaked)")
    println(io, "PASS 4-seam static: bed_mem.jl contains 0 of the 14 species tokens")

    # unchanged adapter_aue_b.jl ([memory] absent: single-phase path) 120 steps; per-step direct NestingCPCC (full theta); replay; tamper
    sd = tseed(919001)
    adb = aueb_wrap(AUEBAdapter(; organ_type = "cpc_local_link_pruning"))
    chk(!species_spec(adb).has_memory && species_spec(adb).memory_c_spec == 0 && species_spec(adb).memory_reserved_bytes == 8,
        "4-seam: AUE-B spec defaults are not B = 8, C_spec = 0")
    dig = String[]
    st1, inb, tape, thetas = make_aue_b_initial_state(:CPC, sd)
    r1 = run_species!(adb, "aue-b-cpc-91", st1, inb; on_step = (s, st, d) -> push!(dig, d))
    st2, _, _, _ = make_aue_b_initial_state(:CPC, sd)
    r2 = run_species!(adb, "aue-b-cpc-91", st2, inb)
    st3, _, _, _ = make_aue_b_initial_state(:CPC, sd)
    rp = replay_from_audit(adb, st3, r1.audit)
    ref = String[]
    sys = NestingCPCC.init_system(:CPC, thetas)
    for k in 1:length(tape); NestingCPCC.step!(sys, tape[k], k); push!(ref, canonical_aue_b_digest(sys)); end
    chk(length(dig) == length(tape) == 120 && dig == ref, "4-seam: AUE-B per-step digests differ from direct NestingCPCC")
    chk(r1.final_digest == r2.final_digest == rp.final_digest && verify_audit_chain(r1.audit), "4-seam: AUE-B not deterministic / replay differs")
    chk(canonical_aue_b_digest(NestingCPCC.run_config(:CPC, sd).sys) == r1.final_digest, "4-seam: AUE-B final digest != NestingCPCC.run_config")
    chk(!any(r -> occursin("mem_", r.payload), r1.audit.rows), "4-seam: single-phase commit rows carry memory fields")
    ta = deepcopy(r1.audit); i = findfirst(r -> r.kind == "input", ta.rows); o = ta.rows[i]
    ta.rows[i] = AuditRow(o.seq, o.kind, o.step, o.payload * " ", o.prev_hash, o.hash)
    ok, m = expect_throw(ChainIntegrityError, () -> replay_from_audit(adb, make_aue_b_initial_state(:CPC, sd)[1], ta)); chk(ok, "4-seam: tampered AUE-B audit: $m")
    println(io, "PASS 4-seam regression: unchanged adapter_aue_b.jl 120 steps = direct NestingCPCC at every step (full theta), deterministic, replay_from_audit equal, 1-character tamper rejected")

    # ports, species boundary
    adm = mkad(:C2; inj = inj); stm = AM.make_s91a_initial_state(tseed(919001), adm); inm = AM.make_s91a_inputs(919001, :env_stat, 3)
    bad = [StampedInput(0, Dict{String,Any}("x" => inb[1].ports["x"], "h" => inb[1].ports["h"], "r" => inb[1].ports["r"], "t_abs" => 1, "hidden_cheat" => 99))]
    for (name, T, f) in (
        ("undeclared input port (AUE-B)", PortViolation, () -> run_species!(adb, "neg-in", make_aue_b_initial_state(:CPC, sd)[1], bad)),
        ("undeclared output port (AUE-B wrapper)", PortViolation, () -> run_species!(
            WrapSingle(adb, o -> DeclaredOutput(merge(o.ports, Dict{String,Any}("secret_sidechannel" => 1)), o.organ_type), identity),
            "neg-out", make_aue_b_initial_state(:CPC, sd)[1], inb[1:3])),
        ("undeclared input port (memory species)", PortViolation, () -> run_species!(adm, "neg-in-m", stm,
            [StampedInput(0, merge(inm[1].ports, Dict{String,Any}("hidden_cheat" => 1)))])),
        ("organ outside allowed_organ_types (AUE-B)", SpeciesBoundaryViolation, () -> run_species!(
            AUEBAdapter(species_spec(adb), "unauthorized_llm_controller", nothing), "neg-organ", make_aue_b_initial_state(:CPC, sd)[1], inb[1:3])),
        ("organ outside allowed_organ_types (memory species)", SpeciesBoundaryViolation, () -> run_species!(
            mkad(:C2; inj = inj, organ_type = "unauthorized_llm_controller"), "neg-organ-m", stm, inm)))
        ok, m = expect_throw(T, f); chk(ok, "4-seam: $name: $m")
    end
    rv = run_species!(AUEBAdapter(species_spec(adb), "cpc_runaway_control", nothing), "pos-organ", make_aue_b_initial_state(:CPC, sd)[1], inb[1:3])
    chk(rv.ledger.steps_completed == 3, "4-seam: allowed organ variant did not pass")
    println(io, "PASS 4-seam ports / species boundary: undeclared input (both paths) / output ports and disallowed organs (both paths) rejected; allowed variant passes")

    # budget: per step, instantaneous rate, rolling 3600 s window (low-window specs on AUE-B); free dormancy
    spec_rate = aueb_spec(t -> rep1(rep1(rep1(t, "step_granularity_sec = 1.0", "step_granularity_sec = 0.01"),
                                      "ops_per_step = 5000", "ops_per_step = 1000"), "ops_per_hour = 18000000", "ops_per_hour = 100000"))
    spec_roll = aueb_spec(t -> rep1(rep1(rep1(t, "step_granularity_sec = 1.0", "step_granularity_sec = 1000.0"),
                                      "ops_per_step = 5000", "ops_per_step = 200"), "ops_per_hour = 18000000", "ops_per_hour = 360"))
    s0() = make_aue_b_initial_state(:CPC, sd)[1]
    rr3 = run_species!(AUEBAdapter(spec_roll, "cpc_local_link_pruning", 100), "pos-roll", s0(), inb[1:3])
    chk(rr3.ledger.steps_completed == 3, "4-seam: rolling window: 3 steps (300 <= 360) did not pass")
    stsp, insp, _, _ = make_aue_b_initial_state(:CPC, sd; emit_spore_at = 2, spore_id = "sp-2")
    rsp = run_species!(adb, "pos-dorm", stsp, insp[1:6])
    chk(rsp.ledger.dormancy_slots_used == 1 && rsp.ledger.cumulative_dormancy_upkeep > 0.0, "4-seam: paid dormancy did not pass")
    for (name, T, f) in (
        ("per-step ops", BudgetViolation, () -> run_species!(AUEBAdapter(species_spec(adb), "cpc_local_link_pruning", 5001), "neg-step", s0(), inb[1:3])),
        ("instantaneous wall-clock rate", BudgetViolation, () -> run_species!(AUEBAdapter(spec_rate, "cpc_local_link_pruning", 100), "neg-rate", s0(), inb[1:3])),
        ("rolling 3600 s window (step 4: 400 > 360)", BudgetViolation, () -> run_species!(AUEBAdapter(spec_roll, "cpc_local_link_pruning", 100), "neg-roll", s0(), inb[1:4])),
        ("free dormancy (spore held at zero upkeep)", DormancyAccountingViolation, () -> run_species!(
            WrapSingle(adb, identity, c -> StepCost(c.ops_used, c.upkeep_paid, c.act_cost, 0.0)), "neg-dorm",
            make_aue_b_initial_state(:CPC, sd; emit_spore_at = 2, spore_id = "sp-2")[1], insp[1:6])),
        ("dormancy upkeep rate 0 at load", DormancyAccountingViolation, () -> aueb_spec(t -> rep1(t, "upkeep_rate_per_slot = 0.01", "upkeep_rate_per_slot = 0.0"))))
        ok, m = expect_throw(T, f); chk(ok, "4-seam: $name: $m")
    end
    println(io, "PASS 4-seam budget / dormancy: per-step, instantaneous-rate and rolling-3600 s-window (low-window spec: 3 steps pass, step 4 rejected) overruns rejected; free dormancy rejected (run and load); paid dormancy passes")

    # absorbing death, zero post-death commits, post-death / death-step spores, lineage child
    adr = AUEBAdapter(; organ_type = "cpc_runaway_control")
    sr, inr, _, _ = make_aue_b_initial_state(:Runaway, sd; emit_spore_at = 5, spore_id = "sp-5")
    rm_ = run_species!(adr, "aue-b-runaway-91", sr, inr); ds = rm_.ledger.death_step
    chk(rm_.ledger.termination == METABOLIC_OR_ORG_DEATH && ds !== nothing && ds > 5, "4-seam: Runaway fixture did not die after the spore")
    chk(count(r -> r.kind == "commit" && r.step > ds, rm_.audit.rows) == 0 && rm_.ledger.steps_completed == ds &&
        rm_.audit.rows[end].kind == "termination", "4-seam: commits after the absorbing death")
    rpm = replay_from_audit(adr, make_aue_b_initial_state(:Runaway, sd; emit_spore_at = 5, spore_id = "sp-5")[1], rm_.audit)
    chk(rpm.ledger.termination == METABOLIC_OR_ORG_DEATH && rpm.audit.rows[end].hash == rm_.audit.rows[end].hash, "4-seam: death replay differs")
    ch = germinate_lineage_child(rm_.ledger, rm_.audit, "sp-5", "child-91")
    chk(!ch.same_individual && ch.lineage_child && ch.verified_pre_death, "4-seam: pre-death spore lineage child")
    ok, m = expect_throw(ProhibitedRescueError, () -> attempt_post_death_spore!(rm_.ledger, rm_.audit, "rescue", ds + 1)); chk(ok, "4-seam: post-death spore: $m")
    ok, m = expect_throw(ProhibitedRescueError, () -> run_species!(adr, "death-step-spore",
        make_aue_b_initial_state(:Runaway, sd; emit_spore_at = ds, spore_id = "sp-d")[1], inr)); chk(ok, "4-seam: death-step spore: $m")
    println(io, "PASS 4-seam absorbing death: Runaway (seed $sd) dies at step $ds, 0 commits after death, replay equal; post-death and death-step spores rejected; pre-death spore -> lineage child")

    # shared-medium double chain (claims parsed from the hash-chained input rows)
    function shared(tag, a1, a2)
        med = SharedMediumAudit("medium-$tag"); i1 = StampedInput[]; i2 = StampedInput[]
        t1 = make_aue_b_initial_state(:CPC, 919001)[2]; t2 = make_aue_b_initial_state(:CPC, 919002)[2]
        for t in 1:5
            record_medium_event!(med, "ev-$tag-$t", t, 5.0)
            push!(i1, StampedInput(t1[t].step, t1[t].ports, [("ev-$tag-$t", a1)]))
            push!(i2, StampedInput(t2[t].step, t2[t].ports, [("ev-$tag-$t", a2)]))
        end
        q1 = run_species!(adb, "ind-$tag-1", make_aue_b_initial_state(:CPC, 919001)[1], i1)
        q2 = run_species!(adb, "ind-$tag-2", make_aue_b_initial_state(:CPC, 919002)[1], i2)
        return (med, q1.audit, q2.audit)
    end
    med, a1, a2 = shared("ok", 3.0, 2.0); chk(verify_shared_medium(med, [a1, a2]), "4-seam: valid shared-medium split rejected")
    med, a1, a2 = shared("ds", 3.0, 3.0)
    ok, m = expect_throw(DoubleSpendViolation, () -> verify_shared_medium(med, [a1, a2])); chk(ok, "4-seam: double spend: $m")
    ta = deepcopy(a2); i = findfirst(r -> r.kind == "input", ta.rows); o = ta.rows[i]
    ta.rows[i] = AuditRow(o.seq, o.kind, o.step, split(o.payload, "|refs=")[1] * "|refs=", o.prev_hash, o.hash)
    ok, m = expect_throw(ChainIntegrityError, () -> verify_shared_medium(med, [a1, ta])); chk(ok, "4-seam: stripped ref: $m")
    println(io, "PASS 4-seam shared medium: valid split passes, double spend (3 + 3 > 5) rejected, stripped event_ref breaks the chain")

    # [memory] schema: invalid tables rejected at load; [memory] on a single-phase adapter rejected at run
    for (name, T, f) in (
        ("header_bytes 7", MemoryAccountingViolation, t -> rep1(t, "\nheader_bytes = 8\n", "\nheader_bytes = 7\n")),
        ("slot_bytes 15", MemoryAccountingViolation, t -> rep1(t, "\nslot_bytes = 16\n", "\nslot_bytes = 15\n")),
        ("reserved_bytes 4 < header", MemoryAccountingViolation, t -> rep1(t, "\nreserved_bytes = 40\n", "\nreserved_bytes = 4\n")),
        ("upkeep_rate_per_slot 0", MemoryAccountingViolation, t -> rep1(t, "\nupkeep_rate_per_slot = 0.002\n", "\nupkeep_rate_per_slot = 0.0\n")),
        ("max_body_cells 0", MemoryAccountingViolation, t -> rep1(t, "\nmax_body_cells = 576\n", "\nmax_body_cells = 0\n")),
        ("max_read_ops_per_step 23 < 24", MemoryAccountingViolation, t -> rep1(t, "\nmax_read_ops_per_step = 24\n", "\nmax_read_ops_per_step = 23\n")),
        ("ops_per_step below mandatory memory ops", BudgetViolation, t -> rep1(t, "ops_per_step = 6000000", "ops_per_step = 1000")),
        ("phenomenal_claim certified", SpeciesBoundaryViolation, t -> rep1(t, "phenomenal_claim = \"not_certified\"", "phenomenal_claim = \"certified\"")))
        ok, m = expect_throw(T, () -> load_species_spec_text(f(mem_text(:C2)))); chk(ok, "4-seam: invalid [memory] $name: $m")
    end
    for c in CAPS91
        sp = load_species_spec_text(mem_text(c))
        chk(sp.has_memory && sp.memory_reserved_bytes == AM.capacity_bytes(c) && sp.memory_c_spec == fld(AM.capacity_bytes(c) - 8, 16),
            "4-seam: capacity $c spec")
    end
    memb = aueb_spec(t -> t * "\n[memory]\nreserved_bytes = 40\nheader_bytes = 8\nslot_bytes = 16\nupkeep_rate_per_slot = 0.002\nmax_body_cells = 4\nmax_read_ops_per_step = 24\n")
    ok, m = expect_throw(MemoryAccountingViolation, () -> run_species!(AUEBAdapter(memb, "cpc_local_link_pruning", nothing), "neg-mem-b", s0(), inb[1:2]))
    chk(ok, "4-seam: [memory] on a single-phase adapter: $m")
    println(io, "PASS 4-seam [memory] schema: 8 invalid tables rejected at load, the 5 capacity texts parse (B, C_spec), [memory] on a single-phase adapter rejected")
    return true
end

# ================================================================ GB-M0 (frozen, seeds, BO_CUR survival, rand_u64)
# Independent mulberry32 (the JavaScript text: a += 0x6D2B79F5; t = imul(a ^ a >>> 15, a | 1); t = (t + imul(t ^ t >>> 7, t | 61)) ^ t;
# out = t ^ t >>> 14), not LabCore.Mulberry; rand_u64 = out1 << 32 | out2 of the stream seeded seed + 100000.
function mulberry32_raw(seed::Integer, n::Integer)
    a = UInt32(mod(Int64(seed), 4294967296)); out = Vector{UInt32}(undef, n)
    for i in 1:n
        a += 0x6D2B79F5
        t = (a ⊻ (a >> 15)) * (a | 0x00000001)
        t = (t + (t ⊻ (t >> 7)) * (t | 0x0000003d)) ⊻ t
        out[i] = t ⊻ (t >> 14)
    end
    return out
end
const RU_910101_S0 = 0x5b64d322fa5eabfb                   # from mulberry32_raw(910101 + 100000, 2)
function acf1(x::Vector{Float64})
    m = sum(x) / length(x)
    num = sum((x[i] - m) * (x[i+1] - m) for i in 1:length(x)-1); den = sum((v - m)^2 for v in x)
    return num / den
end

function gate_gbm0(; io = stdout)
    frozen91a()
    println(io, "PASS GB-M0 frozen91a: freeze-s91a.txt = exactly the 2 entries (predictions.toml, S91a-draft-aue-memory.md), SHA-256 match; mem_core.jl unchanged ($(first(MEMCORE_SHA, 12)))")
    chk(length(SEEDS91) == 36 && isempty(intersect(collect(SEEDS91), MAIN_UNUSED)) && isempty(intersect(collect(SEEDS91), collect(TEST_SEEDS))) &&
        sort(vcat([collect(s) for (_, s) in ENVS91]...)) == collect(SEEDS91), "GB-M0: seed blocks")
    println(io, "PASS GB-M0 seeds: 910101..910136 (36 = 3 x 12) disjoint from 1600:1617, 2860:2899 and the test block 919001..919099")
    ad = mkad(:C0_B8)
    alive = tmap91(s -> (st = AM.make_s91a_initial_state(s, ad); (st.life.t == 800 && !st.life.dead && AUESeamBed.is_alive(ad, st))), collect(SEEDS91))
    chk(all(alive), "GB-M0: BO_CUR 800 steps: not alive for seeds $(collect(SEEDS91)[.!alive])")
    println(io, "PASS GB-M0 BO_CUR: all 36 seeds alive after the 800 BO_CUR steps (t = 800); no other quantity of these seeds is computed in smoke")
    ru = AM.rand_u64_stream(910101, STEPS91)
    raw = mulberry32_raw(910101 + 100_000, 2 * STEPS91)
    ind = [(UInt64(raw[2s-1]) << 32) | UInt64(raw[2s]) for s in 1:STEPS91]
    chk(ru[1] == ind[1] == RU_910101_S0, "GB-M0: rand_u64(910101, s=0) = $(ru[1]), independent $(ind[1]), constant $(RU_910101_S0)")
    chk(ru == ind, "GB-M0: rand_u64 stream of 910101 differs from the independent mulberry32 at some step")
    a1 = acf1(u_of.(ru))
    chk(abs(a1) < 0.1, "GB-M0: |acf1| = $(abs(a1)) >= 0.1")
    println(io, "PASS GB-M0 rand_u64: (910101, s=0) = 0x$(string(ru[1], base = 16)) = independent mulberry32 (all 4000 steps equal); u lag-1 acf1 = $(g6(a1)) (|acf1| < 0.1)")
    return true
end

# ================================================================ GB-M1 (C0 = memoryless OneLife + TracePred + U4 reference)
# The reference: onestep.jl's _live_aue (core/circuit.jl step! + one_life.jl _live copies, draw hook without `old`) and its
# TracePred predict / update, Main's own OneLife (one_life.jl included by onestep.jl), the U4 map pi_u4 on Float32(p).
# ops: the declared count of the branches the reference took (predict 1 + 2 on reset, Float32 2, pi_u4 2 on p1 + p2 == 0 else 8,
# draw 5, update 7), compared with the adapter's executed count on every drawn step.
mutable struct BaseBox; drawn::Bool; a::Int; ans::Bool; pe::TracePred; ops::Int; end
function base_step(life::OneLife, pred::TracePred, g::Tuple{Int,Int}, ru::UInt64)
    life.dead && return (life, pred, false, 0, 0)
    _empty_body(life) && return (_detect(life), pred, false, 0, 0)
    box = BaseBox(false, 0, false, pred, 0); u = u_of(ru); R = body_R(life)
    hook = function (cand, cs, win, key, b, conf, habit, total, y)
        s = sort([m for m in cs if b.patch[m] <= 2]; by = m -> (b.patch[m], m))
        length(unique(b.patch[m] for m in s)) >= 2 || return win
        pe, p1, p2 = predict(pred, R)
        pis = MC.pi_u4(Float32(p1), Float32(p2))
        a = u < Float64(pis[1]) ? 1 : 2
        box.drawn = true; box.a = a; box.ans = y[a] > 0; box.pe = pe
        box.ops = 1 + (1 * K_WIN <= R ? 0 : 2) + 2 + (Float32(p1) + Float32(p2) == 0.0f0 ? 2 : 8) + 5 + 7
        return s[findfirst(m -> b.patch[m] == a, s)]
    end
    nl = Base.invokelatest(_live_aue, hook, life, g, 0.02, 0.004, 0.002, :bin3, true, true, false)
    return (nl, box.drawn ? update(box.pe, box.a, box.ans) : pred, box.drawn, box.a, box.ops)
end
base_digest(life::OneLife, pred::TracePred) = bytes2hex(sha256(vcat(onelife_encode(life), pred_bytes(pred))))
function base_init(seed)
    life = onelife_birth(seed, LawL2)
    for g in LabCore.BO_CUR; life, err = onelife_step(life, Int.(g)); err && error("BO_CUR"); end
    return life
end

# Bed run of a C0 capacity vs the reference from the same life, every step: life + predictor bytes, drawn flag, drawn patch,
# death step; memory bytes all 0x00, memory ops 0, ops = the reference's branch count on drawn steps and 0 otherwise.
function c0_compare(cap, life_a, life_b, ins; inj = NamedTuple(), tag = "")
    ad = mkad(cap; inj = inj)
    chk(ad.cfg.C == 0, "GB-M1: $cap is not C_spec = 0")
    st0 = AM.AUEAMemState(life_a, AM.TracePred(), MC.MemoryState(), ad.cfg, 0, AM.NOPENDING, AM.NOREC)
    chk(bytes2hex(sha256(onelife_encode(life_b))) == bytes2hex(sha256(AM.onelife_encode(life_a))), "GB-M1 $tag: initial lives differ")
    r = bedrun(ad, "gbm1-$cap$tag", st0, ins)
    bl = life_b; bp = TracePred(); nd = 0; dsb = nothing; digs = String[]; nreset = 0
    for si in ins
        s = si.step
        bl, bp, drawn, a, ops_ref = base_step(bl, bp, (Int(si.ports["g1"]), Int(si.ports["g2"])), UInt64(si.ports["rand_u64"]))
        haskey(r.states, s) || break
        st = r.states[s]; rec = st.last_rec
        chk(AM.life_digest(st) == base_digest(bl, bp), "GB-M1 $cap$tag: life + predictor bytes differ from the reference at step $s")
        chk(rec.drawn == drawn && (!drawn || (rec.a_draw == a && rec.a == a)), "GB-M1 $cap$tag: draw / patch differs at step $s")
        chk(rec.read_ops == 0 && rec.k == 0 && !rec.hit1 && !rec.hit2, "GB-M1 $cap$tag: memory read on C_spec = 0 at step $s (ops $(rec.read_ops))")
        chk(rec.ops_pred == (drawn ? ops_ref : 0) && rec.ops_pred <= AM.OPS_PRED_WORST, "GB-M1 $cap$tag: ops_pred $(rec.ops_pred) != reference $ops_ref at step $s")
        drawn && ops_ref == 25 && (nreset += 1)
        sc = r.sets[s]
        chk(sc.ops_used == rec.ops_pred && sc.settle.memory_settle_ops == 0 && sc.settle.memory_write_ops == 0 && sc.verified_paid === 0.0,
            "GB-M1 $cap$tag: memory ops / payment on C_spec = 0 at step $s")
        mb = AUESeamBed.memory_bytes(ad, st)
        chk(length(mb) == AM.capacity_bytes(cap) && all(==(0x00), mb), "GB-M1 $cap$tag: memory bytes not $(AM.capacity_bytes(cap)) x 0x00 at step $s")
        drawn && (nd += 1); push!(digs, AM.life_digest(st))
        _empty_body(bl) && (dsb = s; break)
    end
    chk(r.res.ledger.death_step == dsb, "GB-M1 $cap$tag: death step $(r.res.ledger.death_step) != reference $dsb")
    chk(r.res.ledger.cumulative_memory_ops == 0 && r.res.ledger.cumulative_memory_upkeep === 0.0, "GB-M1 $cap$tag: ledger memory ops / upkeep")
    return (r = r, ad = ad, nd = nd, ds = dsb, digs = digs, nreset = nreset)
end

function gate_gbm1(; io = stdout, inj = NamedTuple(), steps = 1000)
    sd = tseed(919001)
    la = AM.make_s91a_initial_state(sd, mkad(:C0_B8; inj = inj)).life; lb = base_init(sd)
    ins = AM.make_s91a_inputs(sd, :env_stat, steps)
    R = tmap91(c -> c0_compare(c, la, lb, ins; inj = inj), [:C0_B8, :C0_B9])
    chk(R[1].digs == R[2].digs, "GB-M1: C0_B9 life + predictor bytes != C0_B8")
    chk(R[1].nd > 0, "GB-M1: no drawn step")
    println(io, "PASS GB-M1 C0_B8 / C0_B9 = memoryless reference (onestep.jl _live_aue + TracePred + U4) at every step of $steps (seed $sd env_stat): ",
            "life + predictor bytes (rng state, balances, pools), $(R[1].nd) draws and patches, death step $(R[1].ds); memory bytes 8 / 9 x 0x00, memory ops 0")
    # a fixture that dies metabolically on a drawn step (every body cell at B = 0.21, free matter removed)
    fa = famine_life(la; Bv = 0.21); fb = famine_life(lb; Bv = 0.21)
    D = tmap91(c -> c0_compare(c, fa, fb, ins[1:20]; inj = inj, tag = "-death"), [:C0_B8, :C0_B9])
    for d in D
        chk(d.ds !== nothing && d.r.res.ledger.termination == METABOLIC_OR_ORG_DEATH, "GB-M1 death fixture: no metabolic death")
        chk(d.r.states[d.ds].last_rec.drawn, "GB-M1 death fixture: the death step $(d.ds) is not a drawn step")
    end
    println(io, "PASS GB-M1 death on a drawn step (seed $sd, body B = 0.21, A = 0): death at step $(D[1].ds) (drawn), life + predictor (pred digest) bytes = reference at every step, C0_B8 = C0_B9")
    # decision boundary: u == Float64(pi1) -> 2, the next lower 53-bit draw -> 1 (through rand_u64 and Phase 1), and on the hook
    # itself u = prevfloat(Float64(pi1)) -> 1; p1 + p2 == 0 -> (0.5, 0.5)
    r8 = R[1].r; ad8 = R[1].ad; bud = Budget(ad8.spec); nb = 0; pis = Float32[]
    dsteps = sort([s for (s, st) in r8.states if st.last_rec.drawn])
    pick = unique(vcat(dsteps[1:min(4, end)], [s for s in dsteps if r8.states[s].last_rec.pi1 > 0.5f0][1:min(3, end)],
                       [s for s in dsteps if r8.states[s].last_rec.pi1 < 0.5f0][1:min(3, end)]))
    for s in pick
        rec = r8.states[s].last_rec; p = Float64(rec.pi1); prev = before(r8, s)
        for (u, want) in ((p, 2), (p - 2.0^-53, 1))
            mid = step_species_pre_settle(ad8, prev, replace_ru(ins[s+1], ru_of(u)), bud)[1]
            chk(mid.last_rec.drawn && mid.last_rec.pi1 === rec.pi1 && mid.last_rec.u === u && mid.last_rec.a_draw == want,
                "GB-M1 boundary: step $s, u = $u, pi1 = $p: patch $(mid.last_rec.a_draw), expected $want")
        end
        b = prev.life.b; ms = [m for m in eachindex(b.names) if b.kind[m] == 'M' && b.patch[m] <= 2]
        m1 = ms[findfirst(m -> b.patch[m] == 1, ms)]; m2 = ms[findfirst(m -> b.patch[m] == 2, ms)]
        for (u, want) in ((p, 2), (prevfloat(p), 1), (nextfloat(p), 2))
            box = AM._Box(AM.NOREC, prev.pred)
            hook = AM._make_draw(box, ad8, prev, AM.body_R(prev.life), u)
            ex = hook([m1, m2], [m1, m2], m1, nothing, b, nothing, nothing, nothing, [1.0, 1.0, 0.0], prev.life.circuit.active)
            chk(box.rec.drawn && box.rec.pi1 === rec.pi1 && box.rec.a_draw == want && b.patch[ex] == want,
                "GB-M1 boundary (hook): step $s, u = $u, pi1 = $p: patch $(box.rec.a_draw), expected $want")
        end
        nb += 1; push!(pis, rec.pi1)
    end
    chk(nb >= 3 && any(==(0.5f0), pis) && any(!=(0.5f0), pis), "GB-M1 boundary: too few boundary steps ($nb) / pi1 values")
    chk(MC.pi_u4(0.0f0, 0.0f0) === (0.5f0, 0.5f0), "GB-M1: pi_u4(0, 0) != (0.5, 0.5)")
    chk(AM.OPS_PRED_WORST <= 64, "GB-M1: OPS_PRED_WORST")
    println(io, "PASS GB-M1 boundary at $nb drawn steps (pi1 in $(g6(minimum(pis)))..$(g6(maximum(pis)))): u == Float64(pi1) -> patch 2, ",
            "u = Float64(pi1) - 2^-53 -> 1 (rand_u64 through Phase 1), hook u = prevfloat -> 1 / nextfloat -> 2; pi_u4(0, 0) = (0.5, 0.5)")
    # executed operation count (P5): the counted forms equal predict / pi_u4 / update bit for bit and count each branch; the hook's
    # count on the three branches (normal, low-balance reset, p1 + p2 == 0) and the whole drawn step (hook + update 7)
    c = AM.OpCount(0); v = AM.pi_u4_c(0.0f0, 0.0f0, c); chk(v === MC.pi_u4(0.0f0, 0.0f0) && c.n == 2, "GB-M1 ops: pi_u4_c zero branch ($(c.n))")
    c = AM.OpCount(0); v = AM.pi_u4_c(0.3f0, 0.6f0, c); chk(v === MC.pi_u4(0.3f0, 0.6f0) && c.n == 8, "GB-M1 ops: pi_u4_c normal ($(c.n))")
    tp = AM.TracePred(0.3, 0.7)
    c = AM.OpCount(0); v = AM.predict_c(tp, 0.0, c); chk(v === AM.predict(tp, 0.0) && v[2] === 0.5 && c.n == 3, "GB-M1 ops: predict_c reset ($(c.n))")
    c = AM.OpCount(0); v = AM.predict_c(tp, 1.0, c); chk(v === AM.predict(tp, 1.0) && v[2] === 0.3 && c.n == 1, "GB-M1 ops: predict_c normal ($(c.n))")
    for (a_, y_) in ((1, true), (1, false), (2, true), (2, false))
        c = AM.OpCount(0); v = AM.update_c(tp, a_, y_, c); chk(v === AM.update(tp, a_, y_) && c.n == 7, "GB-M1 ops: update_c ($a_, $y_) ($(c.n))")
    end
    s = pick[1]; prev = before(r8, s); b = prev.life.b; ms = [m for m in eachindex(b.names) if b.kind[m] == 'M' && b.patch[m] <= 2]
    m1 = ms[findfirst(m -> b.patch[m] == 1, ms)]; m2 = ms[findfirst(m -> b.patch[m] == 2, ms)]
    hops = Int[]
    for (pred, Rv, want) in ((prev.pred, 1.0, 1 + 2 + 8 + 5), (prev.pred, 0.0, 3 + 2 + 8 + 5), (AM.TracePred(0.0, 0.0), 1.0, 1 + 2 + 2 + 5))
        v = AM.AUEAMemState(prev.life, pred, prev.M, prev.cfg, prev.exp_step, prev.pending_write, prev.last_rec)
        box = AM._Box(AM.NOREC, pred)
        AM._make_draw(box, ad8, v, Rv, 0.25)([m1, m2], [m1, m2], m1, nothing, b, nothing, nothing, nothing, [1.0, 1.0, 0.0], prev.life.circuit.active)
        chk(box.rec.drawn && box.rec.ops_pred == want, "GB-M1 ops: hook count $(box.rec.ops_pred) != $want (R = $Rv, pred $pred)")
        want == 10 && chk(box.rec.pi1 === 0.5f0, "GB-M1 ops: zero branch pi1 $(box.rec.pi1)")
        push!(hops, box.rec.ops_pred)
    end
    nrs = sum(x.nreset for x in R)
    println(io, "PASS GB-M1 ops_pred counted as executed (P5): pi_u4_c zero 2 / normal 8, predict_c reset 3 / normal 1, update_c 7 (all 4 branches), ",
            "values bit-identical to pi_u4 / predict / update; hook (without update) normal $(hops[1]), reset $(hops[2]), p1 + p2 == 0 $(hops[3]); ",
            "whole drawn steps = the reference's branch count on every drawn step of both runs ($(nrs) reset steps), all <= OPS_PRED_WORST = $(AM.OPS_PRED_WORST)")
    return true
end

# ================================================================ GB-M2 (upkeep eviction on real balances, bounds, port 2^40)
const RES_HI91 = ldexp(1.0, 40)
slots_distinct(n; k0 = 100) = [MC.MemSlot(UInt64(k0 + j), 0x01, UInt8(j % 2)) for j in 0:n-1]   # keys >= 100: never read or written
function one_settle(ad, st)                         # the Phase 2 report of st through P2Only (state not changed)
    w = deepcopy(st)
    return settle_species_memory!(ad, w, true, Budget(ad.spec))[2]
end
# p0 such that the settlement of st ends exactly at 2^40 (below 2^40 the grid is 2^-13 and add_down rounds down; the last slot
# lands on 2^40 since its remainder is < 2^-13 < 2^-12, the grid above).
function land_2p40(ad, st)
    p1 = RES_HI91 - 1.0
    w = deepcopy(AM.AUEAMemState(with_port(st.life, p1), st.pred, copy(st.M), st.cfg, st.exp_step, st.pending_write, st.last_rec))
    settle_species_memory!(ad, w, true, Budget(ad.spec))
    D = w.life.w.port.reservoir - p1
    return RES_HI91 - D
end
setport(st, p) = AM.AUEAMemState(with_port(st.life, p), st.pred, copy(st.M), st.cfg, st.exp_step, AM.NOPENDING, st.last_rec)
p2in(st) = [StampedInput(st.exp_step, Dict{String,Any}("g1" => 0, "g2" => 0, "rand_u64" => UInt64(0)))]

# explicit-precision BigFloat helpers (no precision setter anywhere in a gate's computation; see bed_mem.jl)
bf91(x) = BigFloat(x; precision = BIGPREC)
pk91(x::BigFloat) = (precision(x) == BIGPREC || error("BigFloat precision $(precision(x)) != $BIGPREC"); x)
bsum91(xs) = (s = bf91(0); for x in xs; s = pk91(s + bf91(x)); end; s)
const SETPREC_TOKEN = "setprec" * "ision("

# P1: is the do-block precision setter task-local in this Julia? (measured: another task blocked inside the do-block, the main
# task reads the default); the production files never call the setter except bed_mem.jl's one load-time global setting; the
# precision guard rejects a lowered default; 8 threads running the bed's exact checks concurrently get the single-threaded results.
function gate_gbm2_prec(; io = stdout)
    chk(precision(BigFloat) == BIGPREC, "GB-M2 precision: default $(precision(BigFloat)) != $BIGPREC at gate start")
    inside = Channel{Nothing}(1); release = Channel{Nothing}(1)
    t = Threads.@spawn setprecision(BigFloat, 64) do
        put!(inside, nothing); take!(release); precision(BigFloat)
    end
    take!(inside); seen = precision(BigFloat); put!(release, nothing); inner = fetch(t)
    chk(inner == 64 && precision(BigFloat) == BIGPREC, "GB-M2 precision probe: inner $inner, after $(precision(BigFloat))")
    scope = seen == 64 ? "process-global (another task sees 64)" : seen == BIGPREC ? "task-local (another task sees $BIGPREC)" : "unknown ($seen)"
    nb = length(findall(SETPREC_TOKEN, read(joinpath(S91, "bed_mem.jl"), String)))
    na = length(findall(SETPREC_TOKEN, read(joinpath(S91, "adapter_aue_a_mem.jl"), String)))
    chk(nb == 1 && na == 0, "GB-M2 precision: precision setter calls bed_mem.jl $nb (expected 1, load time), adapter $na (expected 0)")
    ok, m = expect_throw(MemoryAccountingViolation, () -> setprecision(() -> memory_rounding_bound(1, 4, 0.002, 1.0, 1.0), BigFloat, 256);
                         want = "precision downgraded")
    chk(ok && precision(BigFloat) == BIGPREC, "GB-M2 precision guard under a lowered default: $m")
    # fixture: the positive control shape (N = 576, 130 slots), checked by verify_memory_settlement and total_matter
    ad = mkad(:C130); cfg = ad.cfg; rng = LabCore.Mulberry(tseed(919006))
    Bv = [10.0 + 90.0 * rng() for _ in 1:576]; Bp = copy(Bv); M = MC.MemoryState(slots_distinct(130)); mem_pre = MC.serialize_memory(cfg, M)
    pref = Ref(300.0); stt = MC.settle_upkeep!(cfg, M, Bp, collect(1:576), pref)
    lo = Float64[x.paid_lo for x in stt.trace if x.purchased]
    sc = SettleCost(length(M.slots), lo, Float64(bsum91(lo)), stt.port_delta, stt.ops, 0)
    tpre = Float64(bsum91(vcat([300.0], Bv))); tpost = Float64(bsum91(vcat([pref[]], Bp))); mem_post = MC.serialize_memory(cfg, M)
    st0 = AM.make_s91a_initial_state(tseed(919006), ad)
    job() = (v = verify_memory_settlement(ad.spec, true, sc, Bv, Bp, 300.0, pref[], tpre, tpost, mem_pre, mem_post);
             (v[1], v[2], v[3], v[4], precision(v[3]), precision(v[4]), AUESeamBed.total_matter(ad, st0), precision(BigFloat)))
    ref = job()
    chk(ref[5] == ref[6] == ref[8] == BIGPREC, "GB-M2 precision: single-threaded reference precision")
    nth = Threads.nthreads()
    chk(nth >= 8, "GB-M2 precision: the concurrency check needs >= 8 threads (got $nth; run with -t 8)")
    seenid = fill(false, Threads.maxthreadid())
    out = tmap91(i -> (seenid[Threads.threadid()] = true; [job() for _ in 1:4]), 1:128)
    nbad = count(r -> r != ref, (r for o in out for r in o))
    chk(nbad == 0, "GB-M2 precision: $nbad of $(4 * 128) concurrent results differ from the single-threaded reference (precision race)")
    chk(precision(BigFloat) == BIGPREC, "GB-M2 precision: default changed after the concurrent run")
    println(io, "PASS GB-M2 BigFloat precision (P1): Julia $(VERSION): the do-block precision setter is $scope; precision setter calls: bed_mem.jl 1 ",
            "(load-time global $BIGPREC), adapter 0; guard rejects a lowered default (256: \"precision downgraded\"); $(4 * 128) concurrent ",
            "verify_memory_settlement + total_matter calls on $nth threads ($(count(seenid)) used; N = 576, kept = $(ref[2])) equal the ",
            "single-threaded result bit for bit, every bound / loss at precision $BIGPREC, default unchanged")
    return true
end

function gate_gbm2(; io = stdout, inj = NamedTuple())
    gate_gbm2_prec(; io = io)
    # depletion fixture: seed 919002, C130 with 130 slots, a single body cell at B = 1.0, env_depl drive (real Phase 1 and 2)
    sd = tseed(919002)
    ad = mkad(:C130; inj = inj)
    base = AM.make_s91a_initial_state(sd, ad)
    st = withmem(base, slots_distinct(130); life = lone_cell_life(base.life; Bv = 1.0))
    r = bedrun(ad, "gbm2-depl", st, AM.make_s91a_inputs(sd, :env_depl, 40))
    ev = [(s, get(x.settle.info, "settle", nothing)) for (s, x) in r.sets if x.alive]
    nev = sum((t === nothing ? 0 : t.upkeep_evicted for (_, t) in ev); init = 0)
    chk(nev >= 1, "GB-M2: no upkeep eviction on the depletion fixture")
    mg = minimum(Float64(x.margin) for (_, x) in r.sets if x.alive)
    println(io, "PASS GB-M2 depletion (seed $sd, C130 x 130 slots, one body cell B = 1.0): upkeep_evicted = $nev over $(length(ev)) alive steps ",
            "(death at $(r.res.ledger.death_step)); every step passed the bed's two-phase checks (min bound - loss = $(gE(mg)))")

    # positive control of the separated bound: 576 cells B_i in [10, 100] (Mulberry(919005)), 130 slots, port 300.0 (unit level)
    ad130 = mkad(:C130; inj = inj); cfg = ad130.cfg; rng = LabCore.Mulberry(tseed(919005))
    Bv = [10.0 + 90.0 * rng() for _ in 1:576]; Bp = copy(Bv); M = MC.MemoryState(slots_distinct(130)); mem_pre = MC.serialize_memory(cfg, M)
    pref = Ref(300.0)
    tot(B, p) = Float64(bsum91(vcat([p], B)))
    tpre = tot(Bv, 300.0)
    stt = MC.settle_upkeep!(cfg, M, Bp, collect(1:576), pref)
    lo = Float64[t.paid_lo for t in stt.trace if t.purchased]
    paid = Float64(bsum91(lo))
    sc = SettleCost(length(M.slots), lo, paid, stt.port_delta, stt.ops, 0)
    vp, kept, bnd, loss = verify_memory_settlement(ad130.spec, true, sc, Bv, Bp, 300.0, pref[], tpre, tot(Bp, pref[]), mem_pre, MC.serialize_memory(cfg, M))
    chk(kept == 130 && length(lo) == 130 && loss <= bnd, "GB-M2 positive control: kept $kept")
    exE = bsum91([pk91(bf91(Bv[i]) - bf91(Bp[i])) for i in 1:576]); pd = pk91(bf91(pref[]) - bf91(300.0)); slo = bsum91(lo)
    cell = pk91(exE - slo); port_side = pk91(slo - pd)
    exact_cells = count(i -> (d = pk91(bf91(Bv[i]) - bf91(Bp[i])); bf91(Float64(d)) == d), 1:576)
    chk(exact_cells == 576, "GB-M2 positive control: $(576 - exact_cells) cells with an inexact total decrement (Sterbenz)")
    println(io, "PASS GB-M2 positive control (N = 576, B_i in [10, 100], kept = 130, port 300.0): passes verify_memory_settlement; ",
            "bound $(gE(bnd)), loss $(gE(loss)) (cell side exact_E - paid $(gE(cell)), port side paid - port_delta $(gE(port_side))), ",
            "bound - loss $(gE(bnd - loss)); every cell's decrement B_pre - B_post exact in Float64 (Sterbenz) 576 / 576")

    # leak injection: matter removed from a body cell after the settlement must be rejected by the separated bound
    l0 = AM.make_s91a_initial_state(tseed(919002), mkad(:C2; inj = inj))
    for (cap, n, port, leak) in ((:C1, 1, :p2p40, 1e-3), (:C130, 130, :p2p40, 0.05), (:C130, 130, 300.0, 1e-10))
        adc = mkad(cap; inj = inj); s1 = withmem(recap(l0, adc), slots_distinct(n))
        p0 = port === :p2p40 ? land_2p40(adc, s1) : port
        s1 = setport(s1, p0)
        cl = Any[]
        run_species!(P2Only(adc), "gbm2-clean", s1, p2in(s1); on_settle = (s, x) -> push!(cl, x))
        x = cl[1]; pp = x.state.life.w.port.reservoir
        chk(x.settle.memory_slots_kept == n && (port !== :p2p40 || pp === RES_HI91), "GB-M2 leak fixture $cap: kept $(x.settle.memory_slots_kept), port_post $pp")
        ok, m = expect_throw(MemoryAccountingViolation, () -> run_species!(P2Only(mkad(cap; inj = inj, inject_leak_amount = leak)), "gbm2-leak", s1, p2in(s1));
                             want = "rounding bound")
        chk(ok, "GB-M2 leak ($cap, kept $n, port_post $pp, leak $leak) not rejected: $m")
        println(io, "PASS GB-M2 leak rejected: kept = $n, port_pre = $(@sprintf("%.17g", p0)), port_post = $(@sprintf("%.17g", pp)), leak = $leak: ",
                "bound $(gE(x.bound)), clean loss $(gE(x.loss)), margin = leak - bound = $(gE(leak - x.bound))")
    end

    # port 2^40, 4 points (C1, kept = 1, Phase 2 only): (a) ends at prevfloat(2^40), (b) ends at 2^40, (c) pre-input nextfloat(2^40),
    # (d) valid prevfloat(2^40) crossing 2^40; (c)(d) -> RunInvalidError with the pre-Phase-2 state intact
    adc = mkad(:C1; inj = inj); s1 = withmem(recap(l0, adc), slots_distinct(1))
    pb = land_2p40(adc, s1); pa = pb - 2.0^-13
    for (name, p0, want) in (("(a)", pa, prevfloat(RES_HI91)), ("(b)", pb, RES_HI91))
        st = setport(s1, p0); cl = Any[]
        r = run_species!(P2Only(adc), "gbm2-port", st, p2in(st); on_settle = (s, x) -> push!(cl, x))
        chk(r.ledger.steps_completed == 1 && cl[1].state.life.w.port.reservoir === want && cl[1].settle.memory_slots_kept == 1,
            "GB-M2 port $name: port_post $(cl[1].state.life.w.port.reservoir), expected $want")
    end
    for (name, p0) in (("(c) pre-input nextfloat(2^40)", nextfloat(RES_HI91)), ("(d) prevfloat(2^40) crossing", prevfloat(RES_HI91)))
        st = setport(s1, p0); d0 = state_digest(adc, st)
        e = try; run_species!(P2Only(adc), "gbm2-port", st, p2in(st)); nothing; catch x; x; end
        chk(e isa RunInvalidError && e.mid_intact && occursin("InvalidResourceError", e.msg), "GB-M2 port $name: $(e === nothing ? "passed" : sprint(showerror, e))")
        chk(state_digest(adc, st) == d0, "GB-M2 port $name: input state changed")
    end
    println(io, "PASS GB-M2 port 2^40: (a) ends at prevfloat(2^40) and (b) ends at 2^40 pass; (c) nextfloat(2^40) and (d) prevfloat(2^40) + paid ",
            "-> InvalidResourceError -> RunInvalidError (run invalid), pre-Phase-2 state bit-identical (mid_intact), input state unchanged")
    return true
end

# ================================================================ GB-M3 (death absorbs, memory frozen)
function gate_gbm3(; io = stdout, inj = NamedTuple())
    sd = tseed(919003)
    ad = mkad(:C2; inj = inj)
    b0 = AM.make_s91a_initial_state(sd, ad)
    st = withmem(b0, [MC.MemSlot(UInt64(100), 0x01, 0x01), MC.MemSlot(UInt64(101), 0x02, 0x00)]; life = famine_life(b0.life; Bv = 0.22))
    ins = inputs_with(sd, 80; g = (0, 0))
    r = bedrun(ad, "gbm3-famine", st, ins); L = r.res.ledger; d = L.death_step
    chk(L.termination == METABOLIC_OR_ORG_DEATH && d !== nothing, "GB-M3: famine fixture did not die")
    x = r.sets[d]; sc = x.settle
    chk(!x.alive && isempty(sc.slot_paid_lo) && sc.memory_upkeep_paid === 0.0 && x.verified_paid === 0.0 && sc.memory_port_delta === 0.0 &&
        sc.memory_settle_ops == 0 && sc.memory_write_ops == 0, "GB-M3: the death step paid / moved / counted memory")
    mid = step_species_pre_settle(ad, before(r, d), ins[d+1], Budget(ad.spec))[1]
    fin = r.res.state
    mpre = AUESeamBed.memory_bytes(ad, mid); mpost = AUESeamBed.memory_bytes(ad, fin)
    chk(memcount(mpre) >= 1, "GB-M3: no kept slot at the death step")
    chk(isequal(body_balances(ad, mid), body_balances(ad, fin)) && isequal(mid.life.w.B, fin.life.w.B) &&
        port_balance(ad, mid) === port_balance(ad, fin) && mpre == mpost && state_digest(ad, mid) == state_digest(ad, fin),
        "GB-M3: Phase 2 changed the state on the death step")
    chk(x.outflow_pre === x.outflow_post === mid.life.w.port.outflow === fin.life.w.port.outflow,
        "GB-M3: port outflow moved on the death step ($(x.outflow_pre) -> $(x.outflow_post))")
    nlive = 0
    for (s, y) in r.sets
        y.alive || continue
        chk(y.outflow_post === y.outflow_pre + y.settle.memory_port_delta && y.settle.memory_port_delta > 0.0,
            "GB-M3: settling step $s: outflow $(y.outflow_pre) -> $(y.outflow_post), port delta $(y.settle.memory_port_delta)")
        nlive += 1
    end
    rows = r.res.audit.rows
    chk(L.steps_completed == d + 1 && count(q -> q.kind == "commit", rows) == d + 1 && count(q -> q.kind == "input", rows) == d + 1 &&
        !any(q -> q.kind in ("commit", "input") && q.step > d, rows) && rows[end].kind == "termination" && sum(values(r.nset)) == d + 1,
        "GB-M3: steps or commits after the death")
    chk(occursin("mem_paid=0;", rows[end-1].payload) || occursin("mem_paid=0.0", rows[end-1].payload) || occursin("mem_paid=0;mem_port_delta=0;mem_ops=0", rows[end-1].payload),
        "GB-M3: death-step commit row memory fields: $(rows[end-1].payload[max(1, end-80):end])")
    println(io, "PASS GB-M3 famine death (seed $sd, C2, 2 slots, B = 0.22, A = 0, drive (0, 0)): death at step $d with kept = $(memcount(mpre)); ",
            "paid === 0.0, port_delta === 0.0, settle / write ops 0, B_post == B_pre, port_post === port_pre, outflow_post === outflow_pre, ",
            "mem_post == mem_pre (independent Phase 1 snapshot, full state digest equal); 0 steps and 0 commits after death")
    # port outflow tamper (P2): Phase 2 adds to w.port.outflow only (outside digest_excl_settle and the port balance)
    ok, m = expect_throw(MemoryAccountingViolation, () -> run_species!(mkad(:C2; inj = inj, inject_outflow_tamper = :dead), "gbm3-of-dead", st, ins);
                         want = "dead step: port outflow changed")
    chk(ok, "GB-M3 outflow tamper on the death step not rejected: $m")
    stp = Ref(-1)
    ok2, m2 = expect_throw(MemoryAccountingViolation, () -> run_species!(mkad(:C2; inj = inj, inject_outflow_tamper = :live), "gbm3-of-live", st, ins;
                                                                         on_step = (s, _, _) -> (stp[] = s)); want = "!== outflow_pre + memory_port_delta")
    chk(ok2 && stp[] == -1, "GB-M3 outflow tamper on a settling step not rejected at the first step: $m2 (last committed step $(stp[]))")
    println(io, "PASS GB-M3 port outflow (P2): $nlive settling steps outflow_post === outflow_pre + memory_port_delta; outflow + 1.0 on the death step ",
            "rejected (\"$(first(m, 70))...\"); outflow + 2^-20 on a settling step rejected at step 0")
    return true
end

# ================================================================ GB-M4 (no future leak, ctx_key = S90 definition, Y_t boundary)
# S90 definition (experiments/s90_l2l_trm/l2l_trm.jl ctx_key with the identity map; c0r_dev/lib.jl R1IDX): s == 0 -> 64, else bit
# i-1 = r[R1IDX[i], s], where column s of the receptor stream r holds the 8 receptor units after step s-1.
const R1IDX_S90 = (1, 2, 3, 4, 7, 8)
function ctx_key_s90(r::AbstractMatrix{Bool}, s::Int)
    s == 0 && return UInt64(64)
    k = UInt64(0)
    for i in 1:6; r[R1IDX_S90[i], s] && (k |= UInt64(1) << (i - 1)); end
    return k
end
full_slots() = [MC.MemSlot(UInt64(k), UInt8(a), UInt8((k + a) % 2)) for k in 0:64 for a in 1:2]   # 130 slots: every key, both patches

function gbm4_trace(ad, st0, ins, tag)
    r = bedrun(ad, "gbm4-$tag", st0, ins)
    S = length(ins); rm_ = falses(8, S)
    for s in 1:S-1; haskey(r.states, s - 1) && (rm_[:, s] .= r.states[s-1].life.circuit.active[1:8]); end
    nk = 0; ndiff = 0
    for s in 0:S-1
        haskey(r.states, s) || break
        rec = r.states[s].last_rec; rec.drawn || continue
        s >= 1 && chk(collect(rm_[:, s]) == before(r, s).life.circuit.active[1:8], "GB-M4 $tag: stream column $s")
        k90 = s == 0 ? UInt64(64) : ctx_key_s90(rm_, s)
        chk(rec.k == k90, "GB-M4 $tag: ctx_key $(rec.k) != S90 definition $k90 at step $s")
        nw = r.states[s].life.circuit.active
        s >= 1 && any(i -> nw[R1IDX_S90[i]] != before(r, s).life.circuit.active[R1IDX_S90[i]], 1:6) && (ndiff += 1)
        nk += 1
    end
    return (r = r, nk = nk, ndiff = ndiff)
end

function gate_gbm4(; io = stdout, inj = NamedTuple(), steps = 300)
    sd = tseed(919001)
    ad = mkad(:C130; inj = inj)
    b0 = AM.make_s91a_initial_state(sd, ad)
    ins = AM.make_s91a_inputs(sd, :env_stat, steps)
    lc = deepcopy(b0.life); LabCore.cross!(lc.b.perm)
    chk(lc.b.perm != b0.life.b.perm, "GB-M4: cross! did not change b.perm")
    T = tmap91(x -> gbm4_trace(ad, x[1], ins, x[2]), [(withmem(b0, full_slots()), "perm"), (withmem(b0, full_slots(); life = lc), "cross")])
    chk(all(t -> t.nk > 0 && t.ndiff > 0, T), "GB-M4: no drawn step / no step where old and nw differ on the 6 packed receptors")
    println(io, "PASS GB-M4 ctx_key = S90 definition (old = receptors after step s-1, R1IDX (1,2,3,4,7,8), s = 0 -> 64) on every drawn step: ",
            "b.perm $(T[1].nk) steps ($(T[1].ndiff) with old != nw on the packed bits), cross!(b.perm) $(T[2].nk) steps ($(T[2].ndiff))")
    # fixed old, changed current y: ctx_key, p_pre, pi, drawn patch bit-identical (through Phase 1, pools rewritten; and on the hook)
    r = T[1].r; bud = Budget(ad.spec); ncmp = 0; nydiff = 0
    hs = sort([s for (s, st) in r.states if st.last_rec.drawn && (st.last_rec.hit1 || st.last_rec.hit2) && s >= 1])
    chk(!isempty(hs), "GB-M4: no drawn step with a memory hit")
    for s in hs[1:min(6, end)]
        prev = before(r, s); rec = r.states[s].last_rec
        for pool in ([0.0, 0.0], [0.1, 0.0], [0.0, 0.1], [0.1, 0.1], [0.03, 0.07], [0.07, 0.03])
            l = deepcopy(prev.life); l.pool .= pool
            v = AM.AUEAMemState(l, prev.pred, prev.M, prev.cfg, prev.exp_step, prev.pending_write, prev.last_rec)
            q = step_species_pre_settle(ad, v, ins[s+1], bud)[1].last_rec
            q.drawn || continue
            chk(q.k === rec.k && q.p1 === rec.p1 && q.p2 === rec.p2 && q.pi1 === rec.pi1 && q.pi2 === rec.pi2 && q.a_draw == rec.a_draw &&
                q.p1_base === rec.p1_base && q.p2_base === rec.p2_base && q.hit1 == rec.hit1 && q.hit2 == rec.hit2,
                "GB-M4: step $s, pools $pool: ctx_key / p / pi / patch changed with the current y")
            ncmp += 1; (q.y1, q.y2) != (rec.y1, rec.y2) && (nydiff += 1)
        end
        b = prev.life.b; ms = [m for m in eachindex(b.names) if b.kind[m] == 'M' && b.patch[m] <= 2]
        m1 = ms[findfirst(m -> b.patch[m] == 1, ms)]; m2 = ms[findfirst(m -> b.patch[m] == 2, ms)]
        ref = nothing
        for y in ([0.0, 0.0, 0.0], [5.0, 0.0, 0.0], [0.0, 5.0, 0.0], [3.0, 3.0, 0.0])
            box = AM._Box(AM.NOREC, prev.pred)
            AM._make_draw(box, ad, prev, AM.body_R(prev.life), rec.u)([m1, m2], [m1, m2], m1, nothing, b, nothing, nothing, nothing, y, prev.life.circuit.active)
            x = box.rec
            t = (x.k, x.p1, x.p2, x.pi1, x.pi2, x.a_draw)
            ref === nothing && (ref = t)
            chk(t === ref && x.k == rec.k, "GB-M4 hook: step $s, y $y: ctx_key / p / pi / patch changed with y")
        end
    end
    chk(ncmp >= 3 && nydiff >= 1, "GB-M4: too few drawn pool variants ($ncmp, $nydiff with another y)")
    println(io, "PASS GB-M4 no future leak: $ncmp drawn Phase 1 variants with rewritten pools ($nydiff with another current y) at $(min(6, length(hs))) hit steps ",
            "and 4 current-y vectors on the hook: ctx_key, p_pre, p_base, pi, drawn patch bit-identical")
    # Y_t is y[a_t] > 0 in the selected-action frame, recorded apart from the harvest take of the executed patch
    nat = [(s, st.last_rec) for t in T for (s, st) in t.r.states if st.last_rec.drawn && st.last_rec.Y_t && st.last_rec.take == 0.0]
    for (_, q) in nat; chk(q.Y_t == ((q.a_draw == 1 ? q.y1 : q.y2) > 0), "GB-M4: Y_t != y[a] > 0"); end
    for t in T, (s, st) in t.r.states
        q = st.last_rec; q.drawn || continue
        chk(q.Y_t == ((q.a_draw == 1 ? q.y1 : q.y2) > 0), "GB-M4: Y_t != (y[a_t] > 0) at step $s")
    end
    # boundary fixture y[a_t] > 0 and take == 0.0: unreachable while the executed patch is the drawn one (its offer y > 0 always
    # harvests min(pool, d U) > 0), so the executed patch is separated from the drawn one (route_det) at a drawn step whose DET patch
    # differs, with the pools rewritten so that the DET patch has y = 0 and the drawn patch y = 5 (the candidates are driven by `old`,
    # not by the current y). The production adapter on the same state executes the drawn patch and harvests (contrast).
    adr = mkad(:C130; inj = inj, route_det = true); found = false
    for s in sort([s for (s, st) in r.states if st.last_rec.drawn && st.last_rec.det_patch != st.last_rec.a_draw])
        q0 = r.states[s].last_rec; prev = before(r, s)
        l = deepcopy(prev.life); l.pool[q0.det_patch] = 0.0; l.pool[q0.a_draw] = 0.1
        v = AM.AUEAMemState(l, prev.pred, prev.M, prev.cfg, prev.exp_step, prev.pending_write, prev.last_rec)
        q = step_species_pre_settle(adr, v, ins[s+1], bud)[1].last_rec
        (q.drawn && q.det_patch == q0.det_patch && q.a_draw == q0.a_draw) || continue
        qp = step_species_pre_settle(ad, v, ins[s+1], bud)[1].last_rec
        chk(q.a == q0.det_patch && (q.a == 1 ? q.y1 : q.y2) == 0.0 && (q.a_draw == 1 ? q.y1 : q.y2) == 5.0 && q.Y_t == true && q.take === 0.0,
            "GB-M4 Y_t boundary: step $s: Y_t $(q.Y_t), take $(q.take), a $(q.a), a_draw $(q.a_draw)")
        chk(qp.drawn && qp.a == qp.a_draw == q0.a_draw && qp.Y_t == true && qp.take > 0.0, "GB-M4 Y_t boundary contrast at step $s")
        found = true
        println(io, "PASS GB-M4 Y_t boundary: natural y[a_t] > 0 & take == 0 steps: $(length(nat)) (unreachable with executed = drawn); fixture step $s ",
                "(pools: DET patch $(q.a) y = 0, drawn patch $(q.a_draw) y = 5; executed = DET): Y_t == true and take == 0.0 recorded separately; ",
                "production adapter on the same state: executed = drawn, take $(g6(qp.take)) > 0; Y_t == (y[a_t] > 0) on every drawn step")
        break
    end
    chk(found, "GB-M4 Y_t boundary: no drawn step with DET patch != drawn patch")
    # harvest on every alive step (P4): non-drawn (single-patch) steps with take > 0, rerun with drive (0, 0) so that no regrowth
    # enters the pools: pool_post[k] === pool_pre[k] - take_k for each patch (the life's own pools, independent of the record).
    # The full-memory traces above draw on every step until death (step 22, upkeep), so the non-drawn steps come from a third natural
    # trace: seed 919004, the same adapter, empty memory (single-patch candidate steps with a positive offer occur from step 4)
    sd4 = tseed(919004); ins4 = AM.make_s91a_inputs(sd4, :env_stat, steps)
    T4 = (r = bedrun(ad, "gbm4-take", AM.make_s91a_initial_state(sd4, ad), ins4), ins = ins4)
    TT = [[(r = t.r, ins = ins) for t in T]; T4]
    ntk = 0; nnd = 0; tot_all = 0.0; tot_drawn = 0.0
    for t in TT, (s, st) in t.r.states
        q = st.last_rec
        chk(q.take_all === q.take1 + q.take2 && (!q.drawn || q.take === (q.a == 1 ? q.take1 : q.take2)), "GB-M4 take record at step $s")
        tot_all += q.take_all; q.drawn && (tot_drawn += q.take)
    end
    for t in TT, s in sort([s for (s, st) in t.r.states if !st.last_rec.drawn && st.last_rec.take_all > 0.0])
        nnd += 1; ntk >= 8 && continue
        prev = before(t.r, s); si = t.ins[s+1]
        z = StampedInput(si.step, Dict{String,Any}("g1" => 0, "g2" => 0, "rand_u64" => si.ports["rand_u64"]))
        mid = step_species_pre_settle(ad, prev, z, bud)[1]; q = mid.last_rec; q0 = t.r.states[s].last_rec
        chk(!q.drawn && q.take_all === q0.take_all && q.take1 === q0.take1 && q.take2 === q0.take2, "GB-M4 take: step $s rerun with drive (0, 0) differs")
        for k in 1:2
            tk = k == 1 ? q.take1 : q.take2
            chk(mid.life.pool[k] === (tk > 0.0 ? prev.life.pool[k] - tk : prev.life.pool[k]),
                "GB-M4 take: step $s patch $k: pool $(prev.life.pool[k]) -> $(mid.life.pool[k]), recorded take $tk")
        end
        ntk += 1
    end
    chk(ntk >= 1, "GB-M4 take: no non-drawn alive step with take > 0")
    println(io, "PASS GB-M4 harvest on every alive step (P4): $nnd non-drawn steps with take > 0; $ntk of them rerun with drive (0, 0): ",
            "pool_post === pool_pre - take per patch (life's own pools); take_all = take1 + take2 on every step; total take ",
            "$(g6(tot_all)) over all steps vs $(g6(tot_drawn)) over drawn steps only")
    return true
end

# ================================================================ GB-M5 (no free holding on non-drawn steps; replay)
function gate_gbm5(; io = stdout, inj = NamedTuple(), steps = 450)
    sd = tseed(919001)
    ad = mkad(:C2; inj = inj)
    mk() = withmem(AM.make_s91a_initial_state(sd, ad), [MC.MemSlot(UInt64(100), 0x01, 0x01), MC.MemSlot(UInt64(101), 0x02, 0x00)])
    ins = AM.make_s91a_inputs(sd, :env_stat, steps)
    r = bedrun(ad, "gbm5", mk(), ins); L = r.res.ledger
    chk(all(==(1), values(r.nset)) && length(r.nset) == L.steps_completed == count(q -> q.kind == "commit", r.res.audit.rows),
        "GB-M5: not exactly one settlement per step")
    nnd = 0; nd = 0
    for s in 0:L.steps_completed-1
        x = r.sets[s]; x.alive || continue
        kpre = length(before(r, s).M.slots); kpre >= 1 || continue
        sc = x.settle; rec = x.state.last_rec
        chk(length(sc.slot_paid_lo) == sc.memory_slots_kept >= 1 && x.verified_paid >= sc.memory_slots_kept * K91 &&
            sc.memory_upkeep_paid === x.verified_paid && sc.memory_settle_ops > 0, "GB-M5: step $s (kept before $kpre): no prepaid settlement")
        chk(x.outflow_post === x.outflow_pre + sc.memory_port_delta, "GB-M5: step $s port outflow != outflow_pre + port delta")
        rec.drawn ? (nd += 1) : (nnd += 1)
    end
    chk(nnd >= 1, "GB-M5: no non-drawn step with a kept slot")
    paidrows = count(q -> q.kind == "commit" && !occursin("mem_paid=0;", q.payload), r.res.audit.rows)
    rp = replay_from_audit(ad, mk(), r.res.audit)
    chk(rp.final_digest == r.res.final_digest && rp.ledger.cumulative_memory_upkeep === L.cumulative_memory_upkeep &&
        rp.ledger.cumulative_memory_ops == L.cumulative_memory_ops, "GB-M5: replay_from_audit differs")
    for kind in ("input", "commit")
        ta = deepcopy(r.res.audit); i = findall(q -> q.kind == kind, ta.rows)[3]; o = ta.rows[i]
        j = findfirst(c -> isdigit(c), collect(o.payload[findfirst(kind == "input" ? "u64:" : "mem_paid=", o.payload)[end]+1:end]))
        pos = findfirst(kind == "input" ? "u64:" : "mem_paid=", o.payload)[end] + j
        ch = o.payload[pos] == '1' ? '2' : '1'
        ta.rows[i] = AuditRow(o.seq, o.kind, o.step, o.payload[1:pos-1] * ch * o.payload[pos+1:end], o.prev_hash, o.hash)
        ok, m = expect_throw(ChainIntegrityError, () -> replay_from_audit(ad, mk(), ta)); chk(ok, "GB-M5: 1-character $kind tamper: $m")
    end
    println(io, "PASS GB-M5 (seed $sd, C2, 2 kept slots never read): one prepaid settlement per step on all $(L.steps_completed) steps; ",
            "$nnd non-drawn and $nd drawn alive steps with kept >= 1 each paid >= kept * K_mem and moved the port outflow by exactly the port delta (commit rows with mem_paid > 0: $paidrows); ",
            "replay_from_audit equal (state, cumulative memory upkeep $(g6(L.cumulative_memory_upkeep)), ops); 1-character input / commit tampers rejected")
    return true
end

# ================================================================ GB-M6 (reachable R1 write -> R-MID hit -> executed patch divergence)
function gate_gbm6(; io = stdout, inj = NamedTuple(), steps = 600)
    sd = tseed(919004)
    ad = mkad(:C130; inj = inj); ad0 = mkad(:C0_B8; inj = inj)
    ins = AM.make_s91a_inputs(sd, :env_stat, steps)
    r = bedrun(ad, "gbm6", AM.make_s91a_initial_state(sd, ad), ins)
    W = sort([s for (s, x) in r.sets if haskey(x.settle.info, "write") && (x.settle.info["write"].appended || x.settle.info["write"].replaced)])
    chk(!isempty(W), "GB-M6: no R1 write from the empty memory in $steps steps")
    for tw in W
        pw = r.states[tw].pending_write; rw = r.states[tw].last_rec
        chk(pw.drawn && r.sets[tw].settle.info["write"].miss && pw.k == rw.k && pw.a == rw.a_draw, "GB-M6: write record at $tw")
        pp = rw.a_draw == 1 ? rw.p1 : rw.p2
        chk((rw.Y_t && pp < 0.5f0) || (!rw.Y_t && pp > 0.5f0), "GB-M6: R1 write at $tw without a strict misprediction (p_pre $pp, Y_t $(rw.Y_t))")
        ts = [s for s in sort(collect(keys(r.states))) if s > tw && (q = r.states[s].last_rec; q.drawn && q.k == pw.k && (pw.a == 1 ? q.hit1 : q.hit2))]
        isempty(ts) && continue
        th = ts[1]; q = r.states[th].last_rec
        chk(any(x -> x.ctx_key == pw.k && x.action == UInt8(pw.a), before(r, th).M.slots), "GB-M6: slot not kept at the hit")
        pon = Float64(q.pi1); poff = Float64(MC.pi_u4(q.p1_base, q.p2_base)[1])
        pon == poff && continue
        lo, hi = minmax(pon, poff); u = lo; ru = ru_of(u)
        chk(lo <= u_of(ru) < hi, "GB-M6: draw outside [min, max)")
        si = replace_ru(ins[th+1], ru); prev = before(r, th)
        ron = bedrun(ad, "gbm6-on", prev, [si]); roff = bedrun(ad0, "gbm6-off", recap(prev, ad0), [si])
        qon = ron.states[th].last_rec; qoff = roff.states[th].last_rec
        chk(qon.drawn && qoff.drawn && Float64(qon.pi1) == pon && Float64(qoff.pi1) == poff && (pw.a == 1 ? qon.hit1 : qon.hit2) && !qoff.hit1 && !qoff.hit2,
            "GB-M6: the hit step did not recompute the recorded pi (ON $(qon.pi1), OFF $(qoff.pi1))")
        aon = u < pon ? 1 : 2; aoff = u < poff ? 1 : 2
        actson = AM.onelife_acts(ron.states[th].life); actsoff = AM.onelife_acts(roff.states[th].life)
        chk(aon != aoff, "GB-M6: design error (no divergence expected)")
        chk(qon.a == aon && qoff.a == aoff && aon in actson && !((3 - aon) in actson) && aoff in actsoff && !((3 - aoff) in actsoff),
            "GB-M6: executed patch C130 $(qon.a) (acts $actson), C0_B8 $(qoff.a) (acts $actsoff); expected $aon / $aoff")
        cz = cause91(qon.a, qon.u, MC.pi_u4(qon.p1_base, qon.p2_base)[1], qon.hit1 || qon.hit2)
        chk(cz == "R-MID", "GB-M6: first-divergence cause on the R-MID fixture is $cz")
        # cause unit checks (P3): pi_ON 0.625, pi_OFF 0.5, pi_C0 0.75, u 0.6875 -> a_ON 2 = a_OFF 2, a_C0 1: economic; u 0.5625 -> a_ON 1, a_OFF 2: R-MID
        u1 = 0.6875; chk((u1 < 0.625 ? 1 : 2) == 2 && (u1 < 0.75 ? 1 : 2) == 1, "GB-M6 cause: counterexample design")
        chk(cause91(2, u1, 0.5f0, true) == "economic", "GB-M6 cause: (0.625, 0.5, 0.75, 0.6875) is not economic")
        chk(cause91(1, 0.5625, 0.5f0, true) == "R-MID", "GB-M6 cause: (0.625, 0.5, u 0.5625) is not R-MID")
        chk(cause91(1, 0.5625, 0.5f0, false) == "economic", "GB-M6 cause: no hit must be economic")
        chk(cause91(2, 0.5, 0.5f0, true) == "economic" && cause91(1, prevfloat(0.5), 0.5f0, true) == "economic", "GB-M6 cause: u boundary at pi_OFF")
        println(io, "PASS GB-M6 (seed $sd, C130 from empty memory): R1 write at step $tw (key $(pw.k), patch $(pw.a), Y_t $(rw.Y_t), p_pre $(g6(pp)) strictly wrong), ",
                "R-MID hit at step $th (same key and patch); u = $(g6(u)) in [min, max) of pi_ON $(g6(pon)) / pi_OFF $(g6(poff)): ",
                "executed patch C130 $(qon.a), C0_B8 $(qoff.a) (same prefix state), both acted on the body; first-divergence cause R-MID ",
                "(a_ON != a_OFF on the C run's own pi_OFF); cause units: (pi_ON 0.625, pi_OFF 0.5, pi_C0 0.75, u 0.6875) -> economic, u 0.5625 -> R-MID, no hit -> economic")
        return true
    end
    error("GB-M6: no R1 write followed by an R-MID hit with pi_ON != pi_OFF in $steps steps")
end

# ================================================================ smoke
const GATES91 = (("4-seam", gate_4seam), ("GB-M0", gate_gbm0), ("GB-M1", gate_gbm1), ("GB-M2", gate_gbm2), ("GB-M3", gate_gbm3),
                 ("GB-M4", gate_gbm4), ("GB-M5", gate_gbm5), ("GB-M6", gate_gbm6))
function smoke_gates(io)
    for (name, g) in GATES91
        t0 = time()
        try
            g(; io = io)
        catch e
            error("$name: $(first(sprint(showerror, e), 600))")
        end
        @printf(io, "  (%s %.0f s)\n", name, time() - t0); flush(io)
    end
end
function smoke91()
    t0 = time()
    try
        smoke_gates(stdout)
    catch e
        println("GATE FAILURE: ", sprint(showerror, e)); exit(1)
    end
    println("ALL GATES PASS (4-seam regression, GB-M0..GB-M6). No run metrics and no E1-E3 computed in smoke.")
    @printf("time: %.0f s, threads %d\n", time() - t0, Threads.nthreads())
end

# ================================================================ run (spec §5, §7); not executed before the independent I-R
# gate priority (spec §7): the NC log counts only if it ends with the all-failed line and records the SHA-256 of the 5 files exactly
# once each ("sha256 <name> <hex>"), all equal to the files now on disk; returns nothing or the reason
const NCFILES91 = (("bed_mem.jl", joinpath(S91, "bed_mem.jl")), ("adapter_aue_a_mem.jl", joinpath(S91, "adapter_aue_a_mem.jl")),
                   ("s91a_run.jl", joinpath(S91, "s91a_run.jl")), ("neg_controls.jl", joinpath(S91, "neg_controls.jl")),
                   ("mem_core.jl", joinpath(LAB91, MEMCORE_PATH)))
const NCLAST91 = "negative controls: all 13 failed at their intended gates"
function nc_log_check(lines)
    (!isempty(lines) && last(lines) == NCLAST91) || return "last line is not the all-failed line"
    for (f, path) in NCFILES91
        h = [l[length("sha256 $f ")+1:end] for l in lines if startswith(l, "sha256 $f ")]
        length(h) == 1 || return "sha256 $f recorded $(length(h)) times"
        (occursin(r"^[0-9a-f]{64}$", h[1]) && h[1] == bytes2hex(open(sha256, path))) || return "sha256 $f differs from the file on disk"
    end
    return nothing
end

# One run (seed, environment, capacity), 4000 steps, through the bed; per-step records of the drawn / executed patch, hits,
# predictions, writes, payments; replay_from_audit checked. A RunInvalidError marks the run invalid (excluded, counted).
function run_one(seed::Integer, env::Symbol, cap::Symbol; steps = STEPS91)
    ad = mkad(cap)
    ins = AM.make_s91a_inputs(seed, env, steps)
    n = steps
    drawn = falses(n); alive = falses(n); aex = zeros(Int8, n); hit = falses(n); anyhit = falses(n); pidiff = falses(n)
    pon = fill(NaN32, n); poff = fill(NaN32, n); yt = falses(n); take = zeros(n); uu = fill(NaN, n); pioff = fill(NaN32, n)
    nw = 0; nclr = 0; nd1 = 0; nev = 0; Bfam = NaN; pass1 = false; sumB = 0.0
    function onset(s, x)
        st = x.state; q = st.last_rec; alive[s+1] = true; take[s+1] = q.take_all
        if q.drawn
            drawn[s+1] = true; aex[s+1] = q.a
            h = q.a == 1 ? q.hit1 : q.hit2
            hit[s+1] = h; anyhit[s+1] = q.hit1 || q.hit2
            pidiff[s+1] = q.pi1 !== MC.pi_u4(q.p1_base, q.p2_base)[1]
            uu[s+1] = q.u; pioff[s+1] = MC.pi_u4(q.p1_base, q.p2_base)[1]
            pon[s+1] = q.a == 1 ? q.p1 : q.p2; poff[s+1] = q.a == 1 ? q.p1_base : q.p2_base
            yt[s+1] = (q.a == 1 ? q.y1 : q.y2) > 0
        end
        w = get(x.settle.info, "write", nothing)
        if w !== nothing
            (w.appended || w.replaced) && (nw += 1); w.cleared && (nclr += 1); w.evicted_d1 && (nd1 += 1)
        end
        t = get(x.settle.info, "settle", nothing); t === nothing || (nev += t.upkeep_evicted)
        s == 119 && (Bfam = AM.body_R(st.life))                       # famine entry: sum w.B[body] before step 120
        s == 199 && x.alive && (pass1 = true)                        # first famine s = 120..199 passed
        s == steps - 1 && x.alive && (sumB = AM.body_R(st.life))
    end
    res = nothing; invalid = false; inv_step = -1
    try
        res = run_species!(ad, "s91a-$env-$seed-$cap", AM.make_s91a_initial_state(seed, ad), ins; on_settle = onset)
    catch e
        e isa RunInvalidError || rethrow()
        invalid = true; inv_step = e.step
    end
    if invalid
        return (seed = seed, env = env, cap = cap, valid = false, inv_step = inv_step)
    end
    L = res.ledger
    rp = replay_from_audit(ad, AM.make_s91a_initial_state(seed, ad), res.audit)
    replay_ok = rp.final_digest == res.final_digest && rp.ledger.cumulative_memory_upkeep === L.cumulative_memory_upkeep
    died = L.termination == METABOLIC_OR_ORG_DEATH
    return (seed = seed, env = env, cap = cap, valid = true, inv_step = -1, replay_ok = replay_ok,
            died = died, surv = died ? L.death_step : steps, final_B = died ? 0.0 : sumB, paid = L.cumulative_memory_upkeep,
            drawn = drawn, alive = alive, aex = aex, hit = hit, anyhit = anyhit, pidiff = pidiff, uu = uu, pioff = pioff, pon = pon, poff = poff, yt = yt, take = take,
            nw = nw, nclr = nclr, nd1 = nd1, nev = nev, Bfam = Bfam, pass1 = pass1)
end

brier91(p::Float32, y::Bool) = (Float64(p) - (y ? 1.0 : 0.0))^2
acc91(p::Float32, y::Bool) = y ? p > 0.5f0 : p < 0.5f0
# (C, C0_B8) pair on one seed: jointly alive (both runs executed the step), jointly drawn steps; the first step with another
# executed patch and its cause (P3): R-MID iff the C run had a memory hit there and its executed patch differs from the patch the
# same u draws on the C run's own memoryless pi_OFF = pi_u4(p1_base, p2_base); else economic (body_R / K_win). A pi that differs
# without changing the patch (e.g. pi_ON 0.625, pi_OFF 0.5, pi_C0 0.75, u 0.6875) is economic.
cause91(a_on::Integer, u::Float64, pi_off::Float32, hit::Bool) = (hit && a_on != (u < Float64(pi_off) ? 1 : 2)) ? "R-MID" : "economic"
function pair91(c, b)
    js = [i for i in eachindex(c.drawn) if c.alive[i] && b.alive[i] && c.drawn[i] && b.drawn[i]]
    dv = [i for i in js if c.aex[i] != b.aex[i]]
    first_cause = isempty(dv) ? "" : cause91(c.aex[dv[1]], c.uu[dv[1]], c.pioff[dv[1]], c.anyhit[dv[1]])
    return (njoint = length(js), ndiv = length(dv), first = isempty(dv) ? -1 : dv[1] - 1, cause = first_cause, dsurv = c.surv - b.surv)
end

function run91()
    t00 = time(); io = IOBuffer(); gates_ok = true; msg = ""
    tee(s) = (println(io, s); println(s); flush(stdout))
    try
        frozen91a()
        ncf = joinpath(OUT91, "neg_controls.out")
        isfile(ncf) || error("NC-M1..NC-M8: out/neg_controls.out missing")
        ncr = nc_log_check(readlines(ncf)); ncr === nothing || error("NC-M1..NC-M8 (out/neg_controls.out): $ncr")
        tee("PASS NC-M1..NC-M8: 13 negative controls failed at their intended gates (out/neg_controls.out; SHA-256 of $(join(first.(NCFILES91), " / ")) = files on disk)")
        sb = IOBuffer(); smoke_gates(sb); tee(String(take!(sb)))
    catch e
        gates_ok = false; msg = sprint(showerror, e)
    end
    if !gates_ok
        tee("GATE FAILURE: $(first(msg, 600))")
        tee("S91a-E1: miss\nS91a-E2: undecidable\nS91a-E3: undecidable\n(gate priority rule, spec r3 §7)")
        write(joinpath(OUT91, "s91a.out"), String(take!(io))); exit(1)
    end
    jobs = [(seed, env, cap) for (env, seeds) in ENVS91 for seed in seeds for cap in CAPS91]
    R = tmap91(j -> run_one(j...), jobs)
    tee(@sprintf("runs: %d (3 environments x 12 seeds x 5 capacities, %d steps each), %.0f s, threads %d", length(R), STEPS91, time() - t00, Threads.nthreads()))
    report91(R, tee, ENVS91)
    tee("disclosure: Part 1 self-checks touched production seeds 910101 and 910125 prior to Part 2 (no C0_B8 run on 910125, zero parameter/spec/code tuning). Primary verdicts above use all 36 frozen seeds.")
    ENVS91_34 = ((:env_stat, [s for s in 910101:910112 if s != 910101]), (:env_rev, collect(910113:910124)), (:env_depl, [s for s in 910125:910136 if s != 910125]))
    tee("== [SENSITIVITY 34-SEED (excl. 910101, 910125); descriptive sensitivity only, not primary verdicts]")
    report91(R, tee, ENVS91_34; label = "[SENSITIVITY-34] ")
    @printf(io, "time: %.0f s, threads %d\n", time() - t00, Threads.nthreads())
    write(joinpath(OUT91, "s91a.out"), String(take!(io)))
end

# The 15-cell table and E1-E3 from the run results R (envs: (env, seeds) in the order env_stat, env_rev, env_depl).
function report91(R, tee, envs; label = "")
    get1(env, seed, cap) = R[findfirst(x -> x.env == env && x.seed == seed && x.cap == cap, R)]
    tee("== all 15 cells (descriptive; no capacity is selected, #89). Pairs are (C, C0_B8) on the same seed, both valid.")
    for (env, seeds) in envs, cap in CAPS91
        rs = [get1(env, s, cap) for s in seeds]; v = [x for x in rs if x.valid]
        ninv = count(x -> !x.valid, rs)
        nd = sum((count(x.drawn) for x in v); init = 0); nal = sum((count(x.alive) for x in v); init = 0)
        hs = [(x, i) for x in v for i in findall(x.hit)]
        dB = [brier91(x.pon[i], x.yt[i]) - brier91(x.poff[i], x.yt[i]) for (x, i) in hs]
        seedB = [mean0([brier91(x.pon[i], x.yt[i]) - brier91(x.poff[i], x.yt[i]) for i in findall(x.hit)]) for x in v if any(x.hit)]
        aon = mean0([acc91(x.pon[i], x.yt[i]) for (x, i) in hs]); aoff = mean0([acc91(x.poff[i], x.yt[i]) for (x, i) in hs])
        P = [pair91(x, get1(env, x.seed, :C0_B8)) for x in v if get1(env, x.seed, :C0_B8).valid]
        tee("$env $cap: valid $(length(v)) / invalid $ninv (invalid steps $(join([x.inv_step for x in rs if !x.valid], ",")))")
        tee("    drawn $nd  non-drawn alive $(nal - nd)  |R_hit| $(length(hs))  R1 writes $(sum((x.nw for x in v); init = 0))  " *
            "K-UNIQ-CLEAR $(sum((x.nclr for x in v); init = 0))  D1 $(sum((x.nd1 for x in v); init = 0))  upkeep_evicted $(sum((x.nev for x in v); init = 0))  " *
            "paid $(g6(sum((x.paid for x in v); init = 0.0)))")
        tee("    vs C0_B8: seeds with a_exec divergence $(count(p -> p.ndiv > 0, P)) / $(length(P))  first cause R-MID $(count(p -> p.cause == "R-MID", P)) " *
            "economic $(count(p -> p.cause == "economic", P))  unequal survival without divergence $(count(p -> p.ndiv == 0 && p.dsurv != 0, P))")
        tee("    hit dBrier pooled $(g6(mean0(dB)))  seed-equal $(g6(mean0(seedB)))  acc_ON - acc_OFF $(g6(aon - aoff))  take $(g6(sum((sum(x.take) for x in v); init = 0.0)))")
        tee("    surv mean $(g6(mean0([x.surv for x in v])))  completion $(g6(mean0([!x.died for x in v])))  final_B mean $(g6(mean0([x.final_B for x in v])))  " *
            (env === :env_depl ? "famine-entry sum B mean $(g6(mean0([x.Bfam for x in v if !isnan(x.Bfam)])))  first famine passed $(g6(mean0([x.pass1 for x in v])))  " : "") *
            "replay match $(g6(mean0([x.replay_ok for x in v])))")
    end
    # E1
    e1 = "miss"; anypair = false
    for (env, seeds) in envs
        a = all(cap -> (v = [get1(env, s, cap) for s in seeds if get1(env, s, cap).valid];
                        sum((x.nw for x in v); init = 0) >= 1 && sum((x.paid for x in v); init = 0.0) > 0.0), FINCAPS91)
        b = false
        for cap in FINCAPS91, s in seeds
            c = get1(env, s, cap); z = get1(env, s, :C0_B8)
            (c.valid && z.valid) || continue
            anypair = true; pair91(c, z).ndiv > 0 && (b = true)
        end
        tee("$(label)E1 $env: (a) R1 writes >= 1 and paid > 0 on all of C1 / C2 / C130: $a  (b) a_exec divergence on >= 1 valid seed: $b")
        (a && b) && (e1 = "hit")
    end
    anypair || (e1 = "undecidable")
    # E2
    ds = [get1(:env_depl, s, :C130).surv - get1(:env_depl, s, :C0_B8).surv for s in envs[3][2] if get1(:env_depl, s, :C130).valid && get1(:env_depl, s, :C0_B8).valid]
    e2 = isempty(ds) ? "undecidable" : mean0(ds) < 0 ? "hit" : "miss"
    tee("$(label)E2 env_depl (C130, C0_B8): valid pairs $(length(ds))  mean surv diff $(g6(mean0(ds)))")
    # E3
    v130 = [get1(env, s, :C130) for (env, seeds) in envs[1:2] for s in seeds]
    dB = Float64[]
    for x in v130, i in (x.valid ? findall(x.hit) : Int[])
        push!(dB, brier91(x.pon[i], x.yt[i]) - brier91(x.poff[i], x.yt[i]))
    end
    seedB130 = [mean0([brier91(x.pon[i], x.yt[i]) - brier91(x.poff[i], x.yt[i]) for i in findall(x.hit)]) for x in v130 if x.valid && any(x.hit)]
    e3 = isempty(dB) ? "undecidable" : mean0(dB) < 0 ? "hit" : "miss"
    tee("$(label)E3 env_stat + env_rev C130: |R_hit(130)| $(length(dB))  mean dBrier $(g6(mean0(dB)))  seed-equal mean dBrier $(g6(mean0(seedB130)))  eligible_seeds $(length(seedB130))")
    tee("$(label)S91a-E1: $e1\n$(label)S91a-E2: $e2\n$(label)S91a-E3: $e3")
    tee("note: capacities are all reported, none is adopted (#89). E1 is a wiring check, not efficacy. phenomenal_claim = :not_certified.")
    return (e1 = e1, e2 = e2, e3 = e3)
end

if abspath(PROGRAM_FILE) == @__FILE__
    (isempty(ARGS) || ARGS[1] == "smoke") ? smoke91() : ARGS[1] == "run" ? run91() : error("smoke|run")
end
