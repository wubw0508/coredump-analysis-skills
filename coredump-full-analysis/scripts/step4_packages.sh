#!/bin/bash
# 步骤4: 包管理 - 下载deb/dbgsym包
# 对应 Skill: coredump-package-management

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/../../coredump-package-management/scripts"
CONFIG_DIR="$SCRIPT_DIR/../config"
LOAD_ACCOUNTS_SCRIPT="$SCRIPT_DIR/load_accounts.sh"

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

source "$LOAD_ACCOUNTS_SCRIPT"
load_accounts_or_die shuttle

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
    "type": ["deb", "dbgsym"],
    "tasks": [{"package": package, "version": version, "arch": "amd64"} for version in top_versions]
}
with open('download_tasks.json', 'w') as f:
    json.dump(task, f, indent=2, ensure_ascii=False)
print(json.dumps(task, indent=2, ensure_ascii=False))
PYEOF
    echo ""
    echo "✅ 下载任务已生成"
else
    echo "⚠️ 未找到统计数据: $STATS_FILE"
    echo "错误: 无法生成下载任务，缺少统计数据"
    exit 1
fi

echo ""
echo "输出目录: $WORKSPACE/4.包管理/downloads/"

if [[ ! -f "scan_and_download.py" ]]; then
    echo "错误: 未找到 scan_and_download.py"
    exit 1
fi

echo ""
echo "开始下载 deb/dbgsym 包..."
python3 scan_and_download.py --batch download_tasks.json --download-dir "$WORKSPACE/4.包管理/downloads" || {
    echo "⚠️ 包下载阶段出现错误，继续后续分析"
}

if find "$WORKSPACE/4.包管理/downloads" -maxdepth 1 -name "*.deb" | grep -q .; then
    echo ""
    echo "检测到已下载的 deb 包，开始安装..."
    python3 - "$PACKAGE" download_tasks.json <<'PYEOF' | while IFS= read -r version; do
import json
import sys
package = sys.argv[1]
task_file = sys.argv[2]
with open(task_file, encoding="utf-8") as f:
    task = json.load(f)
for version in task.get("versions", []):
    if version:
        print(version)
PYEOF
        bash "$SCRIPT_DIR/install_package.sh" \
            --package "$PACKAGE" \
            --version "$version" \
            --download-dir "$WORKSPACE/4.包管理/downloads" \
            --force || {
            echo "⚠️ 安装版本 $version 失败，继续处理其他版本"
        }
    done
else
    echo "⚠️ 未下载到任何 deb 包，跳过安装"
fi

echo ""
echo "✅ 步骤4完成"
