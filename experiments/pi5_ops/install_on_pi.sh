#!/bin/sh
# Idempotent installer for Pi 5 network self-recovery, hardware watchdog, and kernel-panic auto-reboot.
# Does NOT modify or restart s52-ambient-log or any AUE service.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
PI_CONN="${DIR}/pi-connect.sh"

TARGET="$(sh "$PI_CONN" --probe-only | awk '{for(i=1;i<=NF;i++) if($i ~ /^target=/){sub("^target=","",$i); print $i}}')"
echo "Resolved Pi target: ${TARGET}"

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o HostKeyAlias=bridge-pi.local"

# Stage into /tmp/aue-pi5-ops on Pi, then install atomically with sudo -n
# shellcheck disable=SC2086
ssh $SSH_OPTS "pi@${TARGET}" "mkdir -p /tmp/aue-pi5-ops"
# shellcheck disable=SC2086
scp $SSH_OPTS \
    "${DIR}/aue-net-recover.sh" \
    "${DIR}/aue-net-recover.service" \
    "${DIR}/aue-net-recover.timer" \
    "${DIR}/99-aue-watchdog.conf" \
    "${DIR}/99-aue-panic.conf" \
    "pi@${TARGET}:/tmp/aue-pi5-ops/"

# shellcheck disable=SC2086
ssh $SSH_OPTS "pi@${TARGET}" 'set -eu
sudo -n install -m 0755 /tmp/aue-pi5-ops/aue-net-recover.sh /usr/local/sbin/aue-net-recover.sh
sudo -n install -m 0644 /tmp/aue-pi5-ops/aue-net-recover.service /etc/systemd/system/aue-net-recover.service
sudo -n install -m 0644 /tmp/aue-pi5-ops/aue-net-recover.timer /etc/systemd/system/aue-net-recover.timer
sudo -n mkdir -p /etc/systemd/system.conf.d
sudo -n install -m 0644 /tmp/aue-pi5-ops/99-aue-watchdog.conf /etc/systemd/system.conf.d/99-aue-watchdog.conf
sudo -n install -m 0644 /tmp/aue-pi5-ops/99-aue-panic.conf /etc/sysctl.d/99-aue-panic.conf
sudo -n /usr/sbin/sysctl -p /etc/sysctl.d/99-aue-panic.conf
sudo -n systemctl daemon-reload
sudo -n systemctl enable --now aue-net-recover.timer
sudo -n systemctl start aue-net-recover.service
rm -rf /tmp/aue-pi5-ops
echo "=== VERIFY ==="
echo "kernel.panic=$(cat /proc/sys/kernel/panic) kernel.panic_on_oops=$(cat /proc/sys/kernel/panic_on_oops)"
systemctl show --property=WatchdogDevice,RuntimeWatchdogUSec,RebootWatchdogUSec
systemctl is-active avahi-daemon.service aue-net-recover.timer s52-ambient-log.service
systemctl is-enabled aue-net-recover.timer s52-ambient-log.service
'
