#!/bin/bash
#=============================================================================
# 批量下载所有版本的deb和dbgsym包
# 功能：从版本清单读取所有版本，下载对应的包
#=============================================================================

set -e

# 配色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 参数
WORKSPACE="${1:-${COREDUMP_WORKSPACE:-$HOME/coredump-workspace-$(date +%Y%m%d-%H%M%S)}}"
PACKAGE="${2:-dde-session-ui}"

# 目录
DOWNLOAD_DIR="$WORKSPACE/4.包管理/下载包"
VERSION_LIST="$WORKSPACE/2.数据筛选/version_list.txt"

# 帮助信息
show_help() {
    cat << EOF
${BLUE}=============================================================================
  批量下载所有版本的包
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 [workspace] [package]

${GREEN}参数:${NC}
    workspace   工作目录（默认: \$HOME/coredump-workspace-YYYYMMDD-HHMMSS）
    package     包名（默认: dde-session-ui）

${GREEN}示例:${NC}
    $0 /path/to/workspace dde-session-ui

${BLUE}=============================================================================
${NC}
EOF
}

if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

echo -e "${BLUE}"
echo "============================================================================="
echo "                  批量下载所有版本的包"
echo "============================================================================="
echo -e "${NC}"
echo -e "工作目录: ${WORKSPACE}"
echo -e "包名: ${PACKAGE}"
echo ""

mkdir -p "$DOWNLOAD_DIR"

# 检查版本清单
if [[ ! -f "$VERSION_LIST" ]]; then
    echo -e "${RED}错误: 版本清单不存在: $VERSION_LIST${NC}"
    exit 1
fi

echo -e "${CYAN}读取版本清单...${NC}"

# 统计
total_versions=0
success_count=0
failed_count=0
skipped_count=0

# 遍历版本清单
while IFS='|' read -r version count priority; do
    # 跳过注释和空行
    [[ "$version" =~ ^#.*$ ]] && continue
    [[ -z "$version" ]] && continue

    total_versions=$((total_versions + 1))

    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[$total_versions] 下载版本: $version (崩溃次数: $count)${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # 检查包是否已下载
    if [[ -f "$DOWNLOAD_DIR/${PACKAGE}_${version}_amd64.deb" ]] || \
       [[ -f "$DOWNLOAD_DIR/${PACKAGE}_${version%?????}_amd64.deb" ]]; then
        echo -e "${GREEN}    ✅ 包已存在，跳过下载${NC}"
        skipped_count=$((skipped_count + 1))
        echo ""
        continue
    fi

    # 尝试下载主包
    echo -e "${CYAN}  → 下载主包: ${PACKAGE}_${version}_amd64.deb${NC}"
    if apt-get download "${PACKAGE}=${version}" 2>/dev/null; then
        # 检查下载的文件
        downloaded_file=$(ls -t "${PACKAGE}"*_amd64.deb 2>/dev/null | head -1)
        if [[ -n "$downloaded_file" ]]; then
            mv "$downloaded_file" "$DOWNLOAD_DIR/"
            echo -e "${GREEN}    ✅ 主包下载完成: $(basename "$downloaded_file")${NC}"
        fi
    else
        echo -e "${YELLOW}    ⚠️  无法下载 ${PACKAGE}=${version}${NC}"
    fi

    # 尝试下载dbgsym包
    echo -e "${CYAN}  → 下载dbgsym包: ${PACKAGE}-dbgsym_${version}_amd64.deb${NC}"
    if apt-get download "${PACKAGE}-dbgsym=${version}" 2>/dev/null; then
        # 检查下载的文件
        downloaded_file=$(ls -t "${PACKAGE}-dbgsym"*_amd64.deb 2>/dev/null | head -1)
        if [[ -n "$downloaded_file" ]]; then
            mv "$downloaded_file" "$DOWNLOAD_DIR/"
            echo -e "${GREEN}    ✅ dbgsym包下载完成: $(basename "$downloaded_file")${NC}"
            success_count=$((success_count + 1))
        fi
    else
        echo -e "${YELLOW}    ⚠️  无法下载 ${PACKAGE}-dbgsym=${version}${NC}"
        # 检查主包是否下载成功作为成功标志
        if [[ -f "$DOWNLOAD_DIR/${PACKAGE}"*"${version}"*"_amd64.deb" ]]; then
            success_count=$((success_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
    fi

    echo ""
done < "$VERSION_LIST"

# 统计结果
echo ""
echo -e "${BLUE}============================================================================="
echo -e "下载完成"
echo -e "${BLUE}=============================================================================${NC}"
echo -e "总版本数: $total_versions"
echo -e "${GREEN}成功: $success_count${NC}"
echo -e "${YELLOW}跳过: $skipped_count${NC}"
echo -e "${RED}失败: $failed_count${NC}"
echo ""

# 列出已下载的包
echo -e "${CYAN}已下载的包:${NC}"
ls -lh "$DOWNLOAD_DIR"/*.deb 2>/dev/null || echo "  无下载的包"
echo ""

exit $failed_count
