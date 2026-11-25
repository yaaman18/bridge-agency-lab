#!/bin/sh
# Mac-side resilient SSH wrapper for Raspberry Pi 5 (`bridge-pi`).
# Automatically falls back when mDNS (`bridge-pi.local`) fails:
#   1) pi@bridge-pi.local (mDNS)
#   2) MAC-derived IPv6 link-local (fe80::da3a:ddff:fef4:474d%<active enX>)
#   3) cached IPv4 link-local (default 169.254.102.224)
#
# Usage:
#   sh experiments/pi5_ops/pi-connect.sh [--wait [max_sec]] [--probe-only] [-- <remote command...>]
set -eu

USER_NAME="pi"
HOST_ALIAS="bridge-pi.local"
PI_IPV6_LL="fe80::da3a:ddff:fef4:474d"
CACHE_DIR="${TMPDIR:-/tmp}"
CACHE_IPV4="${CACHE_DIR}/bridge-pi-last-ipv4.txt"
DEFAULT_IPV4="169.254.102.224"

WAIT_MODE=0
MAX_WAIT=300
PROBE_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --wait)
            WAIT_MODE=1
            shift
            if [ $# -gt 0 ]; then
                case "$1" in
                    [0-9]*) MAX_WAIT="$1"; shift ;;
                esac
            fi
            ;;
        --probe-only)
            PROBE_ONLY=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=4 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o HostKeyAlias=${HOST_ALIAS}"

# Discover active Mac en* interfaces that hold a 169.254.x.x link-local address first, then other active en*
list_en_ifaces() {
    ifconfig | awk '
        /^en[0-9]+:/ { sub(":", "", $1); cur=$1; ll=0; act=0 }
        /inet 169\.254\./ { ll=1 }
        /status: active/ { act=1; if (ll) print "0 " cur; else print "1 " cur }
    ' | sort | awk '{print $2}'
}

probe_target() {
    target="$1"
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "${USER_NAME}@${target}" "ip -4 -o addr show dev eth0 scope link 2>/dev/null | awk '{print \$4}' | cut -d/ -f1 | head -n 1" 2>/dev/null
}

find_live_target() {
    # 1. mDNS
    if ip_out="$(probe_target "$HOST_ALIAS")"; then
        [ -n "$ip_out" ] && printf '%s\n' "$ip_out" > "$CACHE_IPV4"
        printf '%s\n' "$HOST_ALIAS"
        return 0
    fi
    # 2. Burned-in MAC EUI-64 IPv6 link-local across active Mac Ethernet interfaces (hardware-constant & fastest)
    for ifc in $(list_en_ifaces); do
        cand_v6="${PI_IPV6_LL}%${ifc}"
        if ip_out="$(probe_target "$cand_v6")"; then
            [ -n "$ip_out" ] && printf '%s\n' "$ip_out" > "$CACHE_IPV4"
            printf '%s\n' "$cand_v6"
            return 0
        fi
    done
    # 3. Cached or default IPv4 link-local
    cand_v4="$DEFAULT_IPV4"
    [ -r "$CACHE_IPV4" ] && cand_v4="$(cat "$CACHE_IPV4" 2>/dev/null || echo "$DEFAULT_IPV4")"
    if [ -n "$cand_v4" ]; then
        if ip_out="$(probe_target "$cand_v4")"; then
            [ -n "$ip_out" ] && printf '%s\n' "$ip_out" > "$CACHE_IPV4"
            printf '%s\n' "$cand_v4"
            return 0
        fi
    fi
    return 1
}

elapsed=0
backoff=2
TARGET=""
while true; do
    if TARGET="$(find_live_target)"; then
        break
    fi
    if [ "$WAIT_MODE" -eq 0 ] || [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "ERROR: bridge-pi unreachable via mDNS, IPv4 link-local, and IPv6 link-local (elapsed=${elapsed}s)" >&2
        exit 1
    fi
    echo "waiting for bridge-pi... retry in ${backoff}s (elapsed=${elapsed}s/${MAX_WAIT}s)" >&2
    sleep "$backoff"
    elapsed=$((elapsed + backoff))
    backoff=$((backoff * 2))
    [ "$backoff" -gt 15 ] && backoff=15
done

if [ "$PROBE_ONLY" -eq 1 ]; then
    echo "OK target=${TARGET} cached_ipv4=$(cat "$CACHE_IPV4" 2>/dev/null || echo none)"
    exit 0
fi

# shellcheck disable=SC2086
exec ssh $SSH_OPTS "${USER_NAME}@${TARGET}" "$@"
