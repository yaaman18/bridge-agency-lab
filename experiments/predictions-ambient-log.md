# S52 predictions (r2 after the S-R; frozen before the logger is written or run; 2026-11-14). Spec: ../discussion/specs/S52-ambient-log.md.

One Raspberry Pi 5, indoors, moved by the user; a reading every 30 s. The design period = the first 72 hours of elapsed
running time (sum of uptime spans between the first and last reading of each boot; time while off is not counted).
Known before freezing (tool probe only, 4 scans at one place at about 21:00): 3-4 Wi-Fi BSS, strengths 72-97, 4 Bluetooth devices, 51-54 C.
Rows marked failed are excluded from PS1-PS4. Times of day use the Pi's clock as corrected under spec section 2; rows of a
boot whose clock could not be corrected are excluded from PS2 and PS3. A day = 00:00-24:00 JST of that clock.
- PS1 (it varies): over the design period w_sum takes at least 5 distinct values and b_n at least 3 distinct values. Judged
  by the count of distinct values only.
- PS2 (a daily rhythm in Bluetooth, not in Wi-Fi counts): a day is usable if both windows 01:00-05:00 and 19:00-23:00 of
  that day have at least 120 valid rows each. Bluetooth: median b_n in 01:00-05:00 is strictly lower than in 19:00-23:00 on
  at least 2 usable days. Wi-Fi: |median w_n (01-05) - median w_n (19-23)| <= 1 on at least 2 usable days. With fewer than
  2 usable days: not testable. The two halves are judged separately.
- PS3 (moving matters more than time, Wi-Fi): a move = a time the user recorded (to the minute). The stay before a move =
  from the previous move (or the first row) to 5 minutes before this move. For each move with at least 30 valid rows in
  the 30 minutes ending 5 minutes before it and 30 valid rows in the 30 minutes starting 5 minutes after it, and a stay
  before it of at least 2 hours: |median w_sum after - median w_sum before| > interquartile range of w_sum in the stay
  before. Holds if this is so for at least half of such moves, with at least 2 such moves; otherwise not testable.
  Windows of different moves may not overlap; a move within 70 minutes of the previous one is dropped.
- PS4 (temperature is slow and separate): the Pearson lag-1 autocorrelation of t_mc between consecutive rows within one
  boot (pairs across a boot boundary or more than 120 s apart are dropped) is above 0.9; the Pearson correlation between
  t_mc and w_sum over the valid rows of the design period is between -0.3 and 0.3. Judged separately.
- PS5 (the reading is reliable): failed rows / all rows written in the design period < 2 %, and no gap between consecutive
  rows within one boot exceeds 120 s.
- Each prediction (and each half) is judged alone; misses are reported as misses; "not testable" is reported as such. No
  pooled claim. Not claimed: anything about another place or season, about the individual, about a conversion rule, or
  about how far the author's own devices can move these quantities.
- Smoke (frozen here too): 10 minutes of readings to test the script (gate A1); not used for any claim.
