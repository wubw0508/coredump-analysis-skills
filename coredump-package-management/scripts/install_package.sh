#!/bin/bash
#=============================================================================
# 安装 deb 包和调试符号包 - 支持多源回退
# 下载顺序: apt -> internal_server -> ppa
#=============================================================================

set -e

# 配色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE="${WORKSPACE:-/home/wubw/workspace}"
LOAD_ACCOUNTS_SCRIPT="$SKILLS_DIR/coredump-full-analysis/scripts/load_accounts.sh"

# 参数
PACKAGE="${1:-}"
VERSION="${2:-}"
OUTPUT_DIR="${3:-${WORKSPACE}/4.包管理/下载包/downloads}"
source "$LOAD_ACCOUNTS_SCRIPT"
load_accounts_or_die system

show_help() {
    cat << EOF
${BLUE}=============================================================================
安装 deb 包和调试符号包 (支持多源回退)${NC}

${GREEN}用法:${NC}
    $0 <package> <version> [output_dir]
    $0 <package> <version> [output_dir] --download-only
    $0 <package> <version> [output_dir] --install-only

${GREEN}下载源优先级:${NC}
    1. apt 源 (最快)
    2. 内部服务器 (镜像)
    3. PPA (兜底)

${GREEN}示例:${NC}
    $0 dde-launcher 5.6.15.1-1
    $0 dde-launcher 5.6.15.1-1 ./downloads --download-only

${BLUE}=============================================================================${NC}
EOF
}

# 参数解析
DOWNLOAD_ONLY=false
INSTALL_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --download-only)
            DOWNLOAD_ONLY=true
            shift
            ;;
        --install-only)
            INSTALL_ONLY=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$PACKAGE" ]]; then
                PACKAGE="$1"
            elif [[ -z "$VERSION" ]]; then
                VERSION="$1"
            elif [[ -z "$OUTPUT_DIR" ]]; then
                OUTPUT_DIR="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$PACKAGE" ]] || [[ -z "$VERSION" ]]; then
    show_help
    exit 1
fi

echo ""
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}安装 deb 包${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo ""
echo "包: $PACKAGE"
echo "版本: $VERSION"
echo "输出目录: $OUTPUT_DIR"
echo "下载模式: $DOWNLOAD_ONLY"
echo "安装模式: $INSTALL_ONLY"
echo ""

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# 清理版本号
VERSION_CLEAN=$(echo "$VERSION" | sed 's/^1://' | sed 's/-1$//')

# 查找已有的 deb 文件
find_existing_debs() {
    local pkg="$1"
    local ver="$2"
    find "$OUTPUT_DIR" -maxdepth 1 -name "${pkg}_${ver}*.deb" -type f 2>/dev/null || true
}

# --------------------
# 下载步骤
# --------------------
if [[ "$DOWNLOAD_ONLY" == "true" ]] || [[ "$INSTALL_ONLY" == "false" ]]; then
    echo -e "${CYAN}[步骤1] 下载包${NC}"

    # 检查是否已有包
    EXISTING_DEBS=$(find_existing_debs "$PACKAGE" "$VERSION")
    if [[ -n "$EXISTING_DEBS" ]]; then
        EXISTING_COUNT=$(echo "$EXISTING_DEBS" | wc -l)
        echo -e "${GREEN}  发现 $EXISTING_COUNT 个已有包，跳过下载${NC}"
    else
        DOWNLOADED=false
        DOWNLOAD_SOURCE=""

        # 方式1: apt 源
        echo -e "${YELLOW}  [方式1] 从 apt 源下载...${NC}"
        if apt download "${PACKAGE}=${VERSION}" 2>/dev/null; then
            echo -e "${GREEN}    主包下载成功${NC}"
            DOWNLOADED=true
            DOWNLOAD_SOURCE="apt"
        fi

        if [[ "$DOWNLOADED" == "false" ]]; then
            echo -e "${YELLOW}  [方式2] 从内部服务器下载...${NC}"
            if python3 "$SKILLS_DIR/coredump-package-management/scripts/scan_and_download.py" \
                "$PACKAGE" "$VERSION_CLEAN" "$OUTPUT_DIR" 2>/dev/null; then
                if find_existing_debs "$PACKAGE" "$VERSION" | grep -q .; then
                    DOWNLOADED=true
                    DOWNLOAD_SOURCE="internal"
                    echo -e "${GREEN}    内部服务器下载成功${NC}"
                fi
            fi
        fi

        if [[ "$DOWNLOADED" == "false" ]]; then
            echo -e "${YELLOW}  [方式3] 从 PPA 下载...${NC}"
            if bash "$SKILLS_DIR/coredump-package-management/scripts/download_from_ppa.sh" \
                "$PACKAGE" "$VERSION" "$OUTPUT_DIR" 2>/dev/null; then
                if find_existing_debs "$PACKAGE" "$VERSION" | grep -q .; then
                    DOWNLOADED=true
                    DOWNLOAD_SOURCE="ppa"
                    echo -e "${GREEN}    PPA 下载成功${NC}"
                fi
            fi
        fi

        if [[ "$DOWNLOADED" == "false" ]]; then
            echo -e "${RED}  所有下载方式均失败${NC}"
        else
            echo -e "${GREEN}  下载完成 (来源: $DOWNLOAD_SOURCE)${NC}"
        fi
    fi

    # 下载调试包
    echo ""
    echo -e "${CYAN}[步骤2] 下载调试包${NC}"
    DBGSYM_PKG="${PACKAGE}-dbgsym"

    # 检查是否已有调试包
    EXISTING_DBGSYM=$(find "$OUTPUT_DIR" -maxdepth 1 -name "${DBGSYM_PKG}_${VERSION}*.deb" -type f 2>/dev/null || true)
    if [[ -n "$EXISTING_DBGSYM" ]]; then
        echo -e "${GREEN}  发现调试包，跳过下载${NC}"
    else
        for ATTEMPT in 1 2 3; do
            echo -n "  下载调试包 (尝试 $ATTEMPT)... "
            if apt download "${DBGSYM_PKG}=${VERSION}" 2>/dev/null; then
                echo -e "${GREEN}成功${NC}"
                break
            else
                echo -e "${YELLOW}失败${NC}"
                sleep 2
            fi
        done
    fi
fi

# --------------------
# 安装步骤
# --------------------
if [[ "$INSTALL_ONLY" == "true" ]] || [[ "$DOWNLOAD_ONLY" == "false" ]]; then
    echo ""
    echo -e "${CYAN}[步骤3] 安装包${NC}"

    # 查找所有 deb 文件
    DEB_FILES=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.deb" -type f 2>/dev/null || true)

    if [[ -z "$DEB_FILES" ]]; then
        echo -e "${RED}  未找到任何 deb 文件${NC}"
        exit 1
    fi

    echo "  找到以下 deb 包:"
    echo "$DEB_FILES" | while read deb; do
        echo "    - $(basename "$deb")"
    done

    # 分离主包和调试包
    MAIN_DEBS=""
    DBGSYM_DEBS=""

    for deb in $DEB_FILES; do
        if [[ "$deb" == *"-dbgsym_"* ]] || [[ "$deb" == *"dbgsym"* ]]; then
            DBGSYM_DEBS="$DBGSYM_DEBS $deb"
        else
            MAIN_DEBS="$MAIN_DEBS $deb"
        fi
    done

    echo ""
    echo "  主包: $(echo $MAIN_DEBS | wc -w) 个"
    echo "  调试包: $(echo $DBGSYM_DEBS | wc -w) 个"

    # 安装主包
    if [[ -n "$MAIN_DEBS" ]]; then
        echo ""
        echo -e "${YELLOW}  安装主包...${NC}"
        for deb in $MAIN_DEBS; do
            echo "    安装: $(basename "$deb")"
            echo "$SUDO_PASSWORD" | sudo -S dpkg -i "$deb" 2>/dev/null || \
                apt-get install -f -y --no-install-recommends "$deb" 2>/dev/null || true
        done
    fi

    # 安装调试包
    if [[ -n "$DBGSYM_DEBS" ]]; then
        echo ""
        echo -e "${YELLOW}  安装调试包...${NC}"
        for deb in $DBGSYM_DEBS; do
            echo "    安装: $(basename "$deb")"
            echo "$SUDO_PASSWORD" | sudo -S dpkg -i "$deb" 2>/dev/null || \
                apt-get install -f -y --no-install-recommends "$deb" 2>/dev/null || true
        done
    fi

    # 修复依赖
    echo ""
    echo -e "${YELLOW}  修复依赖...${NC}"
    echo "$SUDO_PASSWORD" | sudo -S apt-get install -f -y 2>/dev/null || true
fi

# 列出最终文件
echo ""
echo "下载目录内容:"
ls -lh "$OUTPUT_DIR"/*.deb 2>/dev/null || echo "无 deb 文件"

echo ""
echo -e "${GREEN}=============================================================================${NC}"
echo -e "${GREEN}完成！${NC}"
echo -e "${GREEN}=============================================================================${NC}"
