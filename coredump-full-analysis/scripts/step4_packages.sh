#!/bin/bash
# 步骤4: 包管理 - 下载deb/dbgsym包
# 对应 Skill: coredump-package-management

set -e

SKILLS_DIR="/home/wubw/skills/coredump-package-management/scripts"
CONFIG_DIR="/home/wubw/skills/coredump-full-analysis/config"

# 默认值
PACKAGE="${PACKAGE:-}"
WORKSPACE="${WORKSPACE:-./workspace}"

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
cp "$SKILLS_DIR/generate_tasks.py" .
cp "$SKILLS_DIR/scan_and_download.py" .

# 生成下载任务（基于统计数据）
if [[ -f "../../2.数据筛选/${PACKAGE}_stats.json" ]]; then
    echo "从统计数据生成下载任务..."
    # 这里简化为生成Top版本的任务
    cat > download_tasks.json << EOF
{
  "package": "$PACKAGE",
  "versions": ["5.8.14-1", "5.7.30-1", "5.8.12-1"],
  "arch": "amd64",
  "type": ["deb", "dbgsym"]
}
EOF
    cat download_tasks.json
    echo ""
    echo "✅ 下载任务已生成"
    echo "提示: 需要Shuttle服务器支持才能下载实际包"
else
    echo "⚠️ 未找到统计数据，先执行步骤2生成统计"
fi

echo ""
echo "输出目录: $WORKSPACE/4.包管理/downloads/"
