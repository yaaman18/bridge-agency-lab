#!/bin/sh
# Pi 5 network self-recovery script (infrastructure / husbandry layer only).
# Strictly does NOT touch AUE or S52 services (`promise-cutout.md` §7).
# Writes logs to `/run/aue-net-recover.log` (tmpfs/RAM) to cause 0 microSD wear.
set -eu

LOG="/run/aue-net-recover.log"
STATE_IP="/run/aue-net-recover.last_ip"
IFACE="eth0"
CON="netplan-eth0"

log() {
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s %s\n' "$ts" "$1" >> "$LOG"
    # Keep RAM log bounded to last 200 lines
    if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 250 ]; then
        tail -n 200 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
    fi
}

# 1. Ensure avahi-daemon (mDNS for bridge-pi.local) is active
if ! systemctl is-active --quiet avahi-daemon.service; then
    log "avahi-daemon inactive -> restarting"
    systemctl restart avahi-daemon.service || log "WARN: avahi-daemon restart failed"
fi

# 2. Check Ethernet carrier (cable connected)
carrier="0"
if [ -r "/sys/class/net/${IFACE}/carrier" ]; then
    carrier="$(cat "/sys/class/net/${IFACE}/carrier" 2>/dev/null || echo 0)"
fi

if [ "$carrier" = "1" ]; then
    cur_ip="$(ip -4 -o addr show dev "$IFACE" scope link 2>/dev/null | awk '{print $4}' | head -n 1 || true)"
    if [ -z "$cur_ip" ]; then
        log "carrier=1 but no IPv4 link-local on ${IFACE} -> nmcli con up ${CON}"
        nmcli -w 10 con up "$CON" >/dev/null 2>&1 || log "WARN: nmcli con up ${CON} failed"
        cur_ip="$(ip -4 -o addr show dev "$IFACE" scope link 2>/dev/null | awk '{print $4}' | head -n 1 || true)"
        if [ -n "$cur_ip" ]; then
            log "recovered IPv4 link-local ${cur_ip} -> restarting avahi-daemon"
            systemctl restart avahi-daemon.service || true
        fi
    fi

    # If link-local IPv4 changed, refresh avahi mDNS advertisement immediately
    prev_ip=""
    [ -r "$STATE_IP" ] && prev_ip="$(cat "$STATE_IP" 2>/dev/null || true)"
    if [ -n "$cur_ip" ] && [ "$cur_ip" != "$prev_ip" ]; then
        printf '%s\n' "$cur_ip" > "$STATE_IP"
        if [ -n "$prev_ip" ]; then
            log "IPv4 changed ${prev_ip} -> ${cur_ip}; refreshing avahi-daemon"
            systemctl restart avahi-daemon.service || true
        fi
    fi
fi
