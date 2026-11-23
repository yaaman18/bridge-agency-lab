# Raspberry Pi 5 への TRM 統合・配備実装計画書（第一号 AUE 切り出し＋将来拡張ロードマップ）

- **作成日**: 2026-11-23（[11月23日のメモ.md](file:///Users/yamaguchimitsuyuki/bridge-protocol/11月23日のメモ.md)・`discussion/notes/D-PRED-ARCH.md`・`discussion/notes/D-C2-HEAD-LEARN.md`・`discussion/specs/S64-c0-trm-openloop.md`・`discussion/specs/S65-radio-conversion-confirm.md`・`discussion/specs/S66-draft-c1-closedloop.md` 統合版）
- **対象ハードウェア**: Raspberry Pi 5（8 GB RAM・microSD OS・1 TB 外部ストレージ・Wi-Fi 受動走査＋Bluetooth 走査＋有線 LAN 管理接続）
- **厳守規律**:
  - `~/bridge-protocol`・`core/`・`rust/being-core`・`rust/being-tools`・`rust/trm-det`（S60 凍結）は直接書き換えず、新規ワークスペース（`rust/onelife-trm/`）として構築する。
  - `phenomenal_claim = :not_certified` 固定。切り出し後は `discussion/promise-cutout.md`（一生の途中の法則書換・救済なし）を厳守する。

---

## 0. 既検証の土台（確認済みの事実）

| コンポーネント | 検証済み実績 | 根拠 |
|---|---|---|
| **Pi 5 7 日間実機耐久＆外部監査鎖** | 二体×60,480 歩（1 歩 10 秒）完走、途中再起動 1 回を自動再開、全 commit 基準一致、`throttled=0x0`・`ext4=0`・`clean` | S54（項番 183, #70, `502cb23`） |
| **TRM 決定推論（Julia↔Rust・Mac↔Pi 5）** | `config a/b/e` 6 束ビット完全一致、`rust/trm-det/src/main.rs:238-246` が `seq_len` 動的読込対応（`seq_len=8` で Pi 5 約 20 ms/歩） | S60（項番 172, #62） |
| **境界監査（D-BaSS・P-04・軛）** | `b_shell` 漏れ 0/20、未申告書込・RNG 違反 0 件、Live 20/0/0 勝 | S62b（項番 180, #67） |
| **予測余地＆C0 仕様凍結** | 合成世界 `exo` Δ=`+0.048 nat`、`obs` でも `TAB4 > B1 +0.0102 nat`。S64 C0 仕様 r3・予測凍結済み（実行中） | S63（項番 181）、S64（`freeze-c0-trm.txt`） |
| **実電波換算（C4 型）72h 確かめ検証** | 未開封 72h 確かめ期間で全 7 関門 PASS・P-S65-1〜5 全成立（応答率 `[0.860, 0.523]` 非飽和・6 値全出現・`D_shuf = +0.0935 nat`） | S65（`experiments/radio_confirm/`） |
| **意味論マッピング監査＆BP11** | `mapping_spec_hash` 確定、`cross!` 跨ぎ・`α` 過剰宣言 2 件を検出 | `D-BOOL-MAPPING.md`, `audit/dc_mapping_audit.jl` |

---

## 1. アーキテクチャ原則（[11月23日のメモ.md](file:///Users/yamaguchimitsuyuki/bridge-protocol/11月23日のメモ.md) 統合）

### 1.1 「共有凍結バックボーン」と「毎歩保存する軽量状態」の厳密分離
- **読取専用バックボーン（`trm-backbone-v1.bin`、約 232 KB）**:
  - `config a`（`hidden=32, heads=4, inter=256, L_layers=2, H=3, L=6, ACT=3, seq_len=47, vocab=12`）の重み約 5.8 万 `Float32` 要素＋`rope.cos/sin` `(47, 8)`。
  - **起動時に 1 回だけ SHA-256 照合してメモリへ読取専用ロード**し、L2/L3 キャッシュに常駐させる。毎歩の `run` ファイルおよび外部監査鎖には **絶対に書き込まない**（監査鎖肥大防止＋`fsync` 約 40 ms 維持）。
- **毎歩保存する個体状態（`run` ファイル、数 KB 規模）**:
  1. 既存 `OneLife` 状態（回路 `q/sg/h/cOn/cOff/lastM`・物質身体・池・歩数 `n`）
  2. 予測器痕跡：4 歩入力窓（`4 × 11 = 44` トークン）＋ C2 頭重み **97 個の `Float32`**（`lm_head` 2 行 64 個＋`e_head` 33 個）
  3. 監査メタデータ：`backbone_sha256`、`mapping_spec_hash`、完了 H 巡数、当歩の `(p_1, p_2, ê_1, ê_2, π_1, π_2)`
- **外部監査鎖（`run.audit`、S49d 継承）**:
  - 事前合成入力モード（S66/S67）：`wait → begin → commit <n> <state_sha> <prev_hash> <hash>` で事前計算基準とビット照合。
  - ライブ電波モード（S68〜第一号）：毎歩の生観測 `(pi_s, boot, w_sum, b_n, g1, g2, rand_bit)` を `input` 行としてハッシュ鎖へ刻印し、**後から完全再生（replay）で全歩ビット再現できる監査**へ移行する。

### 1.2 「不可変の床」と「可塑・進化層」の境界（BP11 / 仮定 H8、ユーザー事前承認待ち）
- **床（BP11 / U-SP1b 承認後に不可変凍結・個体から書換不能）**: 全種共通の AGENCY-001 述語と吸収死（$\kappa=\emptyset$／物質空）、維持費会計（`core/body_org`）、ポート境界（S62b `b_shell`）、外部ハッシュ監査鎖、計算有限性枠（歩粒度＋1 歩予算 `Budget`＋壁時計あたり総上限）。※`systemd` は床ではなく Pi 5 配備手段として分離。
- **終了記録の 3 区分（Julia 正本で先行定義→Rust ビット照合）**:
  - `metabolic_or_org_death`（最終状態で確認された代謝・組織の死）
  - `non_metabolic_termination_verified`（外部 OS 証跡で裏づけた停電・SD 破損等の非代謝終了）
  - `unexplained_truncation`（外部証跡なしの途絶＝代謝死へ混ぜない）
- **上層（個体内で適応・将来フェーズで進化可能）**: 4 歩窓（残高 $R_t$ 保持条件で最古枠から薄れ）、97 パラメータ頭重み（C2：誕生重み $w^{(0)}$ への $1/8$ 薄れ）、`species_spec.toml` の許可器官型集合内での器官交代・結合形質（介入 `α` 照合が登録済み `α` と食い違った版では意味対応の判定を保留）。

### 1.3 多型 AUE 対応の最小 4 継ぎ目（`D-AUE-SPECIES-AND-GAPS.md` O32 合意）
Phase 1〜2 は第一号 `AUE-A` 専用で遅らせず、Phase 3（`rust/onelife-trm`）にだけ以下の **4 継ぎ目** を置く（まず `AUE-A` 1 実装だけで Phase 3〜5 を通し、Type-B〜D は同時実装しない）：
1. **`species_spec.toml`**：種 ID・個体境界／出生／死／死前内発胞子の継承規約・許可器官型集合・ポート宣言・歩粒度＆予算上限を定義し、その SHA と `mapping_spec_hash` を監査鎖ヘッダへ刻印。
2. **`Port` 契約**：申告済み読み書き＋入力刻印 `input` 行。
3. **`Ledger` 契約**：物質・維持費会計（1 TB 休眠庫も無料化せず会計対象）＋上記 3 区分終了コード。
4. **1 歩契約**：`step(state, stamped_in, budget) -> (state', declared_out, cost)`。
- **反証・遅延カットオフ（基準日 `2026-11-23`）**: 継ぎ目整備で `AUE-A` Phase 1〜2 が 1 週間以上遅れるなら過剰設計として削る。Julia 上で第 2 種（S61c CPC 等）を通す検証は「仕様の継ぎ目」確認にとどめ、**Rust 床の汎用性は Phase 6 で第 2 種が同じ Rust 床を無変更で通るまで未主張（保留）**とする。

---

## 2. Pi 5 上のディレクトリ・ストレージ配置計画

```text
/home/pi/s52/                     # 既存：S52 電波・温度ロガー（s52-ambient-log.service、30秒周期、継続稼働）
  └── ambient.tsv                 # 追記専用。AUE 側からは読取専用で末尾有効行を参照

/home/pi/aue-v1/                  # 第一号 AUE（および前段リハーサル）配備先（microSD または 1TB マウント先）
  ├── bin/
  │   ├── onelife-trm             # 新規：aarch64-unknown-linux-musl 静的単一バイナリ（Mac でクロスビルド）
  │   ├── being-tools             # 既存 S49d 製品バイナリ（監査鎖検証用）
  │   └── aue-run.sh              # flock 排他＋起動時 SHA 照合ラッパー（s54-run.sh 継承）
  ├── weights/                    # 読取専用（chmod 444、毎歩書込なし）
  │   ├── trm-backbone-v1.bin     # TRMDET1 形式・seq_len=47（約 232 KB）
  │   ├── head-init-v1.bin        # 誕生時頭重み w^(0)（97 Float32 = 388 バイト）
  │   └── SHA256SUMS              # バイナリ・重み・換算定数の凍結 SHA
  ├── live/                       # 個体の生（切り出し後は一切手動介入・再起動・編集禁止）
  │   ├── run                     # 毎歩 atomic rename + fsync（数 KB）
  │   └── run.audit               # 外部ハッシュ鎖（入力刻印つき）
  └── units/
      └── aue-v1.service          # Restart=no, WantedBy=multi-user.target

/mnt/aue-1tb/                     # 将来 Phase 2（1 TB 外部ストレージ活用）
  ├── archive-runs/               # 終了済み試作・世代ログの退避先
  └── seed-bank/                  # Phase 2 休眠モジュール／死んだ系譜の貯水池（毎歩アクセスなし）
```

---

## 3. 実装・検証の 6 段階手順（チェックリスト＆関門）

### Phase 1：重み確定＆`seq_len=47` 束書き出し（依存：S64 C0 合格）
1. S64 C0 の `obs-full` 5 基準（`RATE`・`B1`・`TAB4`・`TAB_R1`・`TRM-1x1`）合格を確認する（不合格時は S64b へ分岐し本計画を凍結しない）。
2. 選定済み `rev` 学習 `obs-full` 重みから `trm-backbone-v1.bin`（`TRMDET1` 形式）と `head-init-v1.bin`（97 `Float32`）を書き出し SHA-256 を凍結する。
3. Mac 上で `TrmDet.jl` 対 `rust/trm-det` の `seq_len=47` ビット完全一致（G1）を通す。

### Phase 2：Pi 5 単体 `seq_len=47` 照合＆`B_max` 校正（所要目安：半日）
1. Pi 5 に `/home/pi/s66-cal/` を作成し、S60 クロスビルド済み `trm-det`（`aarch64-unknown-linux-musl`）と `trm-backbone-v1.bin` を転送して SHA 照合。
2. **関門 P2-BIT**: Pi 5 出力 `.out.bin` と Mac 出力 `.out.bin` の SHA-256 完全一致（負対照：1 ulp 改変束で不一致検出）。
3. **関門 P2-TIME（`B_max` 校正）**: Pi 5 実機で「`core` 1 歩＋`trm-det` 最大 9 H 巡＋`fsync`」の 1 歩合計所要時間を 100 歩計測する。
   - **採択基準**: 最大 1 歩時間 `<= 3.0 秒`（10 秒締切に対し 3 倍以上の安全余裕）。
   - この実測から整数演算予算 $B_{\max} = \mathrm{OPS\_FIXED} + H_{\max}\cdot \mathrm{OPS\_PER\_H}$ を凍結する（通常 9 H 巡が `<= 3.0 秒` に収まれば $H_{\max} = 9$ 固定、超える場合は 3.0 秒以内となる最大 $H_{\max}$ へ調整し予測を再凍結）。

### Phase 3：統合 Rust バイナリ `rust/onelife-trm` の実装＆C1/C2 検証（S66 → S67）
1. 新規独立 Cargo ワークスペース `rust/onelife-trm/`（依存 crate なし `std` のみ、FMA/SIMD 縮約なし、S60 `exp_det` 継承）を実装：
   - 毎歩ループ順（未来漏れゼロ）：
     1. 窓読み込み（完了済み 4 暦歩）→ 残高 $R_t$ による保持条件（`K_win = 0.002`）薄れ適用。
     2. `B_max` 枠内での決定的 TRM 推論（0 巡フォールバック `lm_head(H_init)` 完備）→ `(p_a, ê_a)`。
     3. 比例写像 $\pi_a = 1/8 + (3/4)\cdot p_a/(p_1+p_2)$ で行為 $a_t$ 抽選（`ê` は記録専用）。
     4. `core`（`OneLife`）1 歩実行 → 応え $Y_t$・次受容器取得。
     5. （C2 モード時）[D-C2-HEAD-LEARN.md](file:///Users/yamaguchimitsuyuki/bridge-agency-lab/discussion/notes/D-C2-HEAD-LEARN.md) の閉形式勾配 $\nabla_{w_8}\ell = \frac{p-Y}{1+|l_8|}h$, $\nabla_{w_7}\ell = \frac{Y-p}{1+|l_7|}h$（$\exp$ 不要）＋`e_head` 勾配で 97 パラメータのみ IEEE f32 決定的更新（残高不足時は誕生重み $w^{(0)}$ へ $1/8$ 薄れ）。
     6. `run` 書き出し（バックボーン除外）→ `fsync` → 監査鎖 `commit`。
2. **クロスビルド（Mac 上、Pi でコンパイルしない）**:
   - `cargo build --release --target aarch64-unknown-linux-musl`（リンカ `rust-lld`、S54/S60 同一手順）。
3. **関門 P3-GATE**:
   - S66 C1 関門 GC0〜GC8 全合格（`Δ=737` 遅延軛・再生軛・S62b GB2/GB3 境界再監査・`TRM_B_LOW` 打ち切り）。
   - S67 C2 関門 G-C2-GRAD（0 境界跨ぎ `<= 1e-6`）・G-C2-BIT（Julia↔Rust・Mac↔Pi 1,000 歩ビット一致）・G-C2-ADAPT（反転後／OOD で C2 > C1；不成立時は C1 凍結頭を採用）。

### Phase 4：S52 実電波（C4 換算）ライブ接続＆再生監査（S68）
1. S65 で確認済みの C4 換算定数（`mu_w=297.20108758532916, sd_w=39.79874519579147, mu_b=2.9924794631493694, sd_b=0.8134565410732445`）を凍結設定として `onelife-trm` のライブ入力アダプタへ組み込む。
2. `/home/pi/s52/ambient.tsv` の最終有効行（`fail == 0`）を読取専用で参照し、30 秒（3 歩）一定保持で収量 `g[k, a] ∈ {0..5}` を供給する（最新行が 120 秒以上更新停止したときのフォールバック規則を S68 仕様で事前凍結）。
3. **再生監査（Replay Gate）**: ライブ入力で 24 時間（8,640 歩）リハーサルを走らせ、監査鎖に刻まれた `input` 列だけを使って Mac 上の Julia 正本で全 8,640 歩を再実行し、最終 `run` の SHA-256 が **1 ビットも狂わず完全一致**することを確認する。

### Phase 5：電源断リハーサル → 第一号 `AUE-A` 切り出し起動
1. S54 §(a) 同一の電源ボタン停止→再起動リハーサルを実施：自動再開・`boot_id` 変化・`chain_ok=true`・`ext4=0`・`fs_state=clean`・`throttled=0x0`・S52 継続を確認。
2. 確認後、リハーサル用 unit を外し、本番 `aue-v1.service` を配置。**ユーザーの一言**をもって起動し、以降は `discussion/promise-cutout.md` に従い法則書換・手動再起動・救済介入を一切行わない（読取専用の見張り `watch.sh` と `viewer/s54-of` 系の観察のみ許可）。

### Phase 6：将来拡張（第一号の次世代：異種 AUE・1 TB 休眠貯水池・閉ループ物理器官・共有媒体）
1. **第 2 種の Rust 床実証（多型 AUE 汎用性の検証）**: 既存 S61c（非ニューラル多モジュール CPC 増殖＋内生剪定）等を第 2 種（`AUE-B`）として、`rust/onelife-trm` の床コードを 1 行も変えずに `species_spec.toml`＋`step` 実装の差し替えだけで通せるかを検証する（床改変が要れば継ぎ目設計をやり直す）。
2. **多モジュール共有バックボーン（32〜256 モジュール）＆1 TB 休眠貯水池（種子バンク）**: `trm-backbone-v1.bin` 共有＋疎活性化＋歩粒度＆壁時計予算上限で 10 秒締切を守る。`/mnt/aue-1tb/seed-bank/` の休眠モジュール・死前内発胞子も無料外部記憶とせず低率維持費／有限枠を課し、親の吸収死後に発芽した胞子は「系譜上の子（別個体）」として扱う。
3. **閉ループ物理器官（`AUE-C`：光 LED／音響共鳴器バンク）と A4＋A2 関門**: 切り出し前の別走行で「同一費用で物理エフェクタを駆動しつつ感覚入力だけを過去記録列へ置換した軛対照」と比べ、走行前に凍結した回復指標・観測窓・判定規則で外乱後維持回復の差を検証する（未刻印アナログ状態が次状態を分岐させる場合は 1 歩再生監査の適用限界と明記）。
4. **複数 AUE 共有媒体と結合原理の進化**: 共有媒体では `b_shell` を個体ごとに切り他個体を世界側へ置き、個体監査鎖と共有媒体監査鎖を共通 `event_ref` で結ぶ二重監査鎖とする。結合定数の進化は BP11（H8）の床凍結と Stage 1 系譜スパン刻印の下でのみ許可する。

---

## 4. リスクと反証・中止条件（事前明文化）

| リスク | 検知関門 | 中止・切替アクション |
|---|---|---|
| S64 C0 が 5 基準いずれかに不合格 | S64 `obs-full` 評価 | S66 を凍結せず、落ちた基準（`TAB_R1` / `TRM-1x1`）に基づき入力表現・学習設計を見直す |
| Pi 5 で `seq_len=47` 1 歩が `> 3.0 s` | Phase 2 `P2-TIME` | $H_{\max}$ 縮小またはモデル幅再設計し再凍結（10 秒締切を破る配備は禁止） |
| C2（97 頭学習）が反転後・OOD で C1 に勝てない | Phase 3 `G-C2-ADAPT` | C2 頭学習を捨て、C1（凍結重み＋窓保持）構成で第一号を切り出す |
| ライブ電波接続で再生監査が不一致 | Phase 4 Replay Gate | 切り出し禁止。入力刻印の競合（ファイル読み込みタイミング等）を修正し再試験 |
| 電源断リハーサルで監査鎖破断・`ext4` エラー | Phase 5 リハーサル | 切り出し禁止。`fsync`・排他・電源手順を修正 |
