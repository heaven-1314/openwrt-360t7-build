#!/bin/bash
# patch-kernel.sh — Patch kernel config for BTF + full BPF support
# CRITICAL: CONFIG_DEBUG_INFO=y is required for CONFIG_DEBUG_INFO_BTF=y
set -euo pipefail

cd "$(dirname "$0")/.."
OPENWRT_DIR="${1:-openwrt}"
[ -d "$OPENWRT_DIR" ] && cd "$OPENWRT_DIR" || { echo "Must run from project root or pass openwrt dir"; exit 1; }

# ── Detect kernel version from config filenames ──
KVER=""
for f in target/linux/generic/config-*; do
  v=$(basename "$f" | sed 's/config-//')
  if [ -z "$KVER" ] || [ "$(printf '%s\n%s\n' "$KVER" "$v" | sort -V | tail -1)" = "$v" ]; then
    KVER="$v"
  fi
done
echo "Detected kernel config version: $KVER"

GENERIC_CONFIG="target/linux/generic/config-${KVER}"
TARGET_CONFIG="target/linux/mediatek/config-${KVER}"

set_opt() {
  local f="$1" opt="$2" val="$3"
  [ -f "$f" ] || touch "$f"
  sed -i "/^${opt}[= ]/d; /^# ${opt} is not set/d" "$f"
  echo "${opt}=${val}" >> "$f"
  echo "  ✓ ${opt}=${val} → ${f}"
}

echo ""
echo "=== DEBUG INFO (required for BTF) ==="
set_opt "$GENERIC_CONFIG" "CONFIG_DEBUG_INFO" "y"
set_opt "$GENERIC_CONFIG" "CONFIG_DEBUG_INFO_REDUCED" "y"

echo ""
echo "=== BTF ==="
set_opt "$GENERIC_CONFIG" "CONFIG_DEBUG_INFO_BTF" "y"
set_opt "$GENERIC_CONFIG" "CONFIG_DEBUG_INFO_BTF_MODULES" "y"

echo ""
echo "=== BPF core ==="
set_opt "$GENERIC_CONFIG" "CONFIG_BPF" "y"
set_opt "$GENERIC_CONFIG" "CONFIG_BPF_SYSCALL" "y"
set_opt "$GENERIC_CONFIG" "CONFIG_BPF_JIT" "y"
set_opt "$GENERIC_CONFIG" "CONFIG_BPF_JIT_ALWAYS_ON" "y"

echo ""
echo "=== BPF features ==="
set_opt "$GENERIC_CONFIG" "CONFIG_BPF_EVENTS" "y"
set_opt "$GENERIC_CONFIG" "CONFIG_BPF_STREAM_PARSER" "y"
set_opt "$GENERIC_CONFIG" "CONFIG_CGROUP_BPF" "y"

echo ""
echo "=== Networking BPF ==="
set_opt "$GENERIC_CONFIG" "CONFIG_NET_CLS_BPF" "m"
set_opt "$GENERIC_CONFIG" "CONFIG_NET_ACT_BPF" "m"
set_opt "$GENERIC_CONFIG" "CONFIG_NET_SCH_INGRESS" "m"

echo ""
echo "=== XDP + veth ==="
set_opt "$GENERIC_CONFIG" "CONFIG_XDP_SOCKETS" "y"
set_opt "$GENERIC_CONFIG" "CONFIG_XDP_SOCKETS_DIAG" "m"
set_opt "$GENERIC_CONFIG" "CONFIG_VETH" "m"

echo ""
echo "=== Done — BTF + BPF fully configured ==="
