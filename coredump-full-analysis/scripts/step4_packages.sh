#!/bin/bash
# 步骤4: 包管理 - 下载deb/dbgsym包
# 对应 Skill: coredump-package-management

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/../../coredump-package-management/scripts"
CONFIG_DIR="$SCRIPT_DIR/../config"

# 默认值
PACKAGE="${PACKAGE:-}"
if [[ -z "$WORKSPACE" ]]; then WORKSPACE="$HOME/coredump-workspace-$(date +%Y%m%d-%H%M%S)"; fi

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --package) PACKAGE="$2"; shift 2 ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "$PACKAGE" ]]; then
    echo "错误: 必须指定 --package 参数"
    exit 1
fi

# 加载配置
source "$CONFIG_DIR/shuttle.env" 2>/dev/null || true

# 创建目录
mkdir -p "$WORKSPACE/4.包管理/下载包/downloads"

echo "=========================================="
echo "步骤4: 包管理 - 下载deb/dbgsym包"
echo "=========================================="
echo "包名: $PACKAGE"
echo "Shuttle: ${SHUTTLE_URL:-https://shuttle.uniontech.com}"
echo ""

cd "$WORKSPACE/4.包管理/下载包"

# 复制脚本
if [[ -f "$SKILLS_DIR/generate_tasks.py" ]]; then
    cp "$SKILLS_DIR/generate_tasks.py" .
fi
if [[ -f "$SKILLS_DIR/scan_and_download.py" ]]; then
    cp "$SKILLS_DIR/scan_and_download.py" .
fi

# 生成下载任务（基于统计数据）
STATS_FILE="../../2.数据筛选/${PACKAGE}_crash_statistics.json"
if [[ -f "$STATS_FILE" ]]; then
    echo "从统计数据生成下载任务..."
    python3 - "$PACKAGE" "$STATS_FILE" << 'PYEOF'
import json
import sys
package = sys.argv[1]
stats_file = sys.argv[2]
try:
    with open(stats_file) as f:
        stats = json.load(f)
    top_versions = list(stats.get('by_version', {}).keys())[:5]
except:
    top_versions = ["5.8.14-1", "5.7.30-1", "5.8.12-1"]
task = {
    "package": package,
    "versions": top_versions,
    "arch": "amd64",
    "type": ["deb", "dbgsym"]
}
with open('download_tasks.json', 'w') as f:
    json.dump(task, f, indent=2, ensure_ascii=False)
print(json.dumps(task, indent=2, ensure_ascii=False))
PYEOF
    echo ""
    echo "✅ 下载任务已生成"
else
    echo "⚠️ 未找到统计数据: $STATS_FILE"
    cat > download_tasks.json << EOF
{
  "package": "$PACKAGE",
  "versions": ["5.8.14-1", "5.7.30-1", "5.8.12-1"],
  "arch": "amd64",
  "type": ["deb", "dbgsym"]
}
EOF
fi

echo ""
echo "输出目录: $WORKSPACE/4.包管理/downloads/"
