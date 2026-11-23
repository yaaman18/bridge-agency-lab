# `experiments/pi5_p2_dryrun/` — Phase 2 `seq_len=47` Pi 5 事前実測ドライラン（2026-11-23）

- **位置づけ**: S64 C0 学習完了（重み確定）の前に、`config a`（`hidden=32, heads=4, inter=256, L_layers=2, H=3, L=6, ACT=3, seq_len=47, vocab=12`）の合成重み束（232 KB、`q_head.bias = [-2, -2]` で最悪ケース最大 9 H 巡を強制）を用いて、**`P2-BIT`（Julia == Mac Rust == Pi 5 ARM64 ビット完全一致）と `P2-TIME`（Pi 5 実機レイテンシ）** を事前実測した記録。
- **厳守事項**: 本結果は合成重みによる事前ドライランであり、本番 Phase 2（[PLAN-PI5-TRM-DEPLOY.md](../../discussion/notes/PLAN-PI5-TRM-DEPLOY.md) Phase 2）では S64 C0 の凍結学習重み束で必ず再照合・再計測する。`experiments/trm/det/`・`rust/trm-det/`・`core/`・`~/bridge-protocol` は一切変更していない。主列未使用種子 `1110` 非消費（テスト種子 `660001`）。

## 確認した事実（2026-11-23 23:49 JST、Pi 5 実機）
1. **`P2-BIT` 事前照合（3 者ビット完全一致＋1 ulp 負対照検知）**:
   - 正常束 `s47_dryrun.bin`（232 KB, SHA `f1e1bf95...36c6`）の出力 SHA-256：
     - Julia (`TrmDet.jl`): `7486cd15cd1eb8f00f696c2f77cd34f06dbd198bb4c7618c1ca07c6b62963e41`
     - Mac Rust (`rust/trm-det`): `7486cd15cd1eb8f00f696c2f77cd34f06dbd198bb4c7618c1ca07c6b62963e41`
     - Pi 5 ARM64 (`/home/pi/s66-cal/trm-det`): `7486cd15cd1eb8f00f696c2f77cd34f06dbd198bb4c7618c1ca07c6b62963e41`
   - 1 ulp 改変負対照 `s47_dryrun_1ulp.bin`（SHA `f09624ef...2d01`）の出力 SHA-256：
     - Julia / Mac / Pi 5 すべて `812c5934eea0cf5fc0d104d9784725915cfed95b490e6885393917c0a1cb24ca`（正常束と不一致、3 者間は完全一致）。
2. **`P2-TIME` 事前実測（Pi 5 ARM64、10 連続実行 = 50 ACT ステップ）**:
   - 1 ACT ステップ（3 H 巡、`seq_len=47`）：**`68.230〜68.932 ms`**（5 ステップ合計 `342.6〜343.2 ms`、ジッタ `< 0.7 ms`）。
   - 最悪ケースフル稼働（`ACT = 3` = 9 H 巡）換算：**約 `206 ms` / 歩**（`core` 1 歩＋`fsync` 約 40 ms を加えても **約 `0.25 秒` / 歩**、採択基準 `<= 3.0 秒` に対し 12 倍超、10 秒締切に対し約 40 倍の余裕）。
   - 計測直後の Pi 5 状態：`throttled=0x0`, `temp=59.8'C`。
