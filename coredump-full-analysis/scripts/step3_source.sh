#!/bin/bash
# 步骤3: 代码管理 - 克隆源码并创建崩溃分支
# 对应 Skill: coredump-code-management

set -e

# 默认值
PACKAGE=""
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
LOAD_ACCOUNTS_SCRIPT="$SCRIPT_DIR/load_accounts.sh"
source "$LOAD_ACCOUNTS_SCRIPT"
load_accounts_or_die gerrit
GERRIT_URL="ssh://${GERRIT_USER}@${GERRIT_HOST}:${GERRIT_PORT}"
GIT_SSH_COMMAND_DEFAULT="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8"

echo "=========================================="
echo "步骤3: 代码管理 - 克隆源码"
echo "=========================================="
echo "包名: $PACKAGE"
echo "工作目录: $WORKSPACE"
echo ""

CODE_DIR="$WORKSPACE/3.代码管理/$PACKAGE"

# 创建目录
mkdir -p "$CODE_DIR"

# 检查是否已经克隆
if [[ -d "$CODE_DIR/.git" ]]; then
    echo "源码已存在，更新中..."
    cd "$CODE_DIR"
    git fetch --all 2>/dev/null || true
    git fetch origin develop/eagle 2>/dev/null || true
else
    echo "克隆源码仓库..."
    cd "$WORKSPACE/3.代码管理"
    # 尝试克隆
    if GIT_SSH_COMMAND="$GIT_SSH_COMMAND_DEFAULT" git clone "${GERRIT_URL}/${PACKAGE}.git" "$PACKAGE" 2>/dev/null; then
        echo "✅ 克隆成功"
    else
        echo "⚠️ 克隆失败，尝试从其他源..."
        # 尝试 https
        if git clone "https://github.com/linuxdeepin/${PACKAGE}.git" "$PACKAGE" 2>/dev/null; then
            echo "✅ 从 GitHub 克隆成功"
        else
            echo "⚠️ 无法克隆仓库，将创建空目录"
            mkdir -p "$CODE_DIR"
        fi
    fi
fi

if [[ -d "$CODE_DIR/.git" ]]; then
    cd "$CODE_DIR"
    
    # 切换到 develop/eagle 分支
    echo ""
    echo "切换到 develop/eagle 分支..."
    if git branch -a | grep -q "develop/eagle"; then
        git checkout develop/eagle 2>/dev/null || git checkout -B develop/eagle origin/develop/eagle 2>/dev/null || true
    else
        git checkout -B develop/eagle 2>/dev/null || true
    fi
    
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "未知")
    echo "当前分支: $CURRENT_BRANCH"
    
    # 显示最近提交
    echo ""
    echo "最近5次提交:"
    git log --oneline -5 2>/dev/null || echo "无提交记录"
fi

STATS_FILE="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"
if [[ -f "$STATS_FILE" ]]; then
    echo ""
    echo "=== 崩溃版本分布 ==="
    python3 - "$STATS_FILE" << 'PYEOF'
import json
import sys
try:
    with open(sys.argv[1]) as f:
        stats = json.load(f)
    for version, count in list(stats.get('by_version', {}).items())[:10]:
        print(f"  {version}: {count}次崩溃")
except:
    pass
PYEOF
fi

echo ""
echo "✅ 步骤3完成"
echo "源码目录: $CODE_DIR"
