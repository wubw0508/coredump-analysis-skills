#!/bin/bash
# 步骤3: 代码管理 - 为每个崩溃版本创建分支并切换
# 对应 Skill: coredump-code-management

WORKSPACE="${WORKSPACE:-/home/wubw/Desktop/test}"
PACKAGE="${1:-dde-session-ui}"
STATS_FILE="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"

echo "=========================================="
echo "步骤3: 代码管理 - 创建崩溃分支"
echo "=========================================="
echo ""

cd "$WORKSPACE/3.代码管理/$PACKAGE"

# 检查是否在崩溃分支上
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" == master ]] || [[ -z "$CURRENT_BRANCH" ]]; then
    echo "当前在master分支，需要切换到崩溃分支"
else
    echo "当前在崩溃分支: $CURRENT_BRANCH"
fi

echo ""
echo "可用的崩溃分支:"
git branch | grep crash- || echo "(暂无)"

echo ""
echo "=== 崩溃分支使用说明 ==="
echo ""
echo "1. 查看所有崩溃分支:"
echo "   git branch | grep crash-"
echo ""
echo "2. 切换到指定崩溃版本分支:"
echo "   git checkout crash-5_8_14"
echo ""
echo "3. 分析完一个版本后，切换到下一个:"
echo "   git checkout crash-5_7_30"
echo ""
echo "4. 回到master:"
echo "   git checkout master"
echo ""
echo "=== 崩溃版本与分支对应关系 ==="

if [[ -f "$STATS_FILE" ]]; then
    python3 << EOF
import json
with open("$STATS_FILE") as f:
    stats = json.load(f)
for version, count in list(stats.get('by_version', {}).items())[:10]:
        branch = "crash-" + version.replace('.', '_')
        print(f"  {version}: {branch} ({count}次崩溃)")
EOF
fi

echo ""
echo "✅ 步骤3完成"
