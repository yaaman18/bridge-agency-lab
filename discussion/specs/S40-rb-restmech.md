# S40 区画の交換の後の休みの仕組み（RB :swap、S39 の続き）

- 状態: r1（2026-11-09、ユーザー「休みの仕組みもコーデックスと議論しながら進めて」。codex V1 1〜10 を反映。claude-lab が書き、codex-lab が I-R）。
- 被説明項: 同じ時点 t（更新 t の後、t＋1 の入力の前）の状態から、N と Z（予定表とたまりの交換、S39）の分岐で、t＋1〜t＋15 の m0 の勝つ歩の数が違うこと。分母は 15 歩すべて（死の後の歩は「dead」として数え、m0 に数えない）。
- 対象: RB :swap、**種子 471〜480（未使用）**、予定表 4、H 392、分岐点 t∈32:32:392（本走で生存）。
- 確認した事実: 読む収量 y はたまりから作る（`variant_horizon.jl:141`）。Z の後は y が即座に入れ替わり、新しく高い区画には元の高い区画のたまりが来る。選び方は `core/circuit.jl:128–170`（conf は駆動した q≥1 の辺の重みの和、habit は sg≥1、key＝conf·10⁶＋habit·10³＋total、idle は now−lastM＞FORGET、同点は old、さらに patch の番号）。

## 1. 介入と記録
- 分岐 N・Z・ZM。ZM＝Z の世界（予定表の入れ替え、たまりの交換）に、t の回路の状態を μ で鏡写しにしたもの。μ: r1↔r2、r3↔r4、r7↔r8、c1↔c2、m1↔m2、r5・r6・m0・rb は固定。辺の欄（q・sg・h・cOn・cOff・lastC）は新 (μa,μc)＝旧 (a,c)、単位の欄（active・off・prev・lastM）と AS.State の active も μ で写す。乱数・体・時計・fresh はそのまま。
- 各更新の決定の記録: y、old（更新の前に点いていた運動）、駆動した辺から作った conf・habit・total・key、core_gate の後の候補、idle の集合、pref・win、行為、決め方（候補なし／一つ／key／idle の後の key／key の同点を old で／key と old の同点を patch の番号で）。自己照合: 作った候補が回路の記録（choice.cand）と一致し、行為が候補に入る。
- 関門: μ が配線を保つ（単位と辺の対合、kind・θ・patch〈1↔2〉・特徴・重み・q0 の対応、perm は恒等）。鏡を二度当てると状態が戻る（本走の 8 歩ごとの状態）。一歩の同変性: 同じ状態で mirror(step(X)) と step(mirror(X))（鏡の予定表）が状態の全体（AS.State の active・strength・resource・t・dead と、側の欄すべて: 回路・世界・乱数・たまり・Q0、構造の再帰比較）で一致するか。μ と可換でない決め方は「key と old の後に m1 と m2 が両方残り patch の番号で決めた」場合だけ（m1 か m2 と m0 の同点は 1・2＜4 で可換）で、その歩は記録して分ける。比較の関数は片側の一欄だけを変えた負の対照（回路の q・lastM、乱数、たまり、世界、t、strength、active）で検出を確かめる（codex I-R 2）。

## 2. 予測（凍結、`experiments/predictions-rb-restmech.md`）
- RM1〜RM5。予測は煙試験（種子 1）を見た後に書いた。規則だけからの独立な予測ではない。

## 3. 読みの限定（codex V1）
- ZM が N の鏡写しに一致すれば、Z の後の休みの差は「回路の状態と環境の向きの対応」に帰す証拠になる。ただし来歴の原因（使わない運動の辺の減衰か、上流の不活性か）は t の状態からは確定しない。H-disuse（新しく高い区画の運動の conf が m0 を下回る、または候補にならない）と H-tie（key の同点を old で決めて m0）は、Z の決定の記録で状態の水準として分けるだけ。
- 鏡の予測は「patch の番号で決めた m1・m2 の同点が起きるまで」に限る（一度破れると後の履歴が分かれる）。その前の不一致は対称性の予測の反証で、実装の漏れか規則の非対称かを先に調べる。

## 4. 試験
- `GATE: cd experiments && julia --project=.. restmech.jl && julia --project=.. check_rb_restmech.jl`
