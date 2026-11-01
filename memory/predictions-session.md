# Predictions for stage 30, the session with the person (app v3.1 = turn.js rev. 2 + life_turn.js with the session log),
# written 2026-10-31 before the session. Analysis: analyze_session.js on the saved being/state (frozen with this file).
# Protocol (speed 5 steps/s, about 1500 steps = 5 min per segment, page kept visible):
#   segment 1  answer every call, including babble, varying the gestures (1-4);
#   segment 2  answer only calls marked "間を置いた呼びかけ" (made while no call was pending), not "重ねた呼びかけ";
#   segment 3  blind mode (live / replay alternate every 300 steps, hidden), interact freely.
# Basis: the scripted partners of stages 20-25 (RESP ~ segment 1, SCAF ~ segments 1->2, REPLAY ~ the replay blocks).
# This is one person and one circuit (n = 1, the circuit migrated from the 13,581-step being): the predictions are about
# this session only and a miss may be noise.
H1  Babble ends in segment 1: calls per 100 counted steps in its last 300 steps <= 50 (babble is ~100).
H2  Waiting is acquired in segment 2: share of calls made while waiting in its last 750 steps <= 0.3.
H3  Segment 2 makes the difference: that share is lower in the last 750 steps of segment 2 than in the last 750 of segment 1.
H4  The partner is sedimented: at the end of segment 2, r9 -> m3 or r11 -> m3 has sediment >= 1.
H5  The circuit does not tell live from replay (scripted finding for a reactive caller): in segment 3, the share of calls
    made while waiting differs by < 0.1 and calls per 100 steps by < 20% between live and replay blocks.
    If they do differ, the person's way of answering differs from the scripted partners in a way that matters.
H6  No harm: the circuit keeps its form in >= 0.95 of the 100-step summaries of the whole session.
