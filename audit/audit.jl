# Automatic audit of the app's being against bridge-protocol (2026-10-31, user: connect bridge-protocol and the app and
# audit automatically, before deciding D1-D6). Read-only: the being is read from a saved record (the app's db,
# fetched read-only into audit/in/), and nothing is written back anywhere.
#
# Usage: julia --project=. audit/audit.jl audit/in/state-v<version>.json
# Writes audit/reports/<date>-v<version>.{json,md}.
#
# Audits that do not depend on D1-D6 (formal/README.md):
#   N  noninterference (MetaSelection.SigmaPure / DiversityAuditPure): the audit leaves the record bit-identical, and the
#      app's read path (snapshot, texts, panels; Rust) leaves the being's run identical.
#   M  M4a (no external set point): the record holds only the known fields of the being, the session log only the
#      known event kinds; the Lean statement m4a_circuit (formal/LabCircuit.lean) proves it for the circuit's trace type.
#   P  phenomenal_claim stays not_certified (the report carries it and no audit can change it).
#   C  copies: the saved being lived 5000 steps by the canonical Julia rules and by the app's Rust engine, compared.
#   A  AGENCY-001 measured with the protocol's criteria (audit/agency_adapter.jl) under each adapter choice (D6).
# Pending, shown as such: DC of the being (needs D1-D6 and the proofs of formal/LabCircuit.lean), M4b (needs D5).
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON, Dates
include(joinpath(@__DIR__, "agency_adapter.jl"))
using .LabAgency

const LAB = normpath(joinpath(@__DIR__, ".."))
parsej(s) = JSON.parse(s; dicttype = Dict{String,Any})
canon(x) = JSON.json(jsonable(x))
function deq(a, b)   # deep equality of parsed JSON (numbers by value)
    a isa AbstractDict && b isa AbstractDict && return Set(keys(a)) == Set(keys(b)) && all(k -> deq(a[k], b[k]), keys(a))
    a isa AbstractVector && b isa AbstractVector && return length(a) == length(b) && all(i -> deq(a[i], b[i]), eachindex(a))
    a isa Number && b isa Number && return a == b
    return a == b
end

input = isempty(ARGS) ? error("usage: julia --project=. audit/audit.jl audit/in/state-v<version>.json") : ARGS[1]
version = something(match(r"v(\d+)", basename(input)), (captures = ["?"],)).captures[1]
raw = read(input, String)
record = parsej(raw)
before = canon(record)
results = Dict{String,Any}()

# ---- M: M4a ----
const KNOWN = Set(["v", "age", "wt", "R", "active", "q", "sg", "h", "off", "prev", "rng", "reversals", "stasisUntil", "hist",
    "unansWindow", "callWindow", "lastAct", "open", "pend", "fresh", "partner", "born", "rule", "ruleHist", "cOn", "cOff",
    "lastM", "session", "speed", "savedAt", "migratedAt", "migratedFrom", "firstMigratedAt"])
const PARTNER = Set(["mode", "rec", "rp", "brng", "bcond", "bnext", "stats", "ignored"])
const EVENTS = Set(["b", "u", "g", "c", "a", "s"])
const SUSPECT = r"target|goal|set.?point|reward|score|rating|objective|utility"i
unknown = sort([k for k in keys(record) if !(k in KNOWN)])
unknownP = sort([k for k in keys(get(record, "partner", Dict())) if !(k in PARTNER)])
evkinds = sort(unique(String(e[1]) for e in get(get(record, "session", Dict()), "ev", Any[])))
badev = [k for k in evkinds if !(k in EVENTS)]
suspect = sort(unique(vcat([k for k in keys(record) if occursin(SUSPECT, k)], [k for k in keys(get(record, "partner", Dict())) if occursin(SUSPECT, k)])))
results["M_m4a"] = Dict("pass" => isempty(unknown) && isempty(unknownP) && isempty(badev) && isempty(suspect),
    "unknown_fields" => unknown, "unknown_partner_fields" => unknownP, "event_kinds" => evkinds, "unknown_event_kinds" => badev,
    "suspect_fields" => suspect, "lean" => "m4a_circuit (formal/LabCircuit.lean): proved; the circuit's trace has no external set-point channel (type Empty)")

# ---- C: copies (Julia canonical vs the app's Rust engine) ----
const STEPS_C = 5000
tmp = mktempdir()
infile = joinpath(tmp, "in.json"); write(infile, raw)
l = makelife(deepcopy(record)); live!(l, STEPS_C)
jl = parsej(canon(l.L))
rsout = joinpath(tmp, "rs.json")
run(`$(joinpath(LAB, "rust", "target", "release", "being-tools")) run-state $infile $STEPS_C $rsout`)
rs = parsej(read(rsout, String))
results["C_copies"] = Dict("pass" => deq(jl, rs), "steps" => STEPS_C, "age_after" => jl["age"],
    "what" => "the saved being lived $(STEPS_C) steps (no gestures) by core/life.jl (Julia, canonical) and rust/being-core (the app)")

# ---- A: AGENCY-001 under each adapter choice ----
agency = Dict{String,Any}()
for strength in (:q, :qsg), death in (:none, :agency001)
    t0 = time()
    e = LabAgency.evaluate_being(record; strength, death)
    r = e.result
    agency["strength=$(strength), death=$(death)"] = Dict(
        "agency_L2" => r.agency, "self_producing_L3" => r.self_producing, "self_repairing_L3R" => r.self_repairing,
        "core" => r.core, "core_enables_action" => r.core_enables_action, "alive_somewhere" => r.alive_somewhere,
        "differentiated" => r.differentiated, "value_needed" => r.value_needed, "value_tracking" => r.value_tracking,
        "value_tracking_measured" => r.value_tracking_measured, "choices" => r.choices, "survival" => r.survival,
        "survival_without_tracking" => r.survival_without_tracking, "seconds" => round(time() - t0; digits = 2),
        "templates_sha256" => e.setup_sha256)
end
results["A_agency001"] = Dict("criteria" => "~/bridge-protocol/tools/AgencySubstrate (unchanged; typed criteria re-evaluated for the lab's substrate: $(LabAgency.INSTALLED))",
    "adapter" => "audit/agency_adapter.jl: A1 sensors r1-r11, motors m1->1, m2->2; A2 strength; A3 death; A4 start = the saved being, partner absent",
    "runs" => agency)

# ---- S: the adapter does not change the protocol's own judgments ----
pt(args...) = read(`$(Base.julia_cmd()) --project=$(LAB) $(joinpath(LAB, "audit", "protocol_templates.jl")) $(args...)`, String)
plain = pt(); with = pt("with-adapter")
results["S_adapter_selfcheck"] = Dict("pass" => plain == with && !isempty(plain), "templates" => count(==('\n'), plain),
    "what" => "AgencySubstrate's evaluation of its frozen templates is identical with and without audit/agency_adapter.jl loaded")

# ---- N: noninterference ----
after = canon(record)
pur = parsej(read(`$(joinpath(LAB, "rust", "target", "release", "being-tools")) purity $infile 3000`, String))
results["N_noninterference"] = Dict("pass" => before == after && pur["identical"] == true,
    "record_unchanged_by_audit" => before == after, "app_read_path_pure" => pur,
    "what" => "the audit's input is bit-identical after every audit (DiversityAuditPure); the being lived with the page's snapshot, texts and panels at every step equals the being lived without them (SigmaPure)")

# ---- DC and M4b (formal/LabCircuit.lean, all proved; D1-D5 decided 2026-10-31, D4's alpha state-dependent since item 69; core/dc.jl) ----
const STEPS_DC = 2000
let l = makelife(deepcopy(record)), recs = LabCore.DCStep[]
    live!(l, STEPS_DC; on_step = (o, st, cond, y, ph) -> push!(recs, dc_record(l.b, o, st; partner_live = false, y = y, phase = ph)))
    vs = [(check_dc(l.b, dc_window(l.b, @view recs[x-DC_L+1:x])), !isempty(recs[x].acted)) for x in DC_L:length(recs)]
    rate(f) = count(f, vs) / length(vs)
    living = count(v -> v[1].dc, vs)
    results["DC"] = Dict("occurrences" => length(vs), "window" => DC_L, "steps" => STEPS_DC,
        "self" => rate(v -> v[1].self), "smc" => rate(v -> v[1].smc), "act" => rate(v -> v[1].act), "bound" => rate(v -> v[1].bound),
        "dc" => rate(v -> v[1].dc), "living" => living,
        "what" => "Window.checkDC of formal/LabCircuit.lean (dc_of_check: true gives an ERIEC.DC certificate) at each step of the saved being lived $(STEPS_DC) steps, partner absent; alpha state-dependent (D4, item 69: m1/m2 only in the world phase while their patch yields)")
    results["M4b"] = Dict("check" => all(v -> !v[1].dc || v[2], vs), "living_occurrences" => living,
        "vacuous" => living == 0,
        "what" => "checkM4b of formal/LabCircuit.lean (m4b_of_check): every living occurrence acts; vacuous when no occurrence is living")
end

# ---- P and pending ----
results["P_phenomenal"] = Dict("phenomenal_claim" => "not_certified", "pass" => true,
    "what" => "§13-5: no audit in this report certifies or upgrades a phenomenal claim")
results["pending"] = Dict(
    "L2_body_L3_constituents" => "out of scope for the app's being (no death, no body; D1). Judged on body_org by the D6 lab variant (experiments/variant_horizon.jl, results-horizon.json, item 70): at the frozen 60 steps not measurable; at 294/392/588 L2 false (not value-differentiated), L3 on the constituents true",
    "decisions" => Dict("D1-D5" => "decided 2026-10-31 as recommended (formal/README.md); D4 alpha state-dependent 2026-11-01 (item 69)", "D6" => "decided 2026-11-01 (item 70): the frozen 60 steps kept and shown as not measurable; lab variant with horizons 392 (= 2 x 196), 294, 588"))

report = Dict{String,Any}("audit" => "bridge-agency-lab app being", "phenomenal_claim" => "not_certified",
    "input" => relpath(input, LAB), "db_version" => version, "age" => record["age"], "rule" => get(record, "rule", nothing),
    "date" => string(Dates.now()), "results" => results)
any(v -> v == "certified", values(report)) && error("a report cannot certify a phenomenal claim")
outdir = joinpath(LAB, "audit", "reports"); mkpath(outdir)
stem = joinpath(outdir, Dates.format(Dates.now(), "yyyy-mm-ddTHHMM") * "-v$(version)")
write(stem * ".json", JSON.json(jsonable(report), 2))

# ---- the readable report ----
ok(b) = b ? "合格" : "不合格"
io = IOBuffer()
println(io, "# 自動監査の報告（db 版 $(version)、年齢 $(record["age"])）\n")
println(io, "日時 $(report["date"])。入力 `$(report["input"])`（読むだけ。どこにも書き戻していない）。phenomenal_claim = not_certified。\n")
println(io, "| 監査 | 根拠（bridge-protocol） | 結果 |\n|---|---|---|")
println(io, "| N 書き戻しがない | MetaSelection.SigmaPure・DiversityAuditPure | $(ok(results["N_noninterference"]["pass"]))（監査の前後で記録が同一 $(results["N_noninterference"]["record_unchanged_by_audit"])、アプリの読み取り経路 3000 歩で同一 $(pur["identical"])） |")
m = results["M_m4a"]
println(io, "| M 外部の目標値がない（M4a） | InternalTrace.M4a、Lean の m4a_circuit（証明済み） | $(ok(m["pass"]))（未知の欄 $(isempty(m["unknown_fields"]) ? "なし" : join(m["unknown_fields"], ", "))、疑わしい欄 $(isempty(m["suspect_fields"]) ? "なし" : join(m["suspect_fields"], ", "))、記録の出来事の種類 $(join(m["event_kinds"], ","))） |")
println(io, "| P 灯りを主張しない | §13-5、CertifiedUnit | 合格（固定） |")
println(io, "| C 写しの一致 | ラボの規律 | $(ok(results["C_copies"]["pass"]))（Julia の正本とアプリの Rust で $(STEPS_C) 歩、年齢 $(results["C_copies"]["age_after"]) まで全値一致） |")
println(io, "| S アダプタが protocol の判定を変えない | AgencySubstrate の凍結テンプレート | $(ok(results["S_adapter_selfcheck"]["pass"]))（$(results["S_adapter_selfcheck"]["templates"]) テンプレートの判定がアダプタの有無で同一） |")
println(io, "\n## A AGENCY-001（protocol の判定をそのまま、アダプタの選択ごと）\n")
println(io, "判定は `~/bridge-protocol/tools/AgencySubstrate` の criteria.jl（変更なし）、設定は fixtures/templates.toml（SHA-256 $(first(values(agency))["templates_sha256"][1:12])…）。アダプタの選択 A2・A3 は参考。D1 により、アプリの存在（死も身体もない）は L2・L3 の対象外で、この表は判定ではない（X2・X3）。\n")
println(io, "| 強さ A2 | 死 A3 | 主体性 L2 | 自己産出 L3 | 自己修復 L3R | 核 | 核が行為を通す | どこかで生存 | 価値で行為が違う | 価値の追跡が必要 |\n|---|---|---|---|---|---|---|---|---|---|")
for strength in (:q, :qsg), death in (:none, :agency001)
    r = agency["strength=$(strength), death=$(death)"]
    println(io, "| $(strength) | $(death) | $(r["agency_L2"]) | $(r["self_producing_L3"]) | $(r["self_repairing_L3R"]) | $(join(r["core"], ",")) | $(r["core_enables_action"]) | $(r["alive_somewhere"]) | $(r["differentiated"]) | $(r["value_needed"]) |")
end
dcr = results["DC"]; mb = results["M4b"]
println(io, "\n## DC と M4b（formal/LabCircuit.lean はすべて証明済み。D1〜D5 は推奨どおり決定、D4 の α は項番69 から状態に依存）\n")
println(io, "保存された存在を $(STEPS_DC) 歩（相手なし）走らせ、各歩の窓（$(DC_L) 歩）で Window.checkDC を判定した（$(dcr["occurrences"]) 出来事）。α は状態に依存する（m1・m2 は世界の相で自分の区画に収量があるときだけ届く、Lean の labGate）。\n")
println(io, "| hSelf | hSMC | hAct | hBound | DC（4つとも） |\n|---|---|---|---|---|")
pc(x) = string(round(100x; digits = 1), "%")
println(io, "| $(pc(dcr["self"])) | $(pc(dcr["smc"])) | $(pc(dcr["act"])) | $(pc(dcr["bound"])) | $(pc(dcr["dc"])) |\n")
println(io, "M4b の判定（生きている出来事はすべて行為する、m4b_of_check）: $(mb["check"] ? "成立" : "不成立")$(mb["vacuous"] ? "（生きている出来事が無いので空虚に成立）" : "（生きている出来事 $(mb["living_occurrences"])）")。\n")
println(io, "## アプリの存在では対象外のもの\n")
println(io, "- L2・L3 はアプリの存在では対象外（D1）。body_org での判定は D6 のラボ変種（`experiments/variant_horizon.jl`、項番70）: 凍結の 60 歩では測れない。294・392・588 歩では L2 偽（価値で行為が違わない）、構成体の L3 真。")
write(stem * ".md", String(take!(io)))
println(read(stem * ".md", String))
println("written: ", relpath(stem, LAB), ".{json,md}")
