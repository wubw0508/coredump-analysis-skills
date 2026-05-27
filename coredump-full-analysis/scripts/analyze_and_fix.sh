#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEGACY_TARGET="$SCRIPT_DIR/legacy/analyze_and_fix.sh"

echo "错误: $0 已迁移到 legacy/，不再维护。" >&2
echo "legacy 位置: $LEGACY_TARGET" >&2
echo "推荐入口:" >&2
echo "  bash run_analysis_agent.sh --packages <package> --auto-fix-submit" >&2
echo "或在已有 workspace 上运行当前 auto-fix 主链路。" >&2
exit 1
