# `experiments/aue_seam/` — 多型 AUE 最小 4 継ぎ目・Julia 仕様試作（2026-11-23）

- **位置づけ**: [D-AUE-SPECIES-AND-GAPS.md](../../discussion/notes/D-AUE-SPECIES-AND-GAPS.md)（3 系統合意 O30〜O32・ユーザー承認 U-SP1a / U-SP1b / U-SP2）および [PLAN-PI5-TRM-DEPLOY.md](../../discussion/notes/PLAN-PI5-TRM-DEPLOY.md) §1.3 で定義した **最小 4 継ぎ目**（`species_spec.toml`・`Port`・`Ledger`・1 歩契約 `step_species`）が、床コード無変更のまま異なる 2 種（`AUE-A`・`AUE-B`）を通せるかを検証する Julia 試作。
- **検証範囲（厳密限定）**:
  - 本試作の合格が裏づけるのは **「Julia 上の仕様としての継ぎ目の妥当性」のみ**。
  - **Rust 床（`rust/onelife-trm`）の汎用性は未主張（保留）** であり、Phase 6 で第 2 種が同じ Rust 床を無変更で通るまで主張しない。
- **非変更対象**: `core/`・`experiments/nesting_cpc_c/`・`formal/`・`rust/`・`~/bridge-protocol` は一切変更しない。主列未使用種子 `1110` は非消費。`phenomenal_claim = :not_certified` 固定。

## ファイル構成
- `bed.jl`: 種非依存の不可変な床（`AUE-A` / `AUE-B` / `LabCore` / `NestingCPCC` 等への言及ゼロ）。4 継ぎ目＋ハッシュ鎖監査＋入力行のみからの再生検証＋共有媒体 `event_ref` 二重取得検査を実装。
- `species_aue_a.toml` / `adapter_aue_a.jl`: 第 1 種 `AUE-A`（正本 `core/LabCore.jl` OneLife L2 を無変更で包む）。
- `species_aue_b.toml` / `adapter_aue_b.jl`: 第 2 種 `AUE-B`（正本 `experiments/nesting_cpc_c/NestingCPCC.jl` S61c CPC 増殖・内生剪定／暴走対照を無変更で包む）。
- `run_seam_gates.jl`: 関門 GS1〜GS4（2 種同一床不変性・正本直接実行との一致・再生一致・負対照 8 件）を実行し `results-seam-gates.json` へ出力する。

## 実行方法
```sh
julia /Users/yamaguchimitsuyuki/bridge-agency-lab/experiments/aue_seam/run_seam_gates.jl
```
