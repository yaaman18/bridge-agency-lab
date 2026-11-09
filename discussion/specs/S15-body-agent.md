# S15 同じ物での DC・構造の価値・選択・ValueNeeded の併記と、Lean の Agent の値を組む照合（R-BODY-7）

- 状態: r1（2026-11-07、ユーザー「じゃあそれで実装行ってくれ」。妥当性 V8 の codex 1〜8 を反映。D5 §7 改訂 r4）。
- 物: SF 版、**種子 71〜80（未使用）**、腕 :std・:swap（20 の物）、H 392。各物は一つの育ちの状態（BodyOrg の raised）から、次の試しを別々に始める（共通の初期状態からの別の試し、V8-7）。
  - 試し C1: 道具の選択の予定表 c1（(5,4)、choice_params、窓 5:15）。DC の記録をとり、**窓 w＝更新 1〜32、事象 32**。選択の集合 choice(C1)＝窓 5:15 で点いた区画運動。
  - 試し C2: 予定表 c2（(4,5)）で同じ。choice(C2)。窓 w2 も記録（照合には使わない）。
  - 生存の表 tab: 道具の生存の予定表 4 つで、T ありと T（道具の `value_tracking_units` から核を除いたもの）を黙らせた生存（`AS.survives`、params）。道具の L2 の各成分も同じ物で記録。
  - 来歴: 種子・腕・予定表の名・窓の境界・育ちの状態のハッシュ（CState の全フィールド）を JSON と Lean のファイルの頭に書き、三つの試しで同じハッシュであることを生成器が確かめる。
- act（先に固定、V8-4・5）: 受容器 e について、窓 5:15 の全歩で e が点いていたのが C1 だけなら act e＝choice(C1)、C2 だけなら act e＝choice(C2)。両方・どちらでもなければ「帰属できない」（act e＝∅、別に記録）。
  ValueDifferentiated の証人 e1・e2 は、**どちらも帰属できる**受容器の組から探す（value(e1)≠value(e2) かつ act(e1)≠act(e2)）。∅ による差だけでは証人にしない。
- 価値: value(e)＝|contributionOf w e ∩ nuPhiOf w|（LabCircuit の定義、κ で数える、D5 §7）。
- 照合: 物ごとに `formal/gen/AgentBody.lean` に w・act・tab を書き出し、`def agent_<i> := agentOf w_<i> act_<i> (by decide) ⟨e1, e2, …⟩ tab_<i> (by decide)` を型検査する。
  checkDC が偽、証人がない、checkValueNeeded が偽の物は、Lean の定義を書かず、どの欄が欠けたかを記録する（その物は「Agent を組めない」）。
- 予測（凍結、`experiments/predictions-agent.md`）。
- `GATE: cd experiments && julia --project=.. agent.jl && sh agent_lean.sh`
