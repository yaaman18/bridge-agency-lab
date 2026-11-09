# S11 定位反応の馴れ（h）を移す介入（S10 B の次の手、V4 の codex 6・7）

- 状態: r1（2026-11-07）。問い: 同点の腕の差は r5→m1・r5→m2 の h の違いで運ばれているか。
- 物: S10 B と同じ 13 組（H 392、S8 で J0 の同点に腕の差がある種子）、同点 5 試し（choice_params、窓 5:15）、S10 の自前の choice（無介入で AS.choice と一致）。
- 介入（育ちの状態の写しで、r5→m1・r5→m2 の h だけを変える。ほかの状態は固定）:
  X1 :std の腕に :swap の h を移す、X2 :swap の腕に :std の h を移す、X0 両腕とも 0 にする。それぞれ一回だけ（試しの始め）と持続（各更新の後に同じ値に戻す）。
- 判定（凍結の前に固定）: 「腕の差が消えた」＝比べる二つの写しで、5 つの同点の選択がすべて同じ。X1 は (:std＋:swap の h) と :swap、X2 は (:swap＋:std の h) と :std、X0 は両方 0 どうし。
  記録: 窓の中で r5 の辺が駆動した歩の数（`drove`）、行為の数、同点で行為があった試しの数。
- 反証（V4-7）: h を揃えても（X0 持続）差が残る組があれば、その組では「h だけで差を説明できる」は退ける。
- 予測（凍結、`experiments/predictions-habituation.md`）。
- `GATE: cd experiments && julia --project=.. habituation.jl && julia --project=.. check_habituation.jl`
