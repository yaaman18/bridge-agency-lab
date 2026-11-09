# S19 沈殿だけの型と sed_fade の因果の試験（gaps G3、`notes/G3G4.md`）

- 状態: r1・実施済み（README 項番115〜117）（2026-11-08、往復1 の codex P1〜P6 を反映）。測定。規則・既定は変えない（sed_fade を切るのは分岐の写しの上、D6 R5-b′）。
- 対象の点: S18 の judge と同じ m*・E の同定（E＝m* に入る受容器からの辺で sg≥1）と (3)（`habit3.jl` の j3）が成り立つ点。物＝**種子 111〜150（未使用）**、SF、腕 2、生存の予定表 4（320 走）、H＝392、点 t∈64:32:384（介入の前に固定）。
  (3) を先に判定し、成り立つ点だけ分岐する。対象 0 点なら未判定で閉じ、種子を足さない（P6）。
- 介入: t の状態の写しから t＋400 まで二つの分岐。**N**＝無介入。**F**＝t＋1 から sed_fade だけを切る（`variant_horizon.jl` の `SEDFADE_OVERRIDE`、既定 nothing で不変。乱数・予定表・たまりは同じ写し）。
- 記録: t＋400 での E の sg（**sgkept**＝E のどれかが sg≥1）と q（**qkept**＝E のどれかが q≥1）を分けて（P2）、E の sg が全部 0 になる最初の歩、死の歩、m* の行為の回数、E の sg が下がった各更新とその経路（sed_fade による／weaken による／その他、更新の前後の差と規則の条件で分類）。
- 使える点＝N・F とも t＋400 まで生きる点。全対象数・両生存数・片側の死の数を併記する（介入の後の生存による選別、一般化しない、P3）。
- 読み: 「N が sg を失い F が保った点」に限り、この点・この 400 歩の窓で sed_fade を切ることで沈殿の喪失を避けた、と読む（P1）。sgkept がなく qkept だけなら型の持続とは読まない（P2）。
  育ちは sed_fade ありなので、sed_fade のない系統の物との比較ではない。L2 との兼ね合いは試さない。同じ走りの複数の点は独立の標本として数えない（P5）。
- 予測（凍結、`experiments/predictions-sedfade-cause.md`）。
- `GATE: cd experiments && julia --project=.. sedfade_cause.jl && julia --project=.. check_sedfade_cause.jl`
