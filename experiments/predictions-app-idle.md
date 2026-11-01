# Predictions for putting the idle-first choice into the app (item 73; frozen 2026-11-01 before the checks)

User 2026-11-01: "推奨どおりでいい、アプリに入れて" (recommendation 1 of item 72: put idle_first into the Rust engine, check
every scenario bit for bit, rebuild the page; keep the being's confidences and sediment, change only the rule).

Change: the app's rule is named "bin3+idle" (core/life.jl RULES, RULE_NAME; rust/being-core life.rs RULE, rule_spec) =
contrast bin3 with idle_first. Migration of a record whose rule was "bin3": ruleHist gains [age, "bin3+idle"], and the
contrast statistics (cOn, cOff) and last acts (lastM) are kept (same contrast rule); other prior rules start them empty as
before. The JavaScript copies stay v3.5 (rule "bin3"), so Julia keeps "bin3" for them (makelife(...; rule = "bin3")). The
earlier trial scripts (audit/dc_run.jl, experiments/diag/diag_choice.jl) are pinned to "bin3".

- AP1: sh core/check/run.sh: JavaScript 42 identical; Rust identical on all its scenarios (the old 19 circuit ones, 4 new
  circuit-*-idle, 6 life-*-idle with the app rule); wasm 1 identical; app/index.html embeds the module; body_org stage 42
  reproduced.
- AP2: experiments/eval_idle.jl, rerun after the refactoring (makelife(...; rule) in place of live!'s rule_opts), prints
  exactly experiments/eval_idle.out.
- AP3: audit/dc_run.jl pinned to "bin3" prints the same verdicts and numbers as before (DQ7-DQ12 as in item 69).
- AP4: makelife of state-v528 with the app rule: q, sg, cOn, cOff, lastM unchanged; rule "bin3+idle"; ruleHist ends
  with [137919, "bin3+idle"]; Julia and Rust give the same record after the migration and after 5000 steps (audit C).
- AP5: sh audit/run.sh audit/in/state-v528.json with the app rule: N, M, P, C, S pass; DC rate above the v528 report of
  item 69/70 (69.7%); M4b holds.
