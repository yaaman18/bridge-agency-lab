# `experiments/pi5_ops/` — Raspberry Pi 5 通信断リカバリ＆自動リブート基盤（2026-11-23）

- **位置づけ**: [promise-cutout.md](../../discussion/promise-cutout.md) §7 付則（U-SP2：「飼育＝電源・配線・冷却・インフラ維持」対「医療介入＝個体の法則・内部書換」）および [D-POWER.md](../../discussion/notes/D-POWER.md)（microSD 保護）に完全準拠した、Pi 5 インフラ層の自動復旧パッケージ。
- **厳守事項**:
  - `s52-ambient-log.service` や将来の `aue-v1.service`（`Restart=no` 維持）の内部状態・起動停止には一切介入しない。
  - 定期ログは RAM（`/run/aue-net-recover.log`）のみへ書き、microSD 書き込み摩耗を増やさない。
  - `core/`・`rust/`・`~/bridge-protocol` 無変更、`phenomenal_claim = :not_certified`。

## 1. Mac ↔ Pi 5 通信断リカバリ（二段構え）
1. **Pi 側（`aue-net-recover.sh` ＋ `aue-net-recover.timer`、30 秒周期）**:
   - `avahi-daemon` 停止時に自動再起動（mDNS `bridge-pi.local` 復旧）。
   - `eth0` キャリアありで IPv4 リンクローカル欠落時に `nmcli con up netplan-eth0` で再確立＋`avahi-daemon` 再広告。
   - Mac 切断・スリープ等で勝手に Pi を再起動しない（無用な `boot_id` 増加防止）。
2. **Mac 側（`pi-connect.sh`）**:
   - mDNS (`bridge-pi.local`) が死んでも **① mDNS → ② Pi 5 固定 MAC 由来 IPv6 リンクローカル (`fe80::da3a:ddff:fef4:474d%<enX>`) → ③ キャッシュ IPv4 (`169.254.102.224`)** へ自動フォールバックし、`--wait` で指数バックオフ自動復帰待機が可能。
   - **実機障害試験で確認した事実（2026-11-23 23:57 JST）**: `avahi-daemon` 停止中に `pi-connect.sh` が即座に `fe80::da3a:ddff:fef4:474d%en7` へフォールバック接続 → Pi 側 `aue-net-recover.timer` が `avahi-daemon` を自動再起動（`/run/aue-net-recover.log` に記録、microSD 書込 0）→ `bridge-pi.local` が自動復帰、全期間で `s52-ambient-log.service`（`MainPID=1023`）無影響を確認。`RuntimeWatchdogUSec=15s`・`RebootWatchdogUSec=2min`・`kernel.panic=10`・`kernel.panic_on_oops=1` 反映確認済み。

## 2. 電源断・OS フリーズ時の自動リブート＆自動再開
1. **停電→復電時の自動起動（ハードウェア EEPROM）**:
   - Pi 5 EEPROM 確認済み（`BOOT_ORDER=0xf461`, `POWER_OFF_ON_HALT=0`）。AC 電源（USB-C PD）が断→再通電されると自動でコールドブートし、`WantedBy=multi-user.target` の全常駐（`s52-ambient-log`・`aue-net-recover.timer`・将来の `aue-v1`）が人手なしで自動再開する。
2. **OS ハング時のハードウェアウォッチドッグ自動リブート（`99-aue-watchdog.conf`）**:
   - BCM2712 `/dev/watchdog0` に対し `RuntimeWatchdogSec=15s`・`RebootWatchdogSec=2min` を設定。OS / PID 1 フリーズ時に 15 秒以内でハードウェアが強制自動リブート。
3. **カーネルパニック／Oops 自動リブート（`99-aue-panic.conf`）**:
   - `kernel.panic = 10`・`kernel.panic_on_oops = 1` を永続化（既定 `0/0` の永久停止を解消）。

## 3. 物理的限界（正直な明記）
- AC 電源そのものが切れたまま（無通電）の状態から自力で起動することは物理的に不可能であり、復電（または外部 UPS／スマートプラグ）が必要。
- 電源ボタン短押し等で正常停止した直後に通電したままの状態からは、ボタン再押下または電源再投入が必要。
- `D-POWER.md` 方針に従い、microSD 保護のため「稼働中の電源引き抜き試験」「意図的カーネルパニック試験」は行わず、設定反映・`systemctl show`・`avahi-daemon` 停止→自動復旧・Mac 側 mDNS バイパス接続試験で検証する。
