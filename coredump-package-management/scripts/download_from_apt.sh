#!/bin/bash
#=============================================================================
# 从 apt 源下载 deb 包和调试包
#=============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 参数
PACKAGE="${1:-}"
VERSION="${2:-}"
OUTPUT_DIR="${3:-.}"

show_help() {
    cat << EOF
${BLUE}=============================================================================
从 apt 源下载 deb 包和调试包${NC}

${GREEN}用法:${NC}
    $0 <package> <version> [output_dir]

${GREEN}示例:${NC}
    $0 dde-dock 5.7.28.2-1 ./downloads
    $0 dde-launcher 5.6.15.1-1

${BLUE}=============================================================================${NC}
EOF
}

if [[ -z "$PACKAGE" || -z "$VERSION" ]]; then
    show_help
    exit 1
fi

echo ""
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}从 apt 源下载包${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo ""
echo "包: $PACKAGE"
echo "版本: $VERSION"
echo "输出目录: $OUTPUT_DIR"
echo ""

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# 清理版本号中的 epoch 和 revision
VERSION_CLEAN=$(echo "$VERSION" | sed 's/^1://' | sed 's/-1$//')

echo "清理后版本: $VERSION_CLEAN"
echo ""

# 尝试下载主包
echo -e "${YELLOW}尝试下载主包...${NC}"
if apt download "$PACKAGE=$VERSION" 2>/dev/null; then
    echo -e "${GREEN}主包下载成功${NC}"
else
    # 尝试不带版本号下载最新版本
    echo "主包下载失败，尝试下载最新版..."
    if apt download "$PACKAGE" 2>/dev/null; then
        echo -e "${GREEN}最新版主包下载成功${NC}"
    else
        echo -e "${RED}主包下载失败${NC}"
    fi
fi

# 尝试下载调试包
echo ""
echo -e "${YELLOW}尝试下载调试包...${NC}"

# 调试包名称格式: package-dbgsym
DBGSYM_PACKAGE="${PACKAGE}-dbgsym"

if apt download "$DBGSYM_PACKAGE=$VERSION" 2>/dev/null; then
    echo -e "${GREEN}调试包下载成功${NC}"
else
    # 尝试不带版本号
    if apt download "$DBGSYM_PACKAGE" 2>/dev/null; then
        echo -e "${GREEN}最新版调试包下载成功${NC}"
    else
        echo -e "${YELLOW}调试包下载失败（可能该版本没有调试包）${NC}"
    fi
fi

# 列出下载的文件
echo ""
echo "下载的文件:"
ls -la *.deb 2>/dev/null || echo "无"

echo ""
echo -e "${GREEN}完成${NC}"