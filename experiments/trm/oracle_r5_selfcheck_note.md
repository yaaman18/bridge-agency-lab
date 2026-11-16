# oracle_r5.py の自己検査: 恒真のものと効いているもの（2026-11-16 lab-coder、読むだけ。Python は走らせ直していない）

対象: `experiments/trm/oracle_r5.py` sha 58b33be0a2db9d407dd734fd2416da71fd63a2726ddde1902c3e1d56e440a3c1（変えていない）。行番号はこの版。

## 記録の作り（trace_act、41–100 行）
- 74–86 行: 巡の頭の `z_H_in, z_L_in = z_H, z_L`（73）は前の巡の終わりの同じ変数。`z_H_out` と `z_H_after_update`（84・85）は同じ `z_H` の clone。
  `ok_head`（81）は `z_H0, z_L0`（68・82 で前の巡の終わりを入れ直す）と比べるので、同じ値どうし。
- 巡の数は `range(inner.config.H_cycles)`（72）、L の回数は `range(inner.config.L_cycles)`（76）で決まる。

## check_chain（178–199 行）の各検査
| 行 | 名 | 判定 | 理由 |
|---|---|---|---|
| 181–182 | rounds（巡の数 ≠ `W.CUR["H_cycles"]`） | 記録の上では恒真に近い | 巡の数は 72 行の model の H_cycles。`W.CUR` と model の設定がずれたときだけ落ちる。下の 345–348 の負の対照で落ちることは確かめてある |
| 185–187 | in%d | **恒真** | 73 行で z_in を前の巡の z_out（巡 1 は cin）と同じ値から取って clone している。比較は同じ値どうし |
| 188–189 | inprev%d | **恒真** | 81 行の ok_head は 82 行で更新した同じ値との比較で、常に True |
| 190–191 | out%d | **恒真** | 84・85 行で同じ `z_H` を二度 clone したものどうし |
| 192–193 | liter%d | 記録の上では恒真に近い | l_iters は 76 行で `inner.config.L_cycles` 回積む。`W.CUR` と model の設定がずれたときだけ落ちる |
| 194–196 | carry | **効いている** | 最後の巡の z を、別に走らせた ACT forward（`W.run_act_sequence`、250 行）の新しい carry と比べる |
| 197–198 | carry_in_H | **恒真** | 巡 1 の z_H_in は 67・73 行で cin.z_H そのもの |

## main の検査（240–352 行）
- 249–264 module_calls_equal_forward: **効いている**（モジュール直呼びの記録と、公式の forward の出力・carry をビット比較。混ざった reset も 2 通り）。
- 266–277 PT5-0_old_fixtures_bitequal: **効いている**（旧 fixtures の JSON とビット比較）。
- 279–289 chain: 中の check_chain は上の表のとおり。効いているのは carry（195）と、284–285・287–288 の出力（logits・q）と forward の出力のビット比較。
- 291–336 readback: **効いている**（書いた JSON を読み戻し、テンソル・巡の数・l_iters の長さと値までビット比較。直列化の誤りを捕まえる）。
- 340–344 bitequal_rejects_signed_zero / accepts_identical: **効いている**（比較関数そのものの負と正の対照）。
- 345–348 chain_rejects_missing_round: 落ちることは確かめるが、`probe` を `mixed_new`（混ざった reset の carry）と比べるので、巡の数の検査（181）と carry（195）の**両方**で落ちうる。巡の数の検査だけの検出力は切り分けていない。
- 349–350 chain_accepts_recorded: 正の対照として効いている。

## まとめ
- 恒真: in%d（185）・inprev%d（188）・out%d（190）・carry_in_H（197）。記録の作りから同じ値どうしの比較になる。
- 設定のずれのときだけ効く: rounds（181）・liter（192）。
- 実際に効いている: carry（195）、forward との一致（249–264）、出力の一致（284–288）、旧 fixtures とのビット一致（266–277）、読み戻し（291–336）、比較関数の対照（340–344）。
- 巡の連鎖（巡 h の頭＝巡 h−1 の終わり）は「検査で確かめた」のでなく「記録の作りでそうなっている」。fixtures の上でそれが保たれることは readback が支える。
- 基準は作り直していない（ユーザー了承なしに変えない）。恒真の検査を外す・置き換えるかは未決。
