# S29 身体で育てる版 G と別の世界での S7・S17（gaps G18、`notes/gapsC.md`）

- 状態: r1・実施済み（README 項番128）（2026-11-08、gaps C 往復5 の codex 1〜7 を反映）。
- **(a) G 版**: `BodyOrg(...; grow = true, KC = 0.002, sed_fade = true, …)`（項番81 の身体で育てる形、FEED・RAISE "body" の 800 歩、育ちの間も KC を払う。試しは**更新 799 の後の身体・回路・たまり・乱数の写しから始まる**、`variant_horizon.jl:70–80`・`:110–112`）。規則の残り（bin3・idle_first・核の関門）は SF 版と同じ。
  grow の育ちは保育期の台本の腕（:std/:swap）を使わないので、**腕は 1 つ**（物＝種子）。S7 は種子 351〜360（未使用）、生存の予定表 4・H 294/392/588、S17 は種子 361〜370（未使用）・H 392。selfmaint.jl・agent2.jl に ENV `GROWV=1`（既定は今のまま）。
  予測は凍結済みの S7（SP1〜SP7）・S17（AH1〜AH4）の文を逐語で写し、種子・版・腕の数（S17 は 10 物）だけ替える。SF 版との成績の差を版の効果とは読まない。
- **(b) 別の世界**: SF 版の S7 を、S23 の中間の収量のラボの予定表 4 つ（mid-32＝(3,2) 一定、mid-23＝(2,3) 一定、mid-32to23、mid-41to14、switch 20）で。**種子 371〜380 を 4 つの予定表すべてで共用**（両腕）、H 294/392/588。selfmaint.jl に ENV `SCHEDS=mid`（既定は凍結の生存の予定表）。
  SP1〜SP7 の文の「the 4 frozen survival schedules」を「the 4 lab schedules」に替えて写す。**適用不能**の定義（事前に固定、codex 5）: 分岐点が 1 つもない走り（t＝32 の前に身体が死ぬ）は予測の判定から除き、適用不能として数える（反証に数えない）。予定表・種子は結果を見て選び直さない。
- 別の世界での S17 は契約（B1＝p1-high・B2＝p2-high）が予定表に依るので今回は作らず、**未検証として G18 に残す**（codex 2）。
- 予測（凍結、`experiments/predictions-grow-world.md`）。
