# S91a negative controls NC-M1..NC-M8 (discussion/specs/S91a-draft-aue-memory.md r3 §6; 13 cases).
# Each case runs one gate of s91a_run.jl (or, for NC-M2c, the bed on a Phase-2-only fixture) with one injection and must fail
# there with the intended exception type and message fragment; any other outcome (pass, another type, another message) fails.
# Records the SHA-256 of the 4 implementation files and the unchanged mem_core.jl ("sha256 <name> <hex>", nc_log_check format).
# Fixtures use only the test seeds 919001..919099 (through the gates). phenomenal_claim = :not_certified (fixed).
# usage: julia --project=. -t 8 experiments/s91_aue_memory/neg_controls.jl | tee experiments/s91_aue_memory/out/neg_controls.out

include(joinpath(@__DIR__, "s91a_run.jl"))

# NC-M1c: the AUE-B adapter with one step dropped (step `at` returns the input state unadvanced; output and cost from a copy).
struct SkipStepB <: AbstractSpeciesAdapter
    inner::AbstractSpeciesAdapter
    at::Int
end
AUESeamBed.species_spec(w::SkipStepB) = species_spec(w.inner)
AUESeamBed.state_digest(w::SkipStepB, st) = state_digest(w.inner, st)
function AUESeamBed.step_species(w::SkipStepB, st, si::StampedInput, b::Budget)
    si.step == w.at || return step_species(w.inner, st, si, b)
    _, out, c, alive, sp = step_species(w.inner, deepcopy(st), si, b)
    return (st, out, c, alive, sp)
end

# NC-M2c: kept == 0 by construction (C2, empty memory, Phase 1 of P2Only has no pending write).
function nc_scalar_inflate()
    ad = mkad(:C2; inject_scalar_inflate = true)
    st = recap(AM.make_s91a_initial_state(tseed(919002), mkad(:C2)), ad)
    chk(isempty(st.M.slots), "NC-M2c fixture: memory not empty")
    run_species!(P2Only(ad), "nc-m2c", st, p2in(st))
    return true
end

quiet(g; kw...) = () -> g(; io = devnull, kw...)

const NCCASES = (
    ("NC-M1a", "GB-M1", MemoryAccountingViolation, "memory surplus bytes not zero", quiet(gate_gbm1; inj = (inject_c0b9_surplus = true,))),
    ("NC-M1b", "GB-M1", ErrorException, "memory read on C_spec = 0", quiet(gate_gbm1; inj = (inject_c0_ctx = true,))),
    ("NC-M1c", "4-seam", ErrorException, "AUE-B per-step digests differ from direct NestingCPCC",
     quiet(gate_4seam; aueb_wrap = a -> SkipStepB(a, 60))),
    ("NC-M2a", "bed_mem (GB-M5 run)", MemoryAccountingViolation, "(fictitious payment)", quiet(gate_gbm5; inj = (inject_fake_paid = true,))),
    ("NC-M2b", "bed_mem (GB-M5 run)", MemoryAccountingViolation, "reported port delta", quiet(gate_gbm5; inj = (inject_fake_port_delta = true,))),
    ("NC-M2c", "bed_mem (P2Only, kept 0)", MemoryAccountingViolation, "memory_upkeep_paid 1.0 !== verified 0.0", nc_scalar_inflate),
    ("NC-M3", "GB-M4", ErrorException, "!= S90 definition", quiet(gate_gbm4; inj = (inject_leak_nw = true,))),
    ("NC-M4", "bed_mem (GB-M5)", MemoryAccountingViolation, "(unpaid holding)", quiet(gate_gbm5; inj = (inject_free_hold = true,))),
    ("NC-M5", "GB-M6", ErrorException, "GB-M6: executed patch", quiet(gate_gbm6; inj = (route_det = true,))),
    ("NC-M6", "bed_mem is_alive (GB-M5 run)", MemoryAccountingViolation, "alive judgement false disagrees with body cells",
     quiet(gate_gbm5; inj = (inject_false_death = true,))),
    ("NC-M7a", "bed_mem digest_excl_settle (GB-M5 run)", MemoryAccountingViolation, "Phase 2 wrote outside {body balances, port, memory}",
     quiet(gate_gbm5; inj = (inject_phase2_tamper = true,))),
    ("NC-M7b", "bed_mem digest_excl_settle (GB-M5 run)", MemoryAccountingViolation, "Phase 2 wrote outside {body balances, port, memory}",
     quiet(gate_gbm5; inj = (inject_pending_tamper = true,))),
    ("NC-M8", "bed_mem mem_pre == mem_init (GB-M6 run)", MemoryAccountingViolation, "Phase 1 wrote the memory bytes (early write)",
     quiet(gate_gbm6; inj = (inject_phase1_write = true,))),
)

function nc91()
    t0 = time()
    frozen91a()
    println("frozen91a: OK (experiments/freeze-s91a.txt, mem_core.jl)")
    for (name, path) in NCFILES91
        println("sha256 $name $(bytes2hex(open(sha256, path)))")
    end
    nfail = 0
    for (case, gate, T, want, f) in NCCASES
        ok, m = expect_throw(T, f; want = want)
        got = replace(first(m, 160), '\n' => ' ')
        println("$case gate=$gate expected=$(nameof(T)) containing $(repr(want)) got: $got => $(ok ? "ok" : "FAIL")"); flush(stdout)
        ok || (nfail += 1)
    end
    @printf("time: %.0f s, threads %d\n", time() - t0, Threads.nthreads())
    if nfail > 0
        println("negative controls: $nfail of $(length(NCCASES)) did not fail at their intended gates"); exit(1)
    end
    length(NCCASES) == 13 || error("expected 13 cases")
    println(NCLAST91)
end

if abspath(PROGRAM_FILE) == @__FILE__
    nc91()
end
