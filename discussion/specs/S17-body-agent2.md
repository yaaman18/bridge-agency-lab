# S17 一つの契約（生存の予定表）に揃えた Agent の照合（R-BODY-7 の次の版）

- 状態: r1（2026-11-07、妥当性 V10 の codex 1〜4・8・9 を反映）。S15 の結果の点検 7・8 への答え。
- 物: SF 版、**種子 91〜100（未使用）**、腕 :std・:swap（20 の物。同じ種子の二つの腕は独立の標本と数えない）、H 392。
- 契約: 生存の予定表（params、豊富でない）。基準の試し B1＝p1-high、比較の試し B2＝p2-high、同じ育ちの物から。B1・B2 は `AS.survives` の走りと同じ決定的な軌跡なので、
  B1・B2 で記録した生存が tab の intact 欄（p1-high・p2-high）と一致することを対照にする（軌跡の整合の対照で、構造の価値と生存への寄与の一致は保証しない）。
- 窓 w＝B1 の更新 33..64（事象 64）。value(e)＝窓 w 全体での |contributionOf w e ∩ nuPhiOf w|（LabCircuit、κ）。
- T_struct＝value(e)＞0 の受容器（w で一度でも構造の価値に寄与した結合、V10-2）。tab＝生存の予定表 4 つ（p1-high・p2-high・p1-then-p2・p2-then-p1）すべてで、無介入と、T_struct を**更新 1 から地平まで**黙らせた生存
  （窓より前も含む寄与を測る、V10-3）。道具の T（選択の予定表から同定）は記録だけ。
- act: e が更新 33..64 の全歩で点いていたのが B1 だけなら act e＝B1 の 33..64 で行為した区画運動の集合、B2 だけなら B2 の集合。理由を分けて記録（両方で全歩・どちらも全歩でない・帰属先の集合が空、V10-4）。
  証人 e1・e2 はどちらも帰属でき、集合が空でない受容器から探す。
- 照合: S15 と同じ生成器で `formal/gen/AgentBody2.lean` に書き出し、`agentOf` の型検査。組めない物は欠けた欄（DC・証人・ValueNeeded・来歴・軌跡の整合）を記録する（帰属できないことを自動的に Agent の不成立と同一視せず、理由を分ける）。
- 予測（凍結、`experiments/predictions-agent2.md`）。
- `GATE: cd experiments && julia --project=.. agent2.jl && sh agent_lean.sh AgentBody2`
