#!/bin/bash
#=============================================================================
# 崩溃源码下载脚本
# 功能：根据崩溃数据文件中的包名和版本号，下载对应版本的源代码
# 使用方法：
#   ./download_crash_source.sh <崩溃数据文件路径> [行号]
#   如果不指定行号，默认处理第一行（跳过表头）
#
# 改进：
#   - 所有 git 操作使用绝对路径，不依赖当前目录
#   - 添加回退逻辑：精确匹配 -> 模糊匹配 -> develop/eagle
#   - 添加 git fetch 失败重试
#=============================================================================

set -e

# 配色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置 - 默认使用当前目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${COREDUMP_WORKSPACE:-$SCRIPT_DIR/../../..}"
CODE_DIR="${WORKSPACE}/3.代码管理"

# 从 centralized 配置加载 Gerrit 信息
CENTRALIZED_CONFIG="$SCRIPT_DIR/../../coredump-crash-analysis/centralized/base_config.py"
if [ -f "$CENTRALIZED_CONFIG" ]; then
    # 从 Python 配置加载
    GERRIT_USER=$(python3 -c "import sys; sys.path.insert(0, '$SCRIPT_DIR/../../coredump-crash-analysis'); from centralized.base_config import GERRIT_BASE_URL; print('ut000168')" 2>/dev/null || echo "ut000168")
fi

# 默认值
GERRIT_USER="${GERRIT_USER:-ut000168}"
GERRIT_HOST="${GERRIT_HOST:-gerrit.uniontech.com}"
GERRIT_PORT="${GERRIT_PORT:-29418}"

# 解析参数
CRASH_DATA_FILE="$1"
LINE_NUM="${2:-2}"  # 默认第2行（跳过表头）

show_help() {
    cat << EOF
${BLUE}=============================================================================
崩溃源码下载工具${NC}

${GREEN}用法:${NC}
    $0 <崩溃数据文件路径> [行号]
    $0 <package> <version>

${GREEN}示例:${NC}
    $0 /path/to/filtered_crash_data.csv 2
    $0 dde-launcher 5.6.15.1-1

${BLUE}=============================================================================${NC}
EOF
}

# 检查参数
if [ -z "$1" ]; then
    show_help
    exit 1
fi

# 支持两种调用方式
if [ -f "$1" ]; then
    # 方式1：从崩溃数据文件读取
    CRASH_DATA_FILE="$1"

    if [ ! -f "$CRASH_DATA_FILE" ]; then
        echo -e "${RED}错误：文件不存在: $CRASH_DATA_FILE${NC}"
        exit 1
    fi

    echo "=========================================="
    echo "崩溃源码下载工具"
    echo "=========================================="
    echo "工作目录: $WORKSPACE"
    echo "代码目录: $CODE_DIR"

    # 读取指定行的数据
    echo ""
    echo "正在读取崩溃数据文件..."
    CRASH_LINE=$(sed -n "${LINE_NUM}p" "$CRASH_DATA_FILE")

    if [ -z "$CRASH_LINE" ]; then
        echo -e "${RED}错误：第 $LINE_NUM 行没有数据${NC}"
        exit 1
    fi

    # 解析包名和版本号
    PACKAGE=$(echo "$CRASH_LINE" | cut -d',' -f2)
    VERSION=$(echo "$CRASH_LINE" | cut -d',' -f1)
else
    # 方式2：直接指定包名和版本
    PACKAGE="$1"
    VERSION="$2"
fi

if [ -z "$PACKAGE" ] || [ -z "$VERSION" ]; then
    echo -e "${RED}错误：包名和版本不能为空${NC}"
    show_help
    exit 1
fi

# 清理版本号
VERSION_CLEAN=$(echo "$VERSION" | sed 's/^1://' | sed 's/-1$//')

echo ""
echo "崩溃信息："
echo "   包名: $PACKAGE"
echo "   完整版本: $VERSION"
echo "   清理版本: $VERSION_CLEAN"
echo ""

# 确保代码目录存在
if [ ! -d "$CODE_DIR" ]; then
    echo "创建代码管理目录: $CODE_DIR"
    mkdir -p "$CODE_DIR"
fi

CODE_PATH="$CODE_DIR/$PACKAGE"

# --------------------
# 下载或更新代码仓库
# --------------------
if [ -d "$CODE_PATH/.git" ]; then
    echo -e "${CYAN}[1] 代码已存在，更新仓库...${NC}"

    # 使用绝对路径更新
    git -C "$CODE_PATH" fetch --tags origin 2>/dev/null || {
        echo -e "${YELLOW}  git fetch 失败，尝试重试...${NC}"
        sleep 2
        git -C "$CODE_PATH" fetch --tags origin 2>/dev/null || true
    }
else
    echo -e "${CYAN}[1] 下载源代码...${NC}"

    # 克隆仓库
    if git clone "ssh://${GERRIT_USER}@${GERRIT_HOST}:${GERRIT_PORT}/${PACKAGE}" "$CODE_PATH" 2>/dev/null; then
        echo -e "${GREEN}  克隆成功${NC}"

        # 配置 commit-msg hooks
        echo "  配置 commit-msg hooks..."
        scp -p -P $GERRIT_PORT ${GERRIT_USER}@${GERRIT_HOST}:hooks/commit-msg "$CODE_PATH/.git/hooks/" 2>/dev/null || {
            echo -e "${YELLOW}  警告：复制 hooks 失败${NC}"
        }
    else
        echo -e "${RED}错误：克隆代码失败${NC}"
        exit 1
    fi
fi

# --------------------
# 切换到对应版本
# --------------------
echo ""
echo -e "${CYAN}[2] 切换到版本分支${NC}"

cd "$CODE_PATH"

# 尝试查找精确匹配的 tag
CHECKOUT_TAG=""
CHECKOUT_METHOD=""

# 1. 精确匹配
if git -C "$CODE_PATH" tag | grep -qE "^${VERSION_CLEAN}$"; then
    CHECKOUT_TAG="$VERSION_CLEAN"
    CHECKOUT_METHOD="精确匹配"
fi

# 2. 模糊匹配
if [ -z "$CHECKOUT_TAG" ]; then
    MATCHING_TAG=$(git -C "$CODE_PATH" tag | grep -E "^${VERSION_CLEAN}" | sort -V | tail -1)
    if [ -n "$MATCHING_TAG" ]; then
        CHECKOUT_TAG="$MATCHING_TAG"
        CHECKOUT_METHOD="模糊匹配"
    fi
fi

# 3. 回退到 origin/develop/eagle
if [ -z "$CHECKOUT_TAG" ]; then
    # 检查是否存在 develop/eagle 分支
    if git -C "$CODE_PATH" ls-remote --exit-code --heads origin "origin/develop/eagle" 2>/dev/null | grep -q "develop/eagle"; then
        CHECKOUT_TAG="origin/develop/eagle"
        CHECKOUT_METHOD="回退到 develop/eagle"
    fi
fi

if [ -n "$CHECKOUT_TAG" ]; then
    echo -e "  切换方式: ${GREEN}$CHECKOUT_METHOD${NC}"
    echo -e "  目标版本: ${GREEN}$CHECKOUT_TAG${NC}"

    # 创建新分支并切换
    FIX_BRANCH="${PACKAGE}-${VERSION_CLEAN}"
    echo -e "  创建分支: ${YELLOW}$FIX_BRANCH${NC}"

    if git -C "$CODE_PATH" checkout -b "$FIX_BRANCH" "$CHECKOUT_TAG" 2>/dev/null; then
        echo -e "  ${GREEN}✅ 分支创建成功${NC}"

        # 硬重置到版本标签，确保代码与版本完全一致
        echo -e "  执行: git reset --hard $CHECKOUT_TAG"
        if git -C "$CODE_PATH" reset --hard "$CHECKOUT_TAG" 2>/dev/null; then
            echo -e "  ${GREEN}✅ 代码重置成功${NC}"
        else
            echo -e "  ${YELLOW}⚠️ 代码重置失败，使用当前状态${NC}"
        fi
    else
        # 分支可能已存在，尝试切换并重置
        echo -e "  ${YELLOW}分支已存在，尝试切换...${NC}"
        if git -C "$CODE_PATH" checkout "$FIX_BRANCH" 2>/dev/null && \
           git -C "$CODE_PATH" reset --hard "$CHECKOUT_TAG" 2>/dev/null; then
            echo -e "  ${GREEN}✅ 切换并重置成功${NC}"
        else
            echo -e "  ${RED}❌ 切换失败${NC}"
        fi
    fi
else
    echo -e "${YELLOW}  未找到匹配的 tag，保持当前分支${NC}"
fi

# 显示当前信息
echo ""
echo "=========================================="
echo "完成！"
echo "=========================================="
echo "代码目录: $CODE_PATH"
echo "当前版本: $(git -C "$CODE_PATH" describe --tags --exact-match 2>/dev/null || echo 'N/A')"
echo "当前分支: $(git -C "$CODE_PATH" branch --show-current 2>/dev/null || echo 'detached')"
echo "=========================================="
echo ""
