# S23 中間の収量の予定表での α の対応の照合（gaps G6a、G4 の残り、`notes/G6G15G17.md`）

- 状態: r1・実施済み（README 項番120）（2026-11-08、往復3 の codex 1〜4 を反映）。S20b と別の契約（予定表をラボで作る。bp は変えない）。
- 手順・対・細胞・実現の定義は S20b（`S20b-body-alpha-scan.md`）と同じ。予定表だけ: **mid-32**＝(3,2) 一定、**mid-23**＝(2,3) 一定、**mid-32to23**＝(3,2)→(2,3)、**mid-41to14**＝(4,1)→(1,4)（switch 20、`AS.Schedule`）。
- 物: **種子 221〜230（未使用）**、SF、腕 std・swap、点 t∈64:32:384（本走で生きている点）、m1・m2、事前のたまり {0..10}U²。
- 量化（codex 2・3）: AM1・AM2 は全条件を合わせて各組が一度でも非ゼロの差（条件別の実現と使える対の数も報告）。組の使える対（その m の使える対）が 0 件なら、その組は判定不能。
- 結論はこの 4 予定表・種子・両腕での照合に限り、一般の収量への成立とは分ける（codex 1）。
- 予測（凍結、`experiments/predictions-alpha-mid.md`）。`GATE: cd experiments && julia --project=.. alpha_mid.jl && IN=results-alpha-mid.json julia --project=.. check_alpha.jl`
