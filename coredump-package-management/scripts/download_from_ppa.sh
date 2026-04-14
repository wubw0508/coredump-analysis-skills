#!/bin/bash
#=============================================================================
# 从 PPA 仓库下载 deb 包和调试包
#=============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
BASE_URL="http://pools.uniontech.com/ppa/dde-eagle/pool/main"
PACKAGE="${1:-}"
VERSION="${2:-}"
OUTPUT_DIR="${3:-.}"

show_help() {
    cat << EOF
${BLUE}=============================================================================
从 PPA 仓库下载 deb 包和调试包${NC}

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
echo -e "${BLUE}从 PPA 下载包${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo ""
echo "包: $PACKAGE"
echo "版本: $VERSION"
echo "输出目录: $OUTPUT_DIR"
echo ""

# 获取包名的第一个字母（用于URL路径）
PKG_LETTER="${PACKAGE:0:1}"
PKG_URL="${BASE_URL}/${PKG_LETTER}/${PACKAGE}"

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

echo "下载主包..."
MAIN_FILE="${PACKAGE}_${VERSION}_amd64.deb"

if [[ -f "$MAIN_FILE" ]]; then
    echo -e "${GREEN}主包已存在: $MAIN_FILE${NC}"
else
    wget -q -O "$MAIN_FILE" "${PKG_URL}/${MAIN_FILE}" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}主包下载成功: $MAIN_FILE${NC}"
    else
        echo -e "${RED}主包下载失败: $MAIN_FILE${NC}"
        rm -f "$MAIN_FILE"
    fi
fi

echo ""
echo "下载调试包..."
DBGSYM_FILE="${PACKAGE}-dbgsym_${VERSION}_amd64.deb"

if [[ -f "$DBGSYM_FILE" ]]; then
    echo -e "${GREEN}调试包已存在: $DBGSYM_FILE${NC}"
else
    wget -q -O "$DBGSYM_FILE" "${PKG_URL}/${DBGSYM_FILE}" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}调试包下载成功: $DBGSYM_FILE${NC}"
    else
        echo -e "${YELLOW}调试包下载失败（可能该版本没有调试包）: $DBGSYM_FILE${NC}"
        rm -f "$DBGSYM_FILE"
    fi
fi

echo ""
echo "下载的文件:"
ls -la *.deb 2>/dev/null || echo "无"

echo ""
echo -e "${GREEN}完成${NC}"