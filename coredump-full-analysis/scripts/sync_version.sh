#!/bin/bash
#=============================================================================
# 版本同步脚本
# 功能：同时切换代码和包到指定版本，确保分析环境一致
#=============================================================================

set -e

# 配色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 首先尝试从 skills 目录加载配置
SKILLS_CONFIG_DIR="/home/wubw/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw/skills/coredump-full-analysis/config"

source "$SKILLS_CONFIG_DIR/metabase.env" 2>/dev/null || true
source "$SKILLS_CONFIG_DIR/gerrit.env" 2>/dev/null || true
source "$SKILLS_CONFIG_DIR/package-server.env" 2>/dev/null || true
source "$SKILLS_CONFIG_DIR/loop.env" 2>/dev/null || true
source "$SKILLS_CONFIG_DIR/local.env" 2>/dev/null || true

# 帮助信息
show_help() {
    cat << EOF
${BLUE}=============================================================================
  版本同步脚本 - 同时切换代码和包到指定版本
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 [选项] --package <name> --version <version> --workspace <dir>

${GREEN}选项:${NC}
    --package <name>       包名（必需）
    --version <version>    版本号（必需），例如: 1:5.9.6-1
    --workspace <dir>      工作目录（必需）
    --skip-code            跳过代码切换
    --skip-package         跳过包安装
    --verify-only          仅验证版本一致性
    --help, -h            显示此帮助信息

${GREEN}示例:${NC}
    # 同步代码和包到版本 5.9.6
    $0 --package dde-session-ui --version 1:5.9.6-1 --workspace /path/to/workspace

    # 仅切换代码
    $0 --package dde-session-ui --version 5.8.32 --workspace /path --skip-package

    # 仅验证版本
    $0 --package dde-session-ui --version 5.8.32 --workspace /path --verify-only

${BLUE}=============================================================================
${NC}
EOF
}

# 解析参数
parse_args() {
    PACKAGE=""
    VERSION=""
    WORKSPACE=""
    SKIP_CODE=false
    SKIP_PACKAGE=false
    VERIFY_ONLY=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --package)
                PACKAGE="$2"
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --workspace)
                WORKSPACE="$2"
                shift 2
                ;;
            --skip-code)
                SKIP_CODE=true
                shift
                ;;
            --skip-package)
                SKIP_PACKAGE=true
                shift
                ;;
            --verify-only)
                VERIFY_ONLY=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}未知参数: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done

    # 验证必需参数
    if [[ -z "$PACKAGE" ]] || [[ -z "$VERSION" ]] || [[ -z "$WORKSPACE" ]]; then
        echo -e "${RED}错误: 必须指定 --package, --version 和 --workspace${NC}"
        show_help
        exit 1
    fi
}

# 清理版本号
clean_version() {
    local version="$1"
    # 移除 epoch（前缀 '1:'）
    version=$(echo "$version" | sed 's/^1://')
    # 移除 debian revision（后缀 '-1', '-2', 等）
    version=$(echo "$version" | sed 's/-[0-9]\+$//')
    echo "$version"
}

# 版本号转文件名使用的格式
version_to_filename() {
    local version="$1"
    # 将版本号中的特殊字符替换为下划线
    echo "$version" | sed 's/\./_/g' | sed 's/+/_/g' | sed 's/-/_/g'
}

# 查找git tag
find_git_tag() {
    local repo_dir="$1"
    local version="$2"

    cd "$repo_dir"

    # 尝试精确匹配
    local exact_tag=$(git tag | grep -E "^${version}$" | head -n 1)
    if [[ -n "$exact_tag" ]]; then
        echo "$exact_tag"
        return 0
    fi

    # 尝试模糊匹配
    local fuzzy_tag=$(git tag | grep -E "${version}" | sort -V | tail -n 1)
    if [[ -n "$fuzzy_tag" ]]; then
        echo "$fuzzy_tag"
        return 0
    fi

    # 尝试匹配主版本号（如 5.8.32 -> 匹配 5.8）
    local major_version=$(echo "$version" | sed 's/\.[0-9]\+$//')
    local major_tag=$(git tag | grep -E "^${major_version}" | sort -V | tail -n 1)
    if [[ -n "$major_tag" ]]; then
        echo "$major_tag"
        return 0
    fi

    return 1
}

# 切换代码版本
sync_code() {
    local version="$1"
    local package="$2"
    local workspace="$3"

    local code_dir="$workspace/3.代码管理/$package"
    local code_version=""

    echo -e "${CYAN}  → 切换代码到版本: $version${NC}" >&2

    if [[ ! -d "$code_dir" ]]; then
        echo -e "${RED}    错误: 代码目录不存在: $code_dir${NC}" >&2
        echo "ERROR" >&2
        return 1
    fi

    if [[ ! -d "$code_dir/.git" ]]; then
        echo -e "${YELLOW}    警告: $code_dir 不是git仓库${NC}" >&2
        echo "ERROR" >&2
        return 1
    fi

    cd "$code_dir" || { echo "ERROR" >&2; return 1; }

    # Suppress git config output for this session
    git config advice.detachedHead false 2>/dev/null || true

    # 方法1: 尝试直接切换到tag
    local exact_tag=$(git tag | grep -E "^${version}$" | head -n 1)
    if [[ -n "$exact_tag" ]]; then
        echo -e "    找到精确tag: $exact_tag" >&2
        # 使用 checkout -b 创建分支然后 reset 到 tag
        local branch_name="crash-version-${version}"
        # 检查是否已存在该分支，如存在则先切换到其他分支再删除
        if git show-ref --verify --quiet "refs/heads/$branch_name"; then
            echo -e "    删除已存在的分支: $branch_name" >&2
            # 先切换到master或其他分支
            git checkout master 2>/dev/null || git checkout develop 2>/dev/null || true
            git branch -D "$branch_name" 2>/dev/null || true
        fi
        if git checkout -b "$branch_name" 2>/dev/null; then
            if git reset --hard "$exact_tag" >/dev/null 2>&1; then
                code_version="$branch_name"
                echo -e "${GREEN}    ✅ 代码已切换到: $branch_name (reset to $exact_tag)${NC}" >&2
            else
                code_version=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                echo -e "${YELLOW}    警告: reset失败，使用当前分支${NC}" >&2
            fi
        else
            code_version=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            echo -e "${YELLOW}    警告: 创建分支失败，使用当前分支${NC}" >&2
        fi
    else
        # 方法2: 尝试模糊匹配
        local fuzzy_tag=$(git tag | grep -E "${version}" | sort -V | tail -n 1)
        if [[ -n "$fuzzy_tag" ]]; then
            echo -e "    找到模糊匹配tag: $fuzzy_tag" >&2
            local branch_name="crash-version-${version}"
            # 检查是否已存在该分支，如存在则先切换到其他分支再删除
            if git show-ref --verify --quiet "refs/heads/$branch_name"; then
                echo -e "    删除已存在的分支: $branch_name" >&2
                git checkout master 2>/dev/null || git checkout develop 2>/dev/null || true
                git branch -D "$branch_name" 2>/dev/null || true
            fi
            if git checkout -b "$branch_name" 2>/dev/null; then
                if git reset --hard "$fuzzy_tag" 2>/dev/null; then
                    code_version="$branch_name"
                    echo -e "${GREEN}    ✅ 代码已切换到: $branch_name (reset to $fuzzy_tag)${NC}" >&2
                else
                    code_version="$branch_name"
                    echo -e "${YELLOW}    警告: reset失败，使用当前分支${NC}" >&2
                fi
            else
                code_version=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                echo -e "${YELLOW}    警告: 创建分支失败，使用当前分支${NC}" >&2
            fi
        else
            # 方法3: 尝试使用commit hash
            echo -e "    未找到匹配的tag" >&2
            # 创建一个新分支
            local branch_name="crash-version-${version}"
            # 检查是否已存在该分支，如存在则先切换到其他分支再删除
            if git show-ref --verify --quiet "refs/heads/$branch_name"; then
                echo -e "    删除已存在的分支: $branch_name" >&2
                git checkout master 2>/dev/null || git checkout develop 2>/dev/null || true
                git branch -D "$branch_name" 2>/dev/null || true
            fi
            if git checkout -b "$branch_name" 2>/dev/null; then
                code_version="$branch_name"
                echo -e "${GREEN}    ✅ 创建了分析分支: $branch_name${NC}" >&2
                echo -e "    注意: 未找到对应的tag，代码将保持当前状态" >&2
            else
                code_version=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                echo -e "${YELLOW}    警告: 创建分支失败，使用当前分支: $code_version${NC}" >&2
            fi
        fi
    fi

    # 获取当前版本（精确匹配）
    # 改进：避免输出多余的 HEAD 状态信息
    local final_version=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "$code_version")

    # 如果是crash-version分支，提取版本号
    if [[ "$final_version" =~ ^crash-version- ]]; then
        final_version="${final_version#crash-version-}"
    fi

    # 输出最终版本号（不带颜色）
    echo "$final_version"
}

# 安装对应版本的包
sync_package() {
    local version="$1"
    local package="$2"
    local workspace="$3"

    echo -e "${CYAN}  → 安装版本 $version 的包${NC}"

    # Debug: 检查 LOCAL_PASSWORD 是否已设置
    if [[ -z "$LOCAL_PASSWORD" ]]; then
        echo -e "${YELLOW}    警告: LOCAL_PASSWORD 未设置，sudo命令可能失败${NC}" >&2
        LOCAL_PASSWORD="1"  # 设置默认值
    fi

    local download_dir="$workspace/4.包管理/下载包"

    # 尝试多种文件名格式
    local deb_patterns=(
        "${package}_${version}_amd64.deb"
        "${package}_${version}-1_amd64.deb"
        "${package}_1:${version}_amd64.deb"
        "${package}_1:${version}-1_amd64.deb"
    )

    local deb_file=""
    for pattern in "${deb_patterns[@]}"; do
        if [[ -f "$download_dir/$pattern" ]]; then
            deb_file="$download_dir/$pattern"
            break
        fi
    done

    if [[ -z "$deb_file" ]]; then
        echo -e "${YELLOW}    警告: 找不到版本 $version 的deb包${NC}"
        echo -e "    尝试的文件名:"
        for pattern in "${deb_patterns[@]}"; do
            echo "      - $download_dir/$pattern"
        done
        return 1
    fi

    echo -e "    找到deb包: $deb_file"

    # 检查是否已安装相同版本
    local current_version=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || echo "")
    if [[ "$current_version" == "$version" ]] || [[ "$current_version" =~ ^.*:${version}.*$ ]]; then
        echo -e "${GREEN}    ✅ 包已安装: $current_version${NC}"
    else
        echo -e "    安装主包..."
        # 使用本地密码进行sudo，-p "" 抑制提示输出
        if echo "$LOCAL_PASSWORD" | sudo -S -p "" dpkg -i "$deb_file" >/dev/null 2>&1 || echo "$LOCAL_PASSWORD" | sudo -S -p "" dpkg -i --force-overwrite "$deb_file" >/dev/null 2>&1; then
            echo -e "${GREEN}    ✅ 主包安装成功${NC}"
        else
            echo -e "${YELLOW}    警告: 主包安装失败，但不影响崩溃分析${NC}"
            echo -e "    注意: 系统可能使用不同版本的包进行分析"
        fi
    fi

    # 安装dbgsym包
    local dbgsym_patterns=(
        "${package}-dbgsym_${version}_amd64.deb"
        "${package}-dbgsym_${version}-1_amd64.deb"
        "${package}-dbgsym_1:${version}_amd64.deb"
        "${package}-dbgsym_1:${version}-1_amd64.deb"
    )

    local dbgsym_file=""
    for pattern in "${dbgsym_patterns[@]}"; do
        if [[ -f "$download_dir/$pattern" ]]; then
            dbgsym_file="$download_dir/$pattern"
            break
        fi
    done

    if [[ -n "$dbgsym_file" ]]; then
        echo -e "    找到dbgsym包: $dbgsym_file"

        # 检查dbgsym是否已安装
        if dpkg -l | grep -q "^ii.*${package}-dbgsym.*${version}"; then
            echo -e "${GREEN}    ✅ dbgsym包已安装${NC}"
        else
            echo -e "    安装dbgsym包..."
            # 使用本地密码进行sudo
            if echo "$LOCAL_PASSWORD" | sudo -S -p "" dpkg -i "$dbgsym_file" >/dev/null 2>&1 || echo "$LOCAL_PASSWORD" | sudo -S -p "" dpkg -i --force-overwrite "$dbgsym_file" >/dev/null 2>&1; then
                echo -e "${GREEN}    ✅ dbgsym包安装成功${NC}"
            else
                echo -e "${YELLOW}    警告: dbgsym包安装失败，符号化分析功能可能受限${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}    警告: 未找到dbgsym包，符号化分析功能可能受限${NC}"
    fi

    echo -e "${GREEN}    ✅ 包安装完成${NC}"

    return 0
}

# 验证版本一致性
verify_version() {
    local package="$1"
    local version="$2"
    local code_version="$3"

    echo -e "${CYAN}  → 验证版本一致性${NC}"

    # 清理目标版本
    local target_version=$(clean_version "$version")

    # 检查包文件是否存在
    local download_dir="$4"
    local deb_found=false

    local deb_patterns=(
        "${package}_${version}_amd64.deb"
        "${package}_${version}-1_amd64.deb"
        "${package}_1:${version}_amd64.deb"
        "${package}_1:${version}-1_amd64.deb"
    )

    local package_file=""
    for pattern in "${deb_patterns[@]}"; do
        if [[ -f "$download_dir/$pattern" ]]; then
            deb_found=true
            package_file="$download_dir/$pattern"
            break
        fi
    done

    echo -e "    目标版本: $version (清理后: $target_version)"
    echo -e "    代码版本: $code_version"

    if [[ "$deb_found" = true ]]; then
        echo -e "    包文件存在: $(basename "$package_file")"
        local package_version="downloaded"
    else
        echo -e "    包文件: 未找到"
        local package_version="missing"
    fi

    # 检查版本是否匹配
    local matched=false

    # 精确匹配
    if [[ "$code_version" == "$target_version" ]]; then
        matched=true
    elif [[ "$code_version" =~ $target_version ]]; then
        # 如果版本号包含在代码版本中
        matched=true
    fi

    if [[ "$matched" = true ]]; then
        echo -e "${GREEN}    ✅ 版本一致性验证通过${NC}"
        return 0
    else
        echo -e "${YELLOW}    ⚠️  版本未完全匹配（可能是因为代码库tag名称或下载的包文件名）${NC}"
        echo -e "    目标版本: $target_version"
        echo -e "    代码版本: $code_version"
        return 1
    fi
}

# 生成同步报告
generate_report() {
    local package="$1"
    local version="$2"
    local workspace="$3"
    local code_version="$4"
    local package_version="$5"
    local status="$6"

    local version_dir=$(version_to_filename "$version")
    local output_dir="$workspace/5.崩溃分析/${version_dir}"
    mkdir -p "$output_dir"

    local report_file="$output_dir/sync_report.txt"

    cat > "$report_file" << EOF
版本同步报告
========================================

时间: $(date '+%Y-%m-%d %H:%M:%S')
包名: $package
目标版本: $version

代码版本: $code_version
包版本: $package_version

状态: $status

详细信息:
- 原始版本号: $version
- 清理后版本号: $(clean_version "$version")
- 目录名版本: version_${version_dir}

========================================
EOF

    echo -e "${GREEN}    同步报告已保存: $report_file${NC}"
}

# 主函数
main() {
    parse_args "$@"

    # 清理版本号
    local version_clean=$(clean_version "$VERSION")
    local version_dir=$(version_to_filename "$version_clean")

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}版本同步${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "包名: ${PACKAGE}"
    echo -e "版本: ${VERSION} (清理后: ${version_clean})"
    echo -e "工作目录: ${WORKSPACE}"
    echo ""

    # 仅验证模式
    if [[ "$VERIFY_ONLY" = true ]]; then
        local code_dir="$WORKSPACE/3.代码管理/$PACKAGE"
        local code_version="unknown"

        if [[ -d "$code_dir/.git" ]]; then
            cd "$code_dir"
            code_version=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --abbrev-ref HEAD)
        fi

        local download_dir="$WORKSPACE/4.包管理/下载包"
        verify_version "$PACKAGE" "$VERSION" "$code_version" "$download_dir"
        exit $?
    fi

    local code_version=""
    local package_version=""
    local status="success"

    # 切换代码
    if [[ "$SKIP_CODE" = false ]]; then
        code_version=$(sync_code "$version_clean" "$PACKAGE" "$WORKSPACE")
        if [[ -z "$code_version" ]]; then
            status="partial: code sync failed"
        fi
    else
        echo -e "${YELLOW}  → 跳过代码切换${NC}"
        code_version="skipped"
    fi

    # 安装对应版本的包
    if [[ "$SKIP_PACKAGE" = false ]]; then
        sync_package "$VERSION" "$PACKAGE" "$WORKSPACE" || status="partial: package install failed"
        local download_dir="$WORKSPACE/4.包管理/下载包"
        local package_file=""
        local deb_patterns=(
            "${PACKAGE}_${VERSION}_amd64.deb"
            "${PACKAGE}_${VERSION}-1_amd64.deb"
            "${PACKAGE}_1:${VERSION}_amd64.deb"
            "${PACKAGE}_1:${VERSION}-1_amd64.deb"
        )

        for pattern in "${deb_patterns[@]}"; do
            if [[ -f "$download_dir/$pattern" ]]; then
                package_file="$download_dir/$pattern"
                break
            fi
        done

        if [[ -n "$package_file" ]]; then
            package_version=$(basename "$package_file" | sed "s/${PACKAGE}_//" | sed "s/_amd64.deb//" | sed "s/${PACKAGE}-dbgsym_//" | head -1)
        else
            package_version="not found"
        fi
    else
        echo -e "${YELLOW}  → 跳过包安装${NC}"
        package_version="skipped"
    fi

    # 验证版本一致性
    if [[ "$SKIP_CODE" = false ]] && [[ "$SKIP_PACKAGE" = false ]]; then
        local download_dir="$WORKSPACE/4.包管理/下载包"
        if ! verify_version "$PACKAGE" "$VERSION" "$code_version" "$download_dir"; then
            status="warning: version mismatch"
        fi
    fi

    # 生成报告
    generate_report "$PACKAGE" "$VERSION" "$WORKSPACE" "$code_version" "$package_version" "$status"

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [[ "$status" == "success" ]]; then
        echo -e "${GREEN}✅ 版本同步完成${NC}"
    else
        echo -e "${YELLOW}⚠️  版本同步完成（有警告）: ${status}${NC}"
    fi
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [[ "$status" != "success" ]]; then
        exit 1
    fi
}

# 运行
main "$@"
