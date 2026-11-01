# Predictions for stage 24, upbringing (test_raise.js with turn.js rules), written 2026-10-30 after stage 23
# (results-turn.json: 4/8; the gesture became a cue in 4/5 seeds, waiting was not learned: late share of calls made
# while waiting 0.76-0.84, r11 never sedimented, no difference without proprioception) and before any run of test_raise.js.
# Inference behind U3-U6: with the RESP partner calling over a pending call is answered as well as calling after a
# pause, so the world gives no reason to wait; a TURN partner (answers only calls made in a pause) does.
U1  Upbringing with a partner does no harm: in RESP-RAISED and TURN-RAISED the share of patch actions answered is within
    0.05 of BASELINE and form >= 0.99, in every phase and seed.
U2  The partner present in childhood is learned as a cue: r9 -> m3 has sediment >= 1 at the end of the curriculum
    (step 800) in >= 4/5 seeds with RESP-RAISED and with TURN-RAISED.
U3  Upbringing alone does not teach waiting: RESP-RAISED keeps a late (last 1000 steps of A) share of calls made while
    waiting > 0.5 in >= 4/5 seeds.
U4  A partner who answers pauses teaches waiting from birth: TURN-RAISED has that late share <= 0.2 in >= 4/5 seeds,
    and r11 -> m3 sediment >= 1 at the end of A in >= 3/5 seeds.
U5  With the orienting response it can be learned late as well: TURN-ADULT has that late share <= 0.2 in >= 3/5 seeds.
U6  TURN-RAISED keeps answering partners after a separation: in phase C the first call strictly after the first gesture
    comes within 3 steps in >= 4/5 seeds.
