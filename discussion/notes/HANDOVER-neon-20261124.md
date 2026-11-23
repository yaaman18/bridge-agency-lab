# Neon 仕切り役の引き継ぎメモ（2026-11-24 作成）

- 理由: `hub:neon`（agy, gemini-4-neon-high）が "Individual quota reached" で停止。解除まで約 114 時間（2026-11-24 00:10 ごろ時点）。
- 作成方法: neon 窓のスクロールバック、`ps`、git、ファイルの時刻から再構成した。Neon の頭の中にあった文脈そのものではない。**未確認の点は「未確認」と明記**。
- 注意: `discussion/STATE.md` の更新は 2026-11-14 のままで古い。現状の正本としては使えない。

## 体制（記憶メモより）
- 2026-11-20〜: Neon=仕切り、CC(Opus 直)=コーダー、codex=レビュー。概念設計はユーザー×Neon→3者議論。
- 席: `hub` の tmux 窓 `neon` / `bp-claude` / `lab-claude` / `logs` / `shell`。`lab-claude` は Opus 5.5 で正常稼働。`bp-claude` は「信頼するフォルダか」の確認画面で止まっている（レートリミットではない）。

## git の状態
- 直近 commit・push 済み: `26c7217`「Pi 5 seq_len=47 dry-run (4-way bit-exact), pi5_ops recovery/watchdog, & rust/onelife-trm …」（2026-11-24 00:05）。`main` は `origin/main` と同期。
- **未 commit（新規）**: `experiments/fast_sim/`、`experiments/c0_trm/{TrmC0.jl,c0_trm.jl,out/}`、`.agent/`、`memo.md`、`Muse と相談.md`、`results-port*.out/.err`、`results-tf.out`。
  - ユーザーの「commit と push をして」は 00:05 の commit までで完了している。上のファイルはその後に増えたもの、または元から未追跡。**commit するかは、ユーザーに確認してから**。

## 進行中のもの
1. **S64 C0（TRM 学習）**
   - 実体: `julia --project=. -t 8 experiments/c0_trm/c0_trm.jl out`（PID 73103、11/23 23:31 開始、約 396 分の CPU 時間。2026-11-24 00:07 時点でまだ動作中）。
   - 親の `discussion/claude-code-turn.sh high …/s64_impl_prompt.txt`（PID 86780/86810）は 22:01 開始。Neon がこの完了通知を待っていた。
   - 事前ゲート（G1・G3・G-TIME）は PASS（`out/run.log`、510 s）。G-TIME の見積もりは 48 学習で 9274 s（上限 10800 s）。
   - **未確認**: 学習本体が最後まで終わったか。終わったら、Neon の計画では「検収 → 独立 codex-lab の I レビュー」に進む。
   - 成果物の置き場所は `experiments/c0_trm/out/`（`weights/` は現時点で空）。
2. **fast_sim（高速度シミュレーション基盤）** — 直近の依頼
   - ユーザーの依頼: 「ラズパイで実時間の中で AUE を稼働させる前に、高速度シミュレーションの準備をして」。
   - 状態: `experiments/fast_sim/fast_sim.jl`（約 10 KB）と `README.md` を作成済み。`out/` は空。
   - **Julia での実行が `failed` で止まった**（Neon の画面に "Ran … failed" とだけあり、エラーの中身は取れていない）。直接の原因は**未確認**。
   - 次の一手: `julia experiments/fast_sim/fast_sim.jl` を実行してエラーを確認し、直す。
     - ただし C0 が 8 スレッドを使っているので、**並行して重い実行をすると互いに遅くなる**。まず C0 の終了を待つか、スレッド数を絞る。
   - 守るべき制約（README の厳守事項）:
     - `G-FS-PARITY`: 高速走行・間隔つき走行・監査鎖再生の 3 者がビット一致すること。
     - S52 の 144 時間ブラインディング: 読んでよいのは `experiments/ambient/out-72h/design_72h.tsv` と `experiments/radio_confirm/out/confirm_72h.tsv` だけ。`ambient-20261123.tsv` などの未開封データは開かない。
     - `core/`、`experiments/aue_seam/`、`rust/being-*`、`rust/trm-det/`、`~/bridge-protocol` は変更しない。
     - 主列の種子 1110 は使わない（専用の 690001 を使う）。
     - `phenomenal_claim = :not_certified` は固定。
   - 計画: C0 の重みが確定したら、同じシナリオに TRM 予測器を挿し込んで再審査する。

## 直近のユーザー決定（`user-decisions.md` 末尾、2026-11-23 夜）
- U-SP1a: 種＝`species_spec.toml` の許可された認知器官型の集合。親の吸収死後に発芽する胞子は「別個体」とする。
- U-SP1b（BP11 / 仮定 H8）: 複数タイプの AUE を跨いでも AGENCY-001 述語と吸収死の定義を不変に保つ。**BP 正本への反映は BP ライン側の作業で、未実施かどうかは未確認**。
- U-SP2: 飼育と医療介入の線引きを `discussion/promise-cutout.md` §7 付則に明文化済み。

## 新しい仕切り役が最初にやること
1. `ps` で PID 73103 の C0 がまだ動いているか、`experiments/c0_trm/out/run.log` に新しい行があるかを確認する。
2. ユーザーに「未 commit のファイルを commit するか」を聞く。
3. C0 が終わってから fast_sim を実行し、エラーを直す。
4. `discussion/STATE.md` が古い。区切りが付いたら更新する。
5. ユーザーが Neon に出した最後の質問（どのモデルが制限になったか）には、本メモの冒頭で答え済み。
