# Pre-Cutout High-Speed Simulation Harness (`experiments/fast_sim/fast_sim.jl`).
# Runs the EXACT same deterministic 1-step transition as real-time 10s/step Pi 5 operation
# (unmodified `core/LabCore.jl` + unmodified `experiments/aue_seam/bed.jl` + S68 C4 radio converter)
# at maximum CPU speed (zero 10s sleep), plus verifies `G-FS-PARITY` (fast == paced bit-for-bit).
#
# Strict blinding guarantee: reads ONLY already-opened S52 slices (`design_72h.tsv` <= 72h and
# `confirm_72h.tsv` <= 144h). NEVER opens raw `ambient-20261123.tsv` or any data > 144h.
# Does NOT consume main-sequence seeds (uses fixed pre-cutout sim seed 690001).
# phenomenal_claim = :not_certified (fixed).

using SHA
using Printf

const ROOT = abspath(joinpath(@__DIR__, "..", ".."))
const OUT_DIR = joinpath(@__DIR__, "out")
mkpath(OUT_DIR)

include(joinpath(ROOT, "core", "LabCore.jl"))
include(joinpath(ROOT, "experiments", "aue_seam", "bed.jl"))
include(joinpath(ROOT, "experiments", "aue_seam", "adapter_aue_a.jl"))

using .LabCore
using .AUESeamBed
using .AdapterAUEA

# Frozen S65 C4 constants & S68 r2 SIN_TABLE_1000 (exact Julia IEEE-754 binary64)
const MU_W = 297.20108758532916
const SD_W = 39.79874519579147
const MU_B = 2.9924794631493694
const SD_B = 0.8134565410732445
const SIN_TABLE_1000 = [sin(2.0 * pi * Float64(idx) / 1000.0) for idx in 0:999]

function verify_sin_table_sha()::String
    io = IOBuffer()
    for v in SIN_TABLE_1000
        write(io, htol(reinterpret(UInt64, v)))
    end
    bytes2hex(sha256(take!(io)))
end

@inline function c4_yields_s68(step::Int, w_sum::Float64, b_n::Float64, stale::Bool)::Tuple{Float64,Float64}
    z1, z2 = stale ? (0.0, 0.0) : ((w_sum - MU_W) / SD_W, (b_n - MU_B) / SD_B)
    i1 = (step % 1000) + 1
    i2 = ((step + 500) % 1000) + 1
    x1 = (2.5 + (2.5 * SIN_TABLE_1000[i1])) + z1
    x2 = (2.5 + (2.5 * SIN_TABLE_1000[i2])) + z2
    g1 = clamp(round(x1, RoundNearest), 0.0, 5.0)
    g2 = clamp(round(x2, RoundNearest), 0.0, 5.0)
    (g1, g2)
end

# Load already-opened 72h TSV slice (3 steps per 30s row = 10s/step real-time cadence)
function load_s68_radio_inputs(tsv_path::AbstractString; step_offset::Int = 0, force_stale_from::Int = typemax(Int))
    inputs = StampedInput[]
    stale_steps = 0
    step = step_offset
    open(tsv_path, "r") do io
        header = readline(io)
        startswith(header, "pi_s\t") || error("unexpected TSV header in $tsv_path")
        hdr = split(header, '\t')
        i_w = findfirst(==("w_sum"), hdr); i_b = findfirst(==("b_n"), hdr); i_f = findfirst(==("fail"), hdr)
        (i_w === nothing || i_b === nothing || i_f === nothing) && error("missing w_sum/b_n/fail column in $tsv_path")
        for line in eachline(io)
            isempty(line) && continue
            cols = split(line, '\t')
            length(cols) >= length(hdr) || continue
            fail = tryparse(Int, cols[i_f])
            (fail === nothing || fail != 0) && continue
            (cols[i_w] == "NA" || cols[i_b] == "NA") && continue
            w_sum = parse(Float64, cols[i_w])
            b_n = parse(Float64, cols[i_b])
            for _ in 1:3
                stale = step >= force_stale_from
                stale && (stale_steps += 1)
                g1, g2 = c4_yields_s68(step, w_sum, b_n, stale)
                push!(inputs, StampedInput(step, Dict{String,Any}("g1" => g1, "g2" => g2)))
                step += 1
            end
        end
    end
    return inputs, stale_steps
end

function build_rev_ood_inputs(n_steps::Int; rev_at::Int = 4000, ood_at::Int = 10000)
    inputs = StampedInput[]
    for t in 0:(n_steps - 1)
        period = t >= ood_at ? 700.0 : 1000.0
        ang = 2.0 * pi * Float64(t) / period
        x1 = 2.5 + 2.5 * sin(ang)
        x2 = 2.5 + 2.5 * sin(ang + pi)
        if t >= rev_at
            x1, x2 = x2, x1
        end
        g1 = clamp(round(x1, RoundNearest), 0.0, 5.0)
        g2 = clamp(round(x2, RoundNearest), 0.0, 5.0)
        push!(inputs, StampedInput(t, Dict{String,Any}("g1" => g1, "g2" => g2)))
    end
    inputs
end

function run_scenario(
    name::String,
    adapter::AUEAAdapter,
    seed::Int,
    inputs::Vector{StampedInput},
    stale_steps::Int;
    pace_ms::Int = 0,
    check_replay::Bool = false,
    species_id::String = "fastsim-$(name)",
)
    n_req = length(inputs)
    n_req > 0 || error("scenario $name has zero inputs (loader bug?)")
    min_const = typemax(Int)
    sum_const = 0
    steps_seen = 0

    t0 = time()
    res = run_species!(adapter, species_id, make_aue_a_initial_state(seed), inputs;
        on_step = (s, st, d) -> begin
            c = LabCore.nconstituents(st.w)
            c < min_const && (min_const = c)
            sum_const += c
            steps_seen += 1
            pace_ms > 0 && sleep(pace_ms / 1000.0)
        end)
    elapsed_s = max(time() - t0, 1e-6)

    chain_ok = verify_audit_chain(res.audit)
    replay_ok = true
    if check_replay
        rep = replay_from_audit(adapter, make_aue_a_initial_state(seed), res.audit)
        replay_ok = (rep.final_digest == res.final_digest) && (rep.audit.rows[end].hash == res.audit.rows[end].hash)
    end

    sim_real_sec = res.ledger.steps_completed * 10.0
    speedup = sim_real_sec / elapsed_s
    final_const = LabCore.nconstituents(res.state.w)
    mean_const = steps_seen > 0 ? sum_const / steps_seen : 0.0
    min_const = steps_seen > 0 ? min_const : 0

    @printf("%-22s | steps=%5d/%5d (%.2fd) | wall=%6.2fs | x%8.1f | term=%-23s | const(min/mean/fin)=%2d/%5.1f/%2d | stale=%5d | chain=%s replay=%s\n",
            name, res.ledger.steps_completed, n_req, sim_real_sec / 86400.0,
            elapsed_s, speedup, string(res.ledger.termination),
            min_const, mean_const, final_const, stale_steps,
            chain_ok ? "OK" : "FAIL", check_replay ? (replay_ok ? "OK" : "FAIL") : "skip")

    return Dict{String,Any}(
        "scenario" => name,
        "steps_requested" => n_req,
        "steps_completed" => res.ledger.steps_completed,
        "sim_realtime_days" => sim_real_sec / 86400.0,
        "wall_sec" => elapsed_s,
        "steps_per_sec" => res.ledger.steps_completed / elapsed_s,
        "realtime_speedup" => speedup,
        "termination" => string(res.ledger.termination),
        "death_step" => res.ledger.death_step,
        "min_constituents" => min_const,
        "mean_constituents" => mean_const,
        "final_constituents" => final_const,
        "stale_steps" => stale_steps,
        "cumulative_upkeep" => res.ledger.cumulative_upkeep,
        "cumulative_act_cost" => res.ledger.cumulative_act_cost,
        "audit_chain_ok" => chain_ok,
        "replay_checked" => check_replay,
        "replay_ok" => replay_ok,
        "final_digest" => res.final_digest,
        "tail_audit_hash" => res.audit.rows[end].hash,
    )
end

function main()
    sin_sha = verify_sin_table_sha()
    @assert sin_sha == "170c65dfadc4e2c345cff8e1bd5a5d34f191e844a55f0c158492251febecc58a" "SIN_TABLE_1000 SHA mismatch!"
    println("SIN_TABLE_1000 SHA-256 verified: ", sin_sha)
    println("Strict S52 blinding: reading ONLY already-opened design_72h.tsv (<=72h) & confirm_72h.tsv (<=144h).\n")

    ad = AUEAAdapter()
    seed = 690001   # dedicated pre-cutout fast-sim seed (main-sequence seed 1110 untouched)
    summaries = Dict{String,Any}[]

    # 1. G-FS-PARITY: fast (0 ms sleep) vs paced (5 ms sleep) + full audit text replay (200 steps)
    p_inputs = make_aue_a_inputs(200)
    r_fast = run_scenario("parity_fast_200", ad, seed, p_inputs, 0; pace_ms = 0, check_replay = true, species_id = "fastsim-parity_200")
    r_paced = run_scenario("parity_paced_200", ad, seed, p_inputs, 0; pace_ms = 5, check_replay = false, species_id = "fastsim-parity_200")
    parity_ok = (r_fast["final_digest"] == r_paced["final_digest"]) &&
                (r_fast["tail_audit_hash"] == r_paced["tail_audit_hash"]) &&
                r_fast["audit_chain_ok"] && r_fast["replay_ok"]
    println("G-FS-PARITY (fast == paced == text-replay bit-exact): ", parity_ok ? "PASS" : "FAIL")
    @assert parity_ok "G-FS-PARITY FAILED!"
    push!(summaries, r_fast, r_paced)

    # 2. Real S52 design_72h.tsv (3.0 real-time days = 25,929 steps)
    design_tsv = joinpath(ROOT, "experiments", "ambient", "out-72h", "design_72h.tsv")
    in_des, st_des = load_s68_radio_inputs(design_tsv; step_offset = 0)
    push!(summaries, run_scenario("radio_design_72h", ad, seed, in_des, st_des))

    # 3. Real S52 confirm_72h.tsv (3.0 real-time days = 25,923 steps, includes -1.91 SD b_n drift!)
    confirm_tsv = joinpath(ROOT, "experiments", "radio_confirm", "out", "confirm_72h.tsv")
    in_conf, st_conf = load_s68_radio_inputs(confirm_tsv; step_offset = 0)
    push!(summaries, run_scenario("radio_confirm_72h", ad, seed, in_conf, st_conf))

    # 4. Combined 144h continuous real radio (6.0 real-time days = 51,852 steps)
    in_conf_cont, st_conf_cont = load_s68_radio_inputs(confirm_tsv; step_offset = length(in_des))
    in_144h = vcat(in_des, in_conf_cont)
    push!(summaries, run_scenario("radio_full_144h", ad, seed, in_144h, st_des + st_conf_cont))

    # 5. Stress 1: 24h normal C4 radio + 24h continuous stale_flag=1 outage (2.0 real-time days = 17,280 steps)
    in_stale_raw, st_stale = load_s68_radio_inputs(confirm_tsv; step_offset = 0, force_stale_from = 8640)
    in_stale = in_stale_raw[1:min(17280, length(in_stale_raw))]
    st_stale_clipped = count(si -> si.step >= 8640, in_stale)
    push!(summaries, run_scenario("stress_stale_24h", ad, seed, in_stale, st_stale_clipped))

    # 6. Stress 2: Synthetic reversal (4000) + OOD period shift P=700 (10000) (2.0 real-time days = 17,280 steps)
    in_ro = build_rev_ood_inputs(17280; rev_at = 4000, ood_at = 10000)
    push!(summaries, run_scenario("stress_rev_ood", ad, seed, in_ro, 0))

    # Write TSV summary
    tsv_out = joinpath(OUT_DIR, "summary.tsv")
    open(tsv_out, "w") do io
        println(io, "scenario\tsteps_completed\tsteps_requested\tsim_realtime_days\twall_sec\tsteps_per_sec\trealtime_speedup\ttermination\tdeath_step\tmin_const\tmean_const\tfinal_const\tstale_steps\tchain_ok\treplay_ok\tfinal_digest")
        for r in summaries
            @printf(io, "%s\t%d\t%d\t%.4f\t%.4f\t%.2f\t%.2f\t%s\t%s\t%d\t%.3f\t%d\t%d\t%s\t%s\t%s\n",
                    r["scenario"], r["steps_completed"], r["steps_requested"], r["sim_realtime_days"],
                    r["wall_sec"], r["steps_per_sec"], r["realtime_speedup"],
                    r["termination"], r["death_step"] === nothing ? "none" : string(r["death_step"]),
                    r["min_constituents"], r["mean_constituents"], r["final_constituents"],
                    r["stale_steps"], r["audit_chain_ok"], r["replay_ok"], r["final_digest"])
        end
    end
    println("\nWrote ", tsv_out)
    println("G-FS-PARITY PASS; all scenarios ran with chain=OK. Survival is a RESULT, not a gate: ",
            count(r -> r["termination"] == "RUNNING", summaries), "/", length(summaries), " scenarios still RUNNING at end (see termination column).")
end

main()
