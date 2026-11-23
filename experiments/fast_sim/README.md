# `experiments/fast_sim/` — 実時間稼働前の高速度シミュレーション基盤（2026-11-24）

- **位置づけ**: Raspberry Pi 5 上で実時間（1 歩 = 10 秒：1 日 8,640 歩、6 日 51,840 歩）の AUE を稼働させる前に、**10 秒待機のみを取り除いた完全同一の決定遷移**を CPU 全速で走らせ、長期生存・構成要素推移・実電波ドリフト耐性・24 時間 `stale` 障害耐性・反転／OOD 耐性・監査鎖再生一致を数秒〜数分で事前審査するための基盤。
- **厳守事項**:
  - **実時間等価性（`G-FS-PARITY`）**: 高速走行（待機 0 ms）と実時間間隔つき走行、および監査鎖テキストのみからの再生が **1 ビットも狂わず完全一致**することを毎実行で確認する。
  - **S52 144 時間ブラインディング厳守**: 読み込む実電波は既開封の `experiments/ambient/out-72h/design_72h.tsv`（`<= 72h`）と `experiments/radio_confirm/out/confirm_72h.tsv`（`<= 144h`）のみ。144 時間超の未確認行は一切開かない。
  - `core/`・`experiments/aue_seam/`・`rust/being-*`・`rust/trm-det/`・`~/bridge-protocol` 無変更。主列未使用種子 `1110` 非消費（専用シミュレーション種子 `690001`）。`phenomenal_claim = :not_certified` 固定。

## シナリオ一覧
1. **`parity_fast_200` 対 `parity_paced_200`（`G-FS-PARITY`）**: 待機 0 ms 対 5 ms＋監査テキスト再生の 3 者ビット一致検証。
2. **`radio_design_72h`（実時間 3.0 日 = 25,929 歩）**: S52 設計期間 72h 実電波（S68 `SIN_TABLE_1000`＋`round-half-to-even`）。
3. **`radio_confirm_72h`（実時間 3.0 日 = 25,923 歩）**: S52 確かめの期間 72h 実電波（`b_n` `−1.91 SD` ドリフト環境）。
4. **`radio_full_144h`（実時間 6.0 日 = 51,852 歩）**: 上記 2 期間を連続接続した 6 日間実電波通し。
5. **`stress_stale_24h`（実時間 2.0 日 = 17,280 歩）**: 24h 通常実電波の直後に 24h 連続 `stale_flag=1`（$z_1=z_2=0$ フォールバック）を強制注入。
6. **`stress_rev_ood`（実時間 2.0 日 = 17,280 歩）**: 4,000 歩目で反転、10,000 歩目で周期変更 `P=700` を注入。

## 実行方法
```sh
julia /Users/yamaguchimitsuyuki/bridge-agency-lab/experiments/fast_sim/fast_sim.jl
```
※S64 C0 学習重みが確定次第、同じシナリオ・同じ 4 継ぎ目床へ TRM 予測器（C1 凍結頭・C2 97 頭学習・遅延軛）を挿し込んで、Pi 5 実時間稼働前の高速審査を実施する。

## 2026-11-24 修正記録
- `G-FS-PARITY` 失敗の原因: 監査鎖の `species_id` が場面名入りで fast/paced で異なった。parity 対は同一 id（`fastsim-parity_200`）にして PASS。
- 実電波の読み込みは TSV 列番号が誤り（入力 0 件で空の通過）。ヘッダ名（w_sum, b_n, fail）で引き、入力 0 件はエラーにした。
- 基準線（予測器なし）: 全場面が 758〜1538 歩で死亡。生存は判定でなく結果として報告。基準線の shasum は `experiments/freeze-fast_sim-baseline-20261124.txt`。
- C0 重み確定後の TRM 再走は、5 場面ごとの終了理由・死亡歩・末尾ハッシュの予測を先に freeze してから走らせる（codex P3）。
