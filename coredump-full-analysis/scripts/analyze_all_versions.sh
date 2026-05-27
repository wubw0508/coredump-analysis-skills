#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEGACY_TARGET="$SCRIPT_DIR/legacy/analyze_all_versions.sh"

echo "错误: $0 已迁移到 legacy/，不再维护。" >&2
echo "legacy 位置: $LEGACY_TARGET" >&2
echo "推荐入口:" >&2
echo "  bash run_analysis_agent.sh --packages dde-launcher --start-date <YYYY-MM-DD> --end-date <YYYY-MM-DD>" >&2
echo "当前通用流程已覆盖下载、筛选、源码、包、逐版本分析与报告生成。" >&2
exit 1
