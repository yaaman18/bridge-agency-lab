# Predictions for the LLM sensory front-end trial, written 2026-10-29 before any LLM call.
# Placement: input path only (the LLM turns a text observation into the two patch-sensor signals).
# Frozen translation rule: PROMPT.md. Rendering of observations: llm_sensor.js (WORDS a and b).
L1  Closed loop, haiku, 40 steps: the LLM's sensor report agrees with the rule at >= 38/40 steps.
L2  Closed loop: if every report agrees, the trajectory is identical to the rule-sensor run (no other path
    by which the LLM can affect the system); the agent keeps form at every step either way.
L3  Open loop, 30 sampled states: haiku on wording a vs wording b (same counts, different words and order)
    gives the same report on >= 28/30 states; haiku vs sonnet on wording a: >= 28/30.
L4  Mean latency per call between 3 and 15 seconds.
