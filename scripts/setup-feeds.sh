#!/bin/bash
# setup-feeds.sh — Add kenzok8/openwrt-daede as custom feed
# This provides dae (performance-optimized) + daed (web panel) + luci-app-daede (unified LuCI)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENWRT_DIR="${1:-$(pwd)}"

if [ ! -f "$OPENWRT_DIR/feeds.conf.default" ]; then
  echo "ERROR: Not in ImmortalWrt root directory"
  echo "Usage: $0 [openwrt-dir]"
  exit 1
fi

cd "$OPENWRT_DIR"

echo "=========================================="
echo "  Adding kenzok8/openwrt-daede feed"
echo "=========================================="

# Remove old daede feed entry if exists
sed -i '/openwrt-daede/d' feeds.conf 2>/dev/null || true

# Add the feed
cat >> feeds.conf << 'FEED'
src-git daede https://github.com/kenzok8/openwrt-daede.git;main
FEED

echo ""
echo "feeds.conf content:"
cat feeds.conf

echo ""
echo "=========================================="
echo "  Updating feeds..."
echo "=========================================="
./scripts/feeds update -a

echo ""
echo "=========================================="
echo "  Installing feeds..."
echo "=========================================="

# Install kenzok8's dae/daed/luci-app-daede
./scripts/feeds install -a
./scripts/feeds install dae daed luci-app-daede

echo ""
echo "=========================================="
echo "  Feed setup complete!"
echo "=========================================="
echo ""
echo "Available daede packages:"
find feeds/daede -name "Makefile" -exec dirname {} \; 2>/dev/null | while read dir; do
  pkg=$(basename "$dir")
  echo "  - $pkg"
done | sort -u
