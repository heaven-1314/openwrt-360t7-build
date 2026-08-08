#!/bin/bash
# patch-kernel.sh — Patch ImmortalWrt kernel config for full BPF + BTF support
#
# Problem: ImmortalWrt's default MT7981 (360T7) kernel lacks:
#   1. CONFIG_DEBUG_INFO_BTF  → /sys/kernel/btf/vmlinux not created
#   2. Full BPF helper support → daed's eBPF programs rejected by verifier
#      (error: "program of this type cannot use helper bpf_get_current_task#35")
#
# This script patches both target and generic kernel configs to ensure
# daed/dae eBPF programs can be loaded successfully.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENWRT_DIR="${1:-$(pwd)}"

cd "$OPENWRT_DIR"

# Detect kernel version from target
KVER=$(grep -oP 'LINUX_VERSION-\K[0-9.]+' include/kernel-default.mk 2>/dev/null || echo "")
if [ -z "$KVER" ]; then
  # Try to detect from target config files
  KVER=$(ls target/linux/generic/config-* 2>/dev/null | grep -oP 'config-\K[0-9.]+' | sort -V | tail -1)
fi
if [ -z "$KVER" ]; then
  KVER="6.12"
  echo "WARNING: Could not detect kernel version, using default: $KVER"
fi

echo "=========================================="
echo "  Kernel version detected: $KVER"
echo "=========================================="

GENERIC_CONFIG="target/linux/generic/config-${KVER}"
TARGET_CONFIG="target/linux/mediatek/config-${KVER}"

echo "Generic config: $GENERIC_CONFIG"
echo "Target config:  $TARGET_CONFIG"

# ──────────────────────── Helper function ────────────────────────
# set_kernel_option <config_file> <option_name> <value>
set_kernel_option() {
  local config_file="$1"
  local option="$2"
  local value="$3"

  if [ ! -f "$config_file" ]; then
    echo "WARNING: $config_file not found, creating"
    touch "$config_file"
  fi

  # Remove existing entry (both =y/=m and "is not set")
  sed -i "/^${option}[= ]/d" "$config_file"
  sed -i "/^# ${option} is not set/d" "$config_file"

  # Add new value
  echo "${option}=${value}" >> "$config_file"
  echo "  ✓ ${option}=${value}"
}

# ──────────────────────── BTF Support ────────────────────────
# These are the most critical — without BTF, daed cannot load eBPF programs.
echo ""
echo "=== Patching BTF (BPF Type Format) support ==="

set_kernel_option "$GENERIC_CONFIG" "CONFIG_DEBUG_INFO" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_DEBUG_INFO_BTF" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_DEBUG_INFO_BTF_MODULES" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_DEBUG_INFO_REDUCED" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_PAHOLE_HAS_SPLIT_BTF" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_PAHOLE_VERSION" "0"  # dummy, build system fills this
# Remove the dummy if it causes issues
sed -i "/CONFIG_PAHOLE_VERSION/d" "$GENERIC_CONFIG"

# ──────────────────────── BPF Core ────────────────────────
# Full BPF subsystem — needed for eBPF program loading
echo ""
echo "=== Patching BPF core subsystem ==="

set_kernel_option "$GENERIC_CONFIG" "CONFIG_BPF" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_BPF_SYSCALL" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_BPF_JIT" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_BPF_JIT_ALWAYS_ON" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_HAVE_EBPF_JIT" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_HAVE_EBPF_JIT_ARCH" "y"

# ──────────────────────── BPF Helpers ────────────────────────
# bpf_get_current_task and related helpers
echo ""
echo "=== Patching BPF helpers and features ==="

set_kernel_option "$GENERIC_CONFIG" "CONFIG_BPF_EVENTS" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_BPF_KPROBE_OVERRIDE" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_BPF_STREAM_PARSER" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_CGROUP_BPF" "y"

# ──────────────────────── Networking BPF ────────────────────────
# TC cls_bpf, act_bpf, XDP — used by dae for traffic interception
echo ""
echo "=== Patching networking BPF ==="

set_kernel_option "$GENERIC_CONFIG" "CONFIG_NET_CLS_BPF" "m"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_NET_ACT_BPF" "m"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_NET_SCH_INGRESS" "m"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_NET_ACT_GACT" "m"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_NET_ACT_MIRRED" "m"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_NET_ACT_SKBEDIT" "m"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_NET_ACT_VLAN" "m"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_NET_CLS_FLOWER" "m"

# ──────────────────────── XDP ────────────────────────
echo ""
echo "=== Patching XDP support ==="

set_kernel_option "$GENERIC_CONFIG" "CONFIG_XDP_SOCKETS" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_XDP_SOCKETS_DIAG" "m"

# ──────────────────────── Veth ────────────────────────
echo ""
echo "=== Patching veth support ==="

set_kernel_option "$GENERIC_CONFIG" "CONFIG_VETH" "m"

# ──────────────────────── nftables TPROXY ────────────────────────
echo ""
echo "=== Patching nftables TPROXY ==="

set_kernel_option "$GENERIC_CONFIG" "CONFIG_NETFILTER_XT_TARGET_TPROXY" "m"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_NF_TABLES" "y"
set_kernel_option "$GENERIC_CONFIG" "CONFIG_NF_TABLES_INET" "y"

# ──────────────────────── Verify pahole ────────────────────────
echo ""
echo "=== Checking pahole (required for BTF generation) ==="
if command -v pahole &>/dev/null; then
  echo "  ✓ pahole $(pahole --version)"
else
  echo "  ✗ pahole NOT FOUND!"
  echo "    Install with: sudo apt-get install dwarves"
  echo "    Without pahole, BTF generation will fail!"
  exit 1
fi

# ──────────────────────── Summary ────────────────────────
echo ""
echo "=========================================="
echo "  Kernel patch complete!"
echo "=========================================="
echo ""
echo "Key options added:"
echo "  CONFIG_DEBUG_INFO_BTF=y     → /sys/kernel/btf/vmlinux"
echo "  CONFIG_BPF_SYSCALL=y        → bpf(2) syscall"
echo "  CONFIG_BPF_JIT=y            → BPF JIT compiler"
echo "  CONFIG_CGROUP_BPF=y         → cgroup BPF"
echo "  CONFIG_BPF_EVENTS=y         → BPF events"
echo "  CONFIG_NET_CLS_BPF=m        → TC BPF classifier"
echo "  CONFIG_NET_ACT_BPF=m        → TC BPF action"
echo "  CONFIG_XDP_SOCKETS=y        → XDP sockets"
echo "  CONFIG_VETH=m               → Virtual ethernet"
echo ""
echo "These options enable daed/dae eBPF programs to load"
echo "and function correctly on the 360T7."
