# S49 helper of experiments/onelife_rust_check.sh (discussion/specs/S49-rust-onelife.md): the run files that onelife-run
# must refuse (PR5, Q5), and the report. Run from the lab root: julia --project=. experiments/onelife_rust_check.jl ...
#   flips RUN BASE SEED WORK        200 one-bit flips of the run file BASE (40 in the header, 120 in the payload, 40 in the
#                                   trailing SHA-256; positions from Mulberry(SEED)); each is given to RUN with one drive
#   malformed RUN LIVE DEAD WORK    the cases of Q5 / PR5 (forged files have their trailing SHA-256 recomputed, so each
#                                   is refused by its own check), the out-of-range drives and lines, and two controls
#   report TSV JSON                 the results (name, value) as one JSON object
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, SHA, JSON

# Runs RUN on the run file F with the standard input `input`; returns (exit code or -signal, F's bytes after).
function runon(RUN, f, input)
    p = run(pipeline(ignorestatus(`$RUN $f`); stdin = IOBuffer(input), stdout = devnull, stderr = devnull))
    code = p.termsignal != 0 ? -p.termsignal : p.exitcode
    return code, isfile(f) ? read(f) : nothing
end
reseal(b) = (L = length(b) - 64; vcat(b[1:32+L], sha256(b[1:32+L])))
u64le(x) = reinterpret(UInt8, [htol(UInt64(x))])
u32le(x) = reinterpret(UInt8, [htol(UInt32(x))])

function flips(RUN, base, seed, work)
    b0 = read(base); L = length(b0) - 64; r = Mulberry(seed)
    pick(lo, hi, k) = (s = Set{Int}(); while length(s) < k; push!(s, lo + floor(Int, r() * (hi - lo))); end; sort!(collect(s)))
    pos = vcat(pick(0, 256, 40), pick(256, 8 * (32 + L), 120), pick(8 * (32 + L), 8 * (64 + L), 40))
    refused = 0; unchanged = 0; codes = Set{Int}()
    for p in pos
        b = copy(b0); b[p÷8+1] ⊻= UInt8(1) << (p % 8)
        write(work, b)
        code, after = runon(RUN, work, "3 2\n")
        push!(codes, code); refused += code > 0; unchanged += after == b
    end
    rm(work)
    println(JSON.json(Dict("flips" => length(pos), "refused" => refused, "unchanged" => unchanged, "exit_codes" => sort!(collect(codes)),
                           "header" => 40, "payload" => 120, "tail" => 40)))
end

function malformed(RUN, live, dead, work)
    b0 = read(live); d0 = read(dead); L = length(b0) - 64
    n0 = ltoh(reinterpret(UInt64, b0[17:24])[1])
    pay = b0[33:32+L]
    # the payload with one body byte changed and its own check value recomputed, but another law identity
    otherlaw = copy(pay); otherlaw[9:40] = sha256("L3"); otherlaw[end-31:end] = sha256(otherlaw[1:end-32])
    badinner = copy(pay); badinner[100] ⊻= 0x01
    cases = [
        # name, bytes, input, expected exit (0 = accepted), whether the file must stay as it was
        ("truncated_in_n", b0[1:20], "3 2\n", 4, true),
        ("truncated_in_L", b0[1:28], "3 2\n", 4, true),
        ("truncated_payload", b0[1:end-100], "3 2\n", 4, true),
        ("trailing_byte", vcat(b0, UInt8[0]), "3 2\n", 4, true),
        ("unknown_version", reseal(vcat(b0[1:8], u32le(2), b0[13:end])), "3 2\n", 4, true),
        ("reserved_nonzero", reseal(vcat(b0[1:12], UInt8[0, 1, 0, 0], b0[17:end])), "3 2\n", 4, true),
        ("L_too_large", reseal(vcat(b0[1:24], u64le(16_777_217), b0[33:end])), "3 2\n", 4, true),
        ("L_zero", reseal(vcat(b0[1:24], u64le(0), b0[33:end])), "3 2\n", 4, true),
        ("L_wrong", reseal(vcat(b0[1:24], u64le(L - 8), b0[33:end])), "3 2\n", 4, true),
        ("bad_magic", reseal(vcat(b"ONELIFE2", b0[9:end])), "3 2\n", 4, true),
        ("payload_check_value", reseal(vcat(b0[1:32], badinner, b0[end-31:end])), "3 2\n", 4, true),
        ("payload_other_law", reseal(vcat(b0[1:32], otherlaw, b0[end-31:end])), "3 2\n", 4, true),
        ("n_max", reseal(vcat(b0[1:16], u64le(typemax(UInt64)), b0[25:end])), "3 2\n", 7, true),
        ("drive_6_0_live", b0, "6 0\n", 8, true),
        ("drive_minus1_live", b0, "-1 3\n", 8, true),
        ("drive_huge_live", b0, "99999999999999999999 0\n", 8, true),
        ("line_not_integers", b0, "abc\n", 6, true),
        ("line_one_number", b0, "1\n", 6, true),
        ("line_three_numbers", b0, "1 2 3\n", 6, true),
        ("line_empty", b0, "\n", 6, true),
        ("line_float", b0, "1.0 2\n", 6, true),
        ("drive_after_valid_then_bad", b0, "3 2\n6 0\n", 8, false),
        ("control_valid_drive", b0, "3 2\n", 0, false),
        ("control_no_input", b0, "", 0, true),
        ("control_dead_out_of_range_drive", d0, "9 9\n", 0, false),
    ]
    rows = Any[]; allok = true
    for (name, b, inp, want, same) in cases
        write(work, b)
        code, after = runon(RUN, work, inp)
        ok = code == want && (same ? after == b : after != b)
        if name == "drive_after_valid_then_bad" || name == "control_valid_drive"
            # one drive consumed and saved: n + 1, and the file is a valid run file
            ok = ok && after !== nothing && ltoh(reinterpret(UInt64, after[17:24])[1]) == n0 + 1
        elseif name == "control_dead_out_of_range_drive"
            nd = ltoh(reinterpret(UInt64, d0[17:24])[1])
            ok = ok && ltoh(reinterpret(UInt64, after[17:24])[1]) == nd + 1 && after[25:end-32] == d0[25:end-32]
        end
        allok &= ok
        push!(rows, Dict("case" => name, "exit" => code, "expected" => want, "ok" => ok))
    end
    rm(work)
    # a missing run file: an error, and no file is made
    missing = work * ".missing"
    code, after = runon(RUN, missing, "3 2\n")
    okm = code == 3 && after === nothing
    push!(rows, Dict("case" => "missing_file", "exit" => code, "expected" => 3, "ok" => okm)); allok &= okm
    println(JSON.json(Dict("cases" => rows, "all_ok" => allok)))
end

function report(tsv, out)
    d = Dict{String,Any}()
    for l in eachline(tsv)
        k, v = split(l, '\t'; limit = 2)
        d[k] = try JSON.parse(v) catch; v end
    end
    open(out, "w") do io; JSON.print(io, d, 1); end
end

if ARGS[1] == "flips"
    flips(ARGS[2], ARGS[3], parse(Int, ARGS[4]), ARGS[5])
elseif ARGS[1] == "malformed"
    malformed(ARGS[2], ARGS[3], ARGS[4], ARGS[5])
elseif ARGS[1] == "report"
    report(ARGS[2], ARGS[3])
else
    error("usage: flips | malformed | report")
end
