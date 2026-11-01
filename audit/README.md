# audit/ — bridge-protocol との連動による自動監査

2026-10-31 のユーザー指示（「D1〜D6 を決める前に、Bridge Protocol とこのアプリを連動させて、プログラムらしく自動監査させるべきでは」）で作った。
対象はアプリ（記憶する回路）の存在で、読むだけで、どこにも書き戻さない。

## 回し方
1. アプリの db から存在の記録を読む（Claude が ArtifactData の get を使う。collection は `being`、doc は `state`、out_dir は `audit/in`）。
   読んだ記録は `audit/in/state-v<版>.json` に置く。
2. `sh audit/run.sh audit/in/state-v<版>.json` を実行する（約1分）。報告は `audit/reports/<日時>-v<版>.{md,json}` に出る。

## 監査の中身（D1〜D6 に依存しないもの）
| 記号 | 監査 | bridge-protocol の根拠 |
|---|---|---|
| N | 監査の前後で記録がビット単位で同一か。ページの読み取り経路（スナップショット、文字、6つのパネル）を毎歩はさんでも、存在の走りが変わらないか（Rust、3000 歩） | `MetaSelection.SigmaPure`・`DiversityAuditPure` |
| M | 記録の欄が既知のものだけか。目標値・報酬に当たる名前の欄がないか。セッション記録の出来事の種類が既知のものだけか | `InternalTrace.M4a`、Lean の `m4a_circuit`（証明済み） |
| P | 報告は常に `phenomenal_claim = not_certified` を持つ | §13-5、`CertifiedUnit` |
| C | 保存された存在を、Julia の正本とアプリの Rust で 5000 歩走らせて、全値が一致するか | ラボの規律 |
| S | アダプタを読み込んでも、AgencySubstrate 自身の凍結テンプレートの判定が変わらないか | — |
| A | AGENCY-001 の判定（`tools/AgencySubstrate` の criteria.jl を変えずに使う）を、アダプタの選択ごとに出す | AGENCY-001 |

## アダプタ（`agency_adapter.jl`）の選択
アダプタは、ラボの回路を AGENCY-001 の基体として読むためのものです。以下の選択は D6 にあたり、ユーザーはまだ決めていません。
- **A1：** センサーは r1〜r11、運動は m1 を区画1、m2 を区画2 に当てる（m3 には区画がない）。
- **A2：** 結びつきの強さは `q`（確かさ）か `qsg`（確かさ＋沈殿）。
- **A3：** 死は `none`（組織の層には死がない）か `agency001`（AgencySubstrate の資源の規則を観察者の勘定として当てる）。
- **A4：** 各試行は保存された存在の写しから始める。相手（身ぶり）はいない。収量は試行の予定表どおりに与える。

criteria.jl のうち `Substrate` 型に縛られた3つの関数（alive、sensor_units、evaluate）は、bridge-protocol のソースを読み、型だけを置き換えて評価し直します。
bridge-protocol のファイルは変更しません。

| DC | 保存された存在を 2000 歩走らせ、各歩の窓で `Window.checkDC`（`core/dc.jl`、Lean の `dc_of_check` で DC の証明書になる）| ERIEC.DC、`formal/LabCircuit.lean` |
| M4b | 生きている出来事がすべて行為するか（`m4b_of_check`）。生きている出来事がなければ「空虚」と出す | D5、`SeekingTrace` |

Lean との照合は `sh audit/dc_lean.sh` で行う。窓を Lean の項として書き出し、Lean 自身の `checkDC` の結果を Julia の判定と比べる。

## まだ監査していないもの
- **L2（body_org）と L3・L3R（物質の構成体）：** アプリの存在では対象外（D1）。凍結の 60 歩は系の時間尺度に合わないので「測れない」と表示し、判定は D6 のラボ変種 `experiments/variant_horizon.jl`（地平 392・294・588、項番70）で行う。
