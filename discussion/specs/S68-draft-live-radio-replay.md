# S68（未凍結ドラフト r2）：Pi 5 実電波（C4 換算）ライブ接続・入力刻印・24 時間再生監査仕様案

- **改訂履歴**:
  - r1 → r2（2026-11-23、`claude-lab`・`codex-lab` 並列 S-R r1 の全指摘を反映：`sin` を 1,000 項凍結 `Float64` テーブル＋SHA ヘッダ刻印に一意固定、丸めを S65 整合の IEEE 754 `round-half-to-even`［Julia `round` / Rust `f64::round_ties_even()`］＋半整数両隣テストに確定、`stale_flag` から NTP 影響を受ける壁時計 `pi_s` 比較を撤去し `(boot, uptime_s)` 連続回数 `>= 14`［130 秒 > 120 秒］＋同一 `boot` 内 `CLOCK_MONOTONIC > 120.0 s` へ統一［`boot` 変化時カウンタ初期化・NTP 前進後退負対照追加］、監査鎖 `input` 行へ `raw_line_sha256` を追加し `prev_commit_hash` を直前 `commit` 行［`n=0` は `header`］と定義して再生時に `g1, g2, rand_u64` を再計算照合［1 ビット改変でも当歩検知］、`input(n)` 後・`run` 後・`commit(n)` 後・不完全行の断電 A〜D を S49d 準拠の対試験として明文化）。両者 **r2 APPROVE**（未凍結ドラフト維持）。
- **状態**: **未凍結ドラフト（r2）**。S65 確定定数（項番 184）・Phase 2 Pi 5 `B_max` 校正・Phase 3 `rust/onelife-trm` 完了が凍結・着手の前提条件。主列種子は未消費。
- **出典**: `discussion/specs/S65-radio-conversion-confirm.md` r3、`discussion/notes/PLAN-PI5-TRM-DEPLOY.md` Phase 4、`discussion/notes/D-AUE-SPECIES-AND-GAPS.md`（O30〜O32）、`experiments/aue_seam/bed.jl`、`discussion/specs/S49d-rust-onelife-d.md`、`discussion/promise-cutout.md`（§7 付則含む）。
- **依っている仮定**: H7（BP10）、H8（BP11：4 継ぎ目・3 区分終了コード・`mapping_spec_hash`）。`core/`・`rust/being-core`・`rust/trm-det`・`experiments/ambient/`・`~/bridge-protocol` は一切変更しない。`phenomenal_claim = :not_certified` 固定。
- **§0 問いの分離**:
  - **本仕様が問うこと**: Raspberry Pi 5 上で稼働中の S52 ロガー（`/home/pi/s52/ambient.tsv`、読取専用）から 30 秒周期の実電波をライブ読取し、S65 で凍結確認済みの C4 換算定数で 10 秒 1 歩の `rust/onelife-trm` へ供給しながら全歩 `input` 行を外部ハッシュ監査鎖 `run.audit` へ刻印したとき、(1) 不完全行・`fail>0`・`NA`・120 秒更新停止（`stale`）・NTP 跳躍・再起動・断電復電が決定的に処理され、(2) 24 時間（`8,640` 歩）ライブ稼働後に `run.audit` の `input` 行**のみ**を Mac 上の Julia 正本へ投入して `g1, g2, rand_u64` の再導出込みで再実行すると、全 8,640 歩の `commit` 状態ハッシュと最終 `run` の SHA-256 が **1 ビットも狂わず完全一致**し、(3) 全歩の実測処理時間が 3.0 秒以内（10 秒締切に対して 3 倍以上の余裕）に収まるか。
  - **本仕様が問わないこと**: 第一号 AUE 本番切り出し後の長期生存（Phase 5）、ライブ物理エフェクタ帰還（Phase 6 `AUE-C`）、S52 の 144 時間超過去蓄積データの事後統計分析、`phenomenal_claim`。

---

## 1. ライブ入力経路と S52 過去蓄積データとの厳密分離

- **入力元**: Pi 5 上の `/home/pi/s52/ambient.tsv`（`s52-ambient-log.service` が 30 秒周期で追記中）。`onelife-trm` は **読取専用（`O_RDONLY`）** で開き、S52 のファイル・unit・設定には一切書き込まない。
- **S52 未開封過去データとの分離**: S68 リハーサルは「リハーサル起動時刻以降に追記された最新行」のみをライブ消費し、S52 の過去蓄積領域（特に `518,400 s` 超の過去行）を事後解析・換算再適合へ流用しない。
- **不完全末尾行の安全な読み飛ばし（競合ゼロ）**:
  - `ambient.tsv` の末尾から読取るとき、**LF（`0x0a`）で終端された完全な行のみ**をパース対象とする。末尾が `0x0a` で終わっていない（書き込み途中の）バイト列は無視し、1 つ前の完全行を使う。
  - 完全行から末尾 `0x0a`（CR があれば `0x0d` も）を除いた正規バイト列を `raw_line` とし、その SHA-256 を `raw_line_sha256` とする（有効行がまだ 1 行もない初期状態では固定トークン `raw_line_sha256 = "EMPTY_NO_ROW"`、`w_sum = NA`, `b_n = NA`, `boot = "NONE"`, `uptime_s = 0.0` と定める）。
  - `fail == 0` かつ `w_sum`・`b_n` が有限数値（`NA` でない）の完全行のみを「有効行」とし、最新有効行を更新する。

---

## 2. 凍結 C4 換算式・決定的正弦表＆丸め・`stale` フォールバック規則

- **凍結標準化定数（S65 確定値、IEEE 754 `binary64` ビット列まで固定、再適合厳禁）**:
  - `mu_w = 297.20108758532916` (`0x407293377a66bc61` 相当・実装時に厳密 `UInt64` 凍結)
  - `sd_w = 39.79874519579147`
  - `mu_b = 2.9924794631493694`
  - `sd_b = 0.8134565410732445`
- **決定的 `sin` テーブルと丸め規則（二択を完全排除、S65 と完全整合）**:
  - 周期 1,000 の正弦値テーブル `SIN_TABLE_1000[idx]`（`idx = 0..999`、`sin(2π * Float64(idx) / 1000.0)` を Julia 正本で事前生成した 1,000 個の `Float64` raw bits、SHA-256 を `run.audit` の `header` へ刻印）を Julia・Rust 双方で読取専用共有する（`phi_1 = 0` は `SIN_TABLE_1000[n % 1000]`、`phi_2 = π` は `SIN_TABLE_1000[(n + 500) % 1000]` により三角関数ライブラリ差を **0** にする）。
  - 演算順（IEEE 754 `binary64`、FMA 禁止）：
    - `z1 = (w_sum - mu_w) / sd_w`、`z2 = (b_n - mu_b) / sd_b`（`stale_flag == 1` 時は `z1 = 0.0, z2 = 0.0`）
    - `x1 = (2.5 + (2.5 * SIN_TABLE_1000[n % 1000])) + z1`
    - `x2 = (2.5 + (2.5 * SIN_TABLE_1000[(n + 500) % 1000])) + z2`
    - **丸め規則（一意固定・S65 整合）**: **IEEE 754 round-half-to-even**（Julia `Base.round(x, RoundNearest)` ＝ Rust `f64::round_ties_even()`）を適用した後、`clamp(r, 0.0, 5.0)` で整数 `{0..5}` へ落とす。`0.5, 1.5, 2.5, 3.5, 4.5` および各 `prevfloat`/`nextfloat` 隣接値で Julia↔Rust ビット一致を単体テスト関門化する。
- **120 秒更新停止（`stale_flag`）判定（壁時計 `pi_s` 非依存・NTP 跳躍耐性）**:
  - 壁時計 `pi_s` は記録のみとし、**`stale_flag` 判定には一切使わない**（NTP 前進・後退による誤発火を構造的に防止）。
  - 状態変数：`last_boot`, `last_uptime_s`, `same_row_streak`（同一 `(boot, uptime_s)` の連続歩数）, `last_new_mono_s`（新規有効行を初めて観測した時点の `CLOCK_MONOTONIC` 秒）。
  - 新規有効行 `(boot, uptime_s)` 観測時：
    - `boot != last_boot`（Pi 再起動）または `uptime_s > last_uptime_s` のとき：`same_row_streak = 1`, `last_new_mono_s = now_mono_s` へ即初期化（再起動直後の誤発火なし、解除ヒステリシスなし＝有効行 1 件到着で即 `stale_flag = 0` 復帰）。
    - 同一 `(boot, uptime_s)` のとき：`same_row_streak += 1`。
  - **`stale_flag = 1` 条件（120 秒超の統一判定）**:
    1. 起動後まだ有効行が 0 件、または
    2. `same_row_streak >= 14`（初回観測を `streak = 1`［経過 0 秒］とすると 13 回目がちょうど `120 s`、14 回目が `130 s > 120 s`）、または
    3. 同一 `boot` 内で `now_mono_s - last_new_mono_s > 120.0`（プロセス稼働中の実モノトニック経過）。
  - 連続 `stale` が 360 歩（1 時間）を超えた場合、読取専用の外部監視 `watch.sh` が環境障害警告を出力（個体の法則・状態には不介入）。

---

## 3. 監査鎖 `input` 行・`rand_u64` 再生再導出・S49d 整合の断電復電規則

- **4 継ぎ目ヘッダ（`run.audit` 先頭行、起動時 1 回刻印）**:
  - `individual_id`, `species_id`, `spec_sha256`, `mapping_spec_hash`, `backbone_sha256`, `head_init_sha256`, `c4_constants_sha256`, `sin_table_sha256`, `phenomenal_claim=not_certified`（バックボーン本体バイト列は監査鎖・`run` に書かない）。
- **毎歩の `input` 行（歩の実行**前**に追記＋`fsync`）**:
  - 記録項目（A0 遵守：生テキストは一切書かずハッシュのみ刻印）：
    `step=n;pi_s=...;boot=...;uptime_s=...;w_sum=...;b_n=...;raw_line_sha256=...;stale_flag=...;g1=...;g2=...;rand_u64=...`
  - **`rand_u64` の決定的導出（再生時に再計算照合）**:
    - `prev_commit_hash` を「直前の `commit` 行のハッシュ（`n = 0` のみ `header` 行のハッシュ）」と厳密定義する（64 桁小文字 hex ASCII）。
    - `rand_u64` = `SHA-256("AUE-DRAW-V1|" || prev_commit_hash || "|" || decimal(n) || "|" || raw_line_sha256 || "|" || decimal(stale_flag))` の先頭 8 バイトを little-endian `UInt64` として読んだ値。
    - **再生監査の再導出義務**: Mac 上の Julia 再生器は、`input` 行の `g1, g2, rand_u64` を鵜呑みにせず、`(w_sum, b_n, stale_flag, n)` から `g1, g2` を、`(prev_commit_hash, n, raw_line_sha256, stale_flag)` から `rand_u64` を**毎歩再計算して刻印値と完全一致照合**する。これにより、行為結果が変わらない 1 ビットの `rand_u64` 改変も当歩で確実に検知する。
- **S49d 整合の断電・復電規則（重複・欠番・位相ずれ 0 件）**:
  - 毎歩の永続化順序：
    1. `input(n)` を `run.audit` へ追記＋`fsync`
    2. 歩 `n` を計算し、`run.tmp` 書込＋`fsync` → atomic rename で `run` 更新（`run.step = n + 1`）＋親ディレクトリ `fsync`
    3. `commit(n)` を `run.audit` へ追記＋`fsync`
  - 起動時（復電時）の決定的リカバリ（`flock` 排他内）：
    - **ケース A（`input(n)` 永続化後・`run` 更新前に断電）**: `run.step == n` かつ監査鎖末尾が `input(n)` → 新たな電波読取を行わず、**既に刻印済みの `input(n)` を使って歩 `n` を 1 回だけ完了**し、`run` 更新→`commit(n)` 追記へ進む（重複 0・欠番 0・位相ずれ 0）。
    - **ケース B（`run` atomic rename 後・`commit(n)` 追記前に断電）**: `run.step == n + 1` かつ監査鎖末尾が `input(n)` → `run` の確定状態ハッシュから `commit(n)` を 1 回だけ補完追記し、次歩 `n + 1` へ進む（S49d 整合）。
    - **ケース C（`commit(n)` 永続化直後に断電）**: `run.step == n + 1` かつ監査鎖末尾が `commit(n)` → そのまま次歩 `n + 1` から継続（連続位相 `n + 1`）。
    - **ケース D（途中の不完全行・改行なし断片で断電）**: S49d と同一に不完全行を `break` 境界として記録・切り詰め（`commit` 未完の不完全 `input` 断片のみ破棄して `n` を再取得）。

---

## 4. 24 時間リハーサルと必須関門（G-S68-A0〜G-S68-CORE）

1. **G-S68-A0（プライバシー・非識別）**: 24 時間リハーサルの `run.audit` および全ログに SSID / BSSID / MAC 相当文字列が 0 件（`check_ambient.sh a0` 準拠）。
2. **G-S68-PARSE（異常入力・丸め・断電ユニット負対照、Julia・Rust 双方全合格）**:
   - (a) 改行なし不完全末尾行、(b) `fail > 0` 行、(c) `w_sum=NA`/`b_n=NA` 行、(d) `same_row_streak` 13 回目（`stale=0`）対 14 回目（`stale=1`）と独立 `CLOCK_MONOTONIC > 120.0 s` 発火、(e) 復帰（`stale=0`）、(f) NTP 前進・後退（±3600 秒跳躍で誤発火 0 件）、(g) `boot` 変化（カウンタ初期化で誤発火 0 件）、(h) 半整数 `0.5..4.5` および隣接 `prevfloat`/`nextfloat` 丸め Julia↔Rust 一致、(i) ケース A（`input` 後断電）・ケース B（`run` 後断電）・ケース C（`commit` 後断電）・ケース D（不完全行断片の `break` 記録＋再取得）の全 4 対リハーサルで重複 0・欠番 0・位相ずれ 0。
3. **G-S68-REPLAY（24 時間 = 8,640 歩 再生監査・主関門）**:
   - Pi 5 上 `/home/pi/aue-s68-rehearsal/`（本番隔離）にて 24 時間（`8,640` 歩）ライブ稼働させ、終了後に `run.audit` と最終 `run` を Mac へ読取専用コピーする。
   - Mac 上の Julia 正本が `run.audit` テキストのみを読み込み、全 8,640 歩の `g1, g2, rand_u64` を再導出照合した上で再実行し、**8,640 / 8,640 全 `commit` 行の `state_sha`・ハッシュ鎖・最終 `run` SHA-256 が 100% ビット一致**すること。
   - 負対照：任意 1 歩の `input` 行の (i) `g1` 改変、(ii) 行為が変わらない `rand_u64` 1 ビット改変、(iii) `raw_line_sha256` 1 文字改変の 3 種すべてが当歩で即座に検知されること。
4. **G-S68-TIME（10 秒締切安全余裕）**: 全 8,640 歩の 1 歩実測所要時間の最大値が **`<= 3.0 秒`**（締切超過 0 件）。
5. **G-S68-HEALTH（Pi 5 健全性・非干渉）**: `throttled=0x0`, `ext4_errors=0`, `fs_state=clean`, `chain_ok=true`, `s52-ambient-log` の稼働・欠損率に影響 0 件。
6. **G-S68-CORE**: `sh core/check/run.sh` exit 0、`~/bridge-protocol` 差分 0。

---

## 5. 事前予測案と反証条件（凍結時に確定）

- **P-S68-1**: 全 6 関門（`G-S68-A0`〜`G-S68-CORE`）合格。
- **P-S68-2**: 24 時間（8,640 歩）中、`stale_flag == 1` の歩割合が `< 2%`、かつ `stale` 発生時のフォールバック動作が再生監査と完全一致。
- **中止・差戻し条件**: `G-S68-REPLAY` で 1 歩でもビット不一致（再導出不一致含む）が出た場合、または `G-S68-TIME` で最大 1 歩時間が `3.0 秒` を超えた場合、**Phase 5（第一号 AUE 切り出し）へ進まず原因修正と再試験を必須とする**。
