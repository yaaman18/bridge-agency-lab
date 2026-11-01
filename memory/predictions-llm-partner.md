# Predictions for stage 31 A: an LLM partner that does not know the rules (llm_partner.js, PROMPT_partner.md,
# model haiku via `claude -p`, seeds 1 and 2), written 2026-10-31 before any LLM run. The circuit and world are the app's
# (turn.js rev. 2 + life_turn.js v3.2 auto session: segments 1/2/3 of 1500 steps, 3 blind), newborn after 800 steps of
# nursery/school without a partner. The LLM sees once per 5 steps what a person sees and answers one digit.
# NOTE (deviation, reported): the matched scripted partner (llm_partner.js script, seeds 1-2) was run BEFORE this file was
# written (results-llm-script-seed*-reference.json); it is therefore a reference, not a tested prediction. Its values:
#   seed 1: seg1 last750 waiting 0.355, seg2 last750 waiting 0.268, end seg2 r9 0/2 r11 0/4; seg3 live 0.333 vs replay 0.611
#   seed 2: seg1 0.705, seg2 0.076, end seg2 r9 3/4 r11 3/4; seg3 live 0.604 vs replay 0.637
# Analysis: analyze_session2.js (merged marks, steps per condition from block events), frozen with this file.
L1  Babble ends in segment 1: calls per 100 steps in its last 300 steps <= 50 (both seeds).
L2  Waiting in segment 2: share of calls made while waiting in its last 750 steps <= 0.3 (both seeds).
L3  Segment 2 makes the difference: that share is lower in segment 2's last 750 steps than in segment 1's (both seeds).
L4  The partner is sedimented: at the end of segment 2, r9 -> m3 or r11 -> m3 has sediment >= 1 (both seeds).
L5  The LLM partner acts like the scripted one where it matters: segment 2's last-750 waiting share within 0.15 of the
    scripted reference of the same seed (both seeds).
L6  As with the scripted reference, replay blocks of segment 3 have a share of calls made while waiting at least as high
    as live blocks (both seeds).
L7  No harm and a usable partner: form >= 0.95 of the 100-step summaries; LLM answers unparsable in <= 5% of decisions.
