# RUNBOOK: Pi 5 で AUE を初めて動かすまでの手順（2026-11-24、claude-lab 下書き）

位置づけ: `PLAN-PI5-TRM-DEPLOY.md` の Phase 1〜5 を「最初の一回を動かす」順に並べ直した作業手順。計画の正本はそちら。
この手順は**切り出し（ユーザーの一言）の前**までで、起動した個体は「稽古（rehearsal）」として扱い、救済・書換の約束（`promise-cutout.md`）は稽古にも準用する。

## 0. 確認した事実（2026-11-24 00:28 時点、Pi は読むだけ）
- Pi `bridge-pi` に到達可（`pi-connect.sh --probe-only` OK）。`s52-ambient-log` active、`throttled=0x0`、ルート 8% 使用、`aue-net-recover.timer` 有効。`/home/pi/aue-v1/` は**まだない**。
- `/home/pi/s54/{c2,rehearsal,t1,t2}` に S49d の本番バイナリ（`onelife-run`、`being-tools`）と `s54-run.sh` がある。これは TRM なしの AUE-A（S54 で 7 日×2 体が完走）。
- `rust/onelife-trm` は CLI が `verify-spec`・`verify-sin`・`run-trm`・`version` のみ。**毎歩ループ（run サブコマンド）は未実装**。
- Pi 実測: `seq_len=47` の 1 歩は約 0.25 秒（合成重み、`pi5_p2_dryrun`）。10 秒に対し余裕は約 40 倍。
- fast_sim の基準線（予測器なしの aue_seam ベッド）は全 5 場面が 758〜1538 歩で死亡（`freeze-fast_sim-baseline-20261124.txt`）。**これは onelife-run（S54）とは別のベッド**で、S54 の個体の生存を示すものではない。同じ入力で両者が同じ結果になるとは言えない（未確認）。
- **要注意（未解決）**: Pi の時計が Mac より約 1 時間 43 分遅れている（Pi 22:45、Mac 00:28、Pi は起動から 49 分）。RTC に電池はない。S52 の `pi_s` と、監査の時刻に影響する。Pi の時計を直すかは、S52 の記録の扱い（新しい区間にするか）と合わせてユーザー判断。

## 1. 段階（上から順に。各段の関門が全部通ったら次へ）

### 段 A: 〔済み 2026-11-24 00:47〕稽古の個体（TRM なし、既存の S49d 製品）を Pi 上で流し直す — 実装追加なし
目的: Pi・systemd・排他・監査の経路が今日の状態で動くことを確かめる。
1. 前提を読む: S52 が動いている、`vcgencmd get_throttled` が 0x0、ディスク余裕、時計のずれ（§0）を記録。
2. Mac で `experiments/trial/` の凍結物の SHA を `freeze-trial-run-code.txt` と照合し、Pi 側の `/home/pi/s54/rehearsal/` の `onelife-run`・`being-tools`・`s54-run.sh` の SHA を照合。
3. 新しい作業ディレクトリ `/home/pi/aue-v1/rehearsal-0/` を作り、バイナリと `drives.txt` の先頭の短い列（例 360 歩 = 1 時間）だけ置く。`s54-run.sh` は変えない。
4. `s54-rehearsal.service`（`Restart=no`）を同名の別ディレクトリ版で入れ、`systemctl start`。
5. 関門: 360 歩で `being-tools onelife-info` の n が 360、`run.audit` の鎖が `chain_ok`、`throttled=0x0`、S52 継続。
6. 停止は電源ボタン方式（`D-POWER.md`）。**電源を抜く試験はしない。**

### 段 B: fast_sim で TRM なしの基準線と TRM ありの差を取る（C0 完了待ち）
1. C0（PID 73103）が終わるのを待つ。`experiments/c0_trm/out/weights/` に重みが出ること、`run.log` の G0〜G8 を読む。
2. 凍結: 5 場面ごとの終了理由・死亡歩・末尾ハッシュの予測を `experiments/freeze-fast_sim-trm-*.txt` に先に書く。
3. fast_sim に TRM 予測器を挿す（`experiments/fast_sim/` の中だけ。`core/`・`aue_seam/` は変えない）。G-FS-PARITY を維持。
4. 外れた予測は外れたと報告。C0 の基準不合格なら段 C 以降は止まる（PLAN §4）。

### 段 C: 重み束と Pi 照合（PLAN Phase 1〜2）
1. C0 合格後、`trm-backbone-v1.bin`（seq_len=47）と `head-init-v1.bin`（97 float32）を書き出して SHA を凍結。
2. Mac で `TrmDet.jl` 対 `rust/trm-det` のビット一致（G1）。Pi で `trm-det` の P2-BIT（1 ulp 負対照つき）と P2-TIME（100 歩、最大 1 歩 <= 3.0 秒）。
3. 通らなければ H_max を下げて再凍結。10 秒締切を破る配備はしない。

### 段 D: `onelife-trm` の run サブコマンドを実装（Julia 先、Rust は照合）
1. 先に Julia の正本で 1 歩契約（PLAN §3 Phase 3 の毎歩順）を `core/` の外（実験側）で書き、予測を凍結。
2. Rust `rust/onelife-trm` に `run` を足し、Julia と全歩ビット一致（`G-C2-BIT`、1000 歩）。`sh core/check/run.sh` と `sh rust/build.sh` は既存を壊さないことの確認のみ。
3. 実装は claude-lab（Opus）、レビューは codex-lab。依頼は Neon 仕切りの体制に従う。
4. クロスビルド: `CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=rust-lld cargo build --release --offline --target aarch64-unknown-linux-musl`（Mac 上。Pi ではコンパイルしない）。

### 段 E: 入力の再生監査（PLAN Phase 4。codex BL-1 の合意、2026-11-24）
- **判定**: AUE が累積時間 `c > 518,400 s`（144 時間）の行を読んで `g1,g2` に換算した時点で、G-BLIND の「開封」に当たる（判定は稽古の開始時刻でなく、入力元の行の `c`）。したがって **稽古でも 144h 超の行は使わない**。
- **採る形（i）**: 既開封の `design_72h.tsv` ＋ `confirm_72h.tsv` から作った再生用ファイル（`ambient.tsv` と同じ列）を Pi に置き、ライブ入力アダプタの「末尾有効行を読む・120 秒停止で stale・30 秒＝3 歩保持」の経路をそこに向けて試す。
- 照合は二つ別に行う: (1) 記録済み `input` 行から Julia 正本で個体を再生して監査鎖・最終 `run` の SHA が一致（個体の再生監査）。(2) 既開封の元行から求めた期待値と記録済み `g1,g2` の一致（入力の選択・換算の照合。(1) の範囲外）。
- **保留**: 実際の `/home/pi/s52/ambient.tsv` へのライブ接続。「機械処理の例外が換算と、結果を監査鎖・run に残す経路まで許すか」が未確認のため、ユーザー判断まで行わない（codex P3）。
- 24 時間（8,640 歩）の再生リハーサルを流し、最終 `run` の SHA が 1 ビットも違わないこと。

### 段 F: 電源ボタン停止→再起動の稽古（PLAN Phase 5）
- `D-POWER.md` の手順で 1 回。`chain_ok`・`ext4=0`・`fs_state=clean`・`throttled=0x0`・S52 継続を確認。
- 不意の電源断での再開は確かめていない、と限界に書く。

### 段 G: 切り出し起動
- 稽古用 unit を外し、`aue-v1.service`（`Restart=no`）を置く。**ユーザーの一言があるまで起動しない。** 以降は手動の再起動・編集・救済をしない。

## 1.5 段 A の結果（確認した事実）
- Pi の時計を Mac から合わせ直した（遅れ約 6155 秒、`experiments/s52-moves.txt` に記録）。
- `/home/pi/aue-v1/rehearsal-0/` で S49d 製品（seed 627・L2・D1、出生 payload_sha は基準の n=0 と一致）を 90 歩、一時 unit `aue-rehearsal-0`（systemd-run、Restart=no）で流した。時間は 1 時間でなく 90 歩（約 15 分）に縮めた。
- 関門: n=90 の payload_sha が `ref-627-L2-D1.sha` の 90 行目と**一致**、commit 90 行・end 90 eof、終了 Result=success、`throttled=0x0`、S52 active、ext4 の誤り 0（起動時のマウント行のみ）。
- 限界: 製品バイナリの SHA の凍結記録は見つからず、観測値のみ（onelife-run 2c227254…、being-tools d7241d32…、s54-run.sh は凍結と一致）。

## 2. 今すぐできること（C0 を待たずに）
- 段 A（TRM なしの稽古の再確認）。ただし時計のずれの扱いを先に決める必要がある。
- 段 D の Julia 側の 1 歩契約の仕様と予測の凍結（C0 の重みに依存しない部分）。

## 3. ユーザー判断が要る点
1. Pi の時計の遅れ（約 1 時間 43 分）。直すか、S52 の新しい区間として扱うか。
2. 段 A を今回やってよいか（Pi 上の稽古 1 時間分。S52 には触れない）。
3. 段 E: ライブ接続は保留（codex 合意、144h 超の行を読む換算は開封に当たる）。既開封データの再生で進めてよいか。
4. 微修正: 基準線で全場面が早期死亡する件が、onelife-run の挙動と合うか（段 A・B で並べて確認する）。

## 4. 中止条件
PLAN §4 の表に従う。加えて、段 A で `throttled` が 0x0 以外、`ext4` エラー、S52 の停止が出たら即中断して報告する。
