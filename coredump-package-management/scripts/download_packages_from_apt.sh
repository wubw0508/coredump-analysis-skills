#!/bin/bash
#=============================================================================
# 从apt下载指定版本的deb包和dbgsym包
#=============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

download_from_apt() {
    local package="$1"
    local version="$2"
    local arch="${3:-amd64}"

    echo -e "${CYAN}下载 $package $version ($arch)...${NC}"

    # 下载主包
    if ! apt-get download "$package=$version" 2>/dev/null; then
        echo -e "${YELLOW}  警告: 下载主包失败，可能版本不存在${NC}"
        return 1
    fi

    # 查找下载的文件
    local deb_file=$(find . -maxdepth 1 -name "$package*$version*${arch}.deb" 2>/dev/null | grep -v dbgsym | head -1)
    if [[ -n "$deb_file" ]]; then
        echo -e "${GREEN}  ✅ 主包下载成功: $deb_file ($(ls -lh "$deb_file" | awk '{print $5}'))${NC}"
    fi

    # 尝试下载dbgsym包
    if apt-get download "$package-dbgsym=$version" 2>/dev/null; then
        local dbgsym_file=$(find . -maxdepth 1 -name "$package-dbgsym*$version*${arch}.deb" 2>/dev/null | head -1)
        if [[ -n "$dbgsym_file" ]]; then
            echo -e "${GREEN}  ✅ dbgsym包下载成功: $dbgsym_file ($(ls -lh "$dbgsym_file" | awk '{print $5}'))${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠️  dbgsym包下载失败，部分分析功能可能受限${NC}"
    fi

    return 0
}

# 批量下载
if [[ "$1" = "--batch" && -f "$2" ]]; then
    tasks_file="$2"
    echo -e "${BLUE}=== 从apt批量下载包 ===${NC}"
    echo -e "任务文件: $tasks_file"
    echo ""

    success=0
    failed=0

    while IFS= read -r line; do
        [[ "$line" =~ ^\{ ]] && continue
        [[ -z "$line" ]] && continue

        package=$(echo "$line" | jq -r '.package' 2>/dev/null)
        version=$(echo "$line" | jq -r '.version' 2>/dev/null)

        if [[ -n "$package" ]] && [[ -n "$version" ]]; then
            if download_from_apt "$package" "$version"; then
                success=$((success + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done < "$tasks_file"

    echo ""
    echo -e "${BLUE}=== 下载完成 ===${NC}"
    echo -e "成功: $success, 失败: $failed"
    exit 0
fi

# 单个下载
if [[ $# -ge 2 ]]; then
    download_from_apt "$1" "$2" "$3"
else
    echo "用法: $0 <package> <version> [arch]"
    echo "      $0 --batch <tasks.json>"
fi
