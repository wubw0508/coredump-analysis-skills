#!/bin/bash
#=============================================================================
# 创建补丁脚本
# 功能：为可修复的崩溃生成补丁文件
#=============================================================================

set -e

# 配色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 帮助信息
show_help() {
    cat << EOF
${BLUE}=============================================================================
  创建补丁脚本 - 为可修复的崩溃生成补丁文件
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 [选项] --package <name> --version <version> --workspace <dir>

${GREEN}选项:${NC}
    --package <name>       包名（必需）
    --version <version>    版本号（必需）
    --workspace <dir>      工作目录（必需）
    --with-ai             使用AI生成修复代码（需要额外工具）
    --help, -h            显示此帮助信息

${GREEN}示例:${NC}
    $0 --package dde-session-ui --version 1:5.9.6-1 --workspace /path/to/workspace

${BLUE}=============================================================================
${NC}
EOF
}

# 解析参数
parse_args() {
    PACKAGE=""
    VERSION=""
    WORKSPACE=""
    WITH_AI=false

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
            --with-ai)
                WITH_AI=true
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

# 版本号清理
clean_version() {
    local version="$1"
    version=$(echo "$version" | sed 's/^1://' | sed 's/-1$//')
    echo "$version"
}

# 版本号转目录名
version_to_dir() {
    local version="$1"
    echo "$version" | sed 's/\./_/g' | sed 's/+/_/g' | sed 's/-/_/g'
}

# 查找源文件
find_source_file() {
    local package="$1"
    local symbol="$2"
    local workspace="$3"

    local code_dir="$workspace/3.代码管理/$package"

    if [[ ! -d "$code_dir" ]]; then
        echo ""
        return 1
    fi

    # 清理符号名称，提取函数名
    local func_name=$(echo "$symbol" | sed 's/[(].*//' | sed 's/^.*:://')

    # 搜索包含该函数的文件
    local found_files=$(cd "$code_dir" && grep -r "${func_name}" --include="*.cpp" --include="*.c" --include="*.h" --include="*.hpp" -l 2>/dev/null | head -5)

    echo "$found_files"
    return 0
}

# 生成修复代码
generate_fix_code() {
    local fix_type="$1"
    local symbol="$2"

    case "$fix_type" in
        "添加空指针检查")
            echo "if (${symbol}) {"
            echo "    // 原有代码"
            echo "}"
            ;;
        "使用智能指针或置NULL")
            echo "delete ptr;"
            echo "ptr = nullptr;"
            ;;
        "添加边界检查")
            echo "if (index >= 0 && index < size) {"
            echo "    // 原有代码"
            echo "}"
            ;;
        "初始化变量")
            echo "Type var = initial_value;"
            ;;
        "添加除零检查")
            echo "if (denominator != 0) {"
            echo "    result = numerator / denominator;"
            echo "}"
            ;;
        "修复断言条件或添加错误处理")
            echo "if (!condition) {"
            echo "    // 错误处理代码"
            echo "    return error_code;"
            echo "}"
            ;;
        *)
            echo "// TODO: 需要手动添加修复代码"
            ;;
    esac
}

# 生成补丁文件
create_patch() {
    local package="$1"
    local version="$2"
    local crash="$3"
    local workspace="$4"
    local with_ai="$5"

    local crash_id=$(echo "$crash" | jq -r '.id' | head -c 10)
    local crash_signal=$(echo "$crash" | jq -r '.signal')
    local crash_symbol=$(echo "$crash" | jq -r '.app_layer_symbol' | tr -d '():,')
    local crash_count=$(echo "$crash" | jq -r '.count')
    local fix_type=$(echo "$crash" | jq -r '.fix_type')
    local fix_reason=$(echo "$crash" | jq -r '.fix_reason')

    # 查找源文件
    local source_files=$(find_source_file "$package" "$crash_symbol" "$workspace")

    local version_dir=$(version_to_dir "$(clean_version "$version")")
    local patch_dir="$workspace/5.崩溃分析/version_${version_dir}/patches"
    mkdir -p "$patch_dir"

    local patch_file="$patch_dir/patch_${crash_id}_${crash_signal}.patch"

    # 生成补丁头部
    cat > "$patch_file" << EOF
# 崩溃修复补丁
#
# 包名: $package
# 版本: $version
# 崩溃ID: $(echo "$crash" | jq -r '.id')
# 崩溃次数: $crash_count
# 信号类型: $crash_signal
# 应用层函数: $crash_symbol
#
# 问题描述:
# - 原因: $fix_reason
#
# 修复建议:
# - 类型: $fix_type
#
EOF

    # 添加源文件信息
    if [[ -n "$source_files" ]]; then
        cat >> "$patch_file" << EOF
# 可能的源文件:
EOF
        while IFS= read -r file; do
            echo "#   - $file" >> "$patch_file"
        done <<< "$source_files"
        echo "" >> "$patch_file"
    else
        cat >> "$patch_file" << EOF
# 注意: 无法自动定位源文件， 请在代码仓库中手动搜索函数: $crash_symbol
#
EOF
    fi

    # 生成修复代码
    cat >> "$patch_file" << EOF
# 修复代码示例:
# =================
EOF

    generate_fix_code "$fix_type" "$crash_symbol" >> "$patch_file"

    echo "" >> "$patch_file"
    cat >> "$patch_file" << EOF
# =================
#
# 修复步骤:
# 1. 在代码仓库中搜索函数: $crash_symbol
# 2. 定位到崩溃点
# 3. 添加上述修复代码
# 4. 编译测试
# 5. 提交并创建PR/Change
#
# Gerrit提交信息建议:
# -------------------
# [coredump-analysis] fix: 修复 $crash_symbol 导致的崩溃
#
# 崩溃信息:
# - 包名: $package
# - 崩溃版本: $version
# - 架构: <arch>
# - 系统版本: $(echo "$crash" | jq -r '.sys_v_number // "unknown"')
# - Crash ID: $(echo "$crash" | jq -r '.id')
# - Crash Count: $crash_count
# - Signal: $crash_signal
# - App Layer: $crash_symbol
# - 修复详细堆栈:
# $(echo "$crash" | jq -r '.stack_info // "N/A"' | head -n 8)
#
# 本次修复说明:
# - Root Cause: $fix_reason
# - Fix: $fix_type
#
# Log: 基于产品说明补充本次修复内容
# Influence: 影响哪些功能点
#
EOF

    echo "$patch_file"
}

# 主函数
main() {
    parse_args "$@"

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}创建补丁文件${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "包名: ${PACKAGE}"
    echo -e "版本: ${VERSION}"
    echo -e "工作目录: ${WORKSPACE}"
    echo ""

    # 版本号处理
    local version_clean=$(clean_version "$VERSION")
    local version_dir=$(version_to_dir "$version_clean")

    # 读取分析结果
    local analysis_file="$WORKSPACE/5.崩溃分析/version_${version_dir}/analysis.json"

    if [[ ! -f "$analysis_file" ]]; then
        echo -e "${RED}错误: 分析文件不存在: $analysis_file${NC}"
        echo -e "请先运行 analyze_crash_per_version.py 进行崩溃分析"
        exit 1
    fi

    # 创建补丁目录
    local patch_dir="$WORKSPACE/5.崩溃分析/version_${version_dir}/patches"
    mkdir -p "$patch_dir"

    # 获取可修复的崩溃
    local fixable_crashes=$(jq -c '.crashes[] | select(.fixable == true)' "$analysis_file")

    if [[ -z "$fixable_crashes" ]]; then
        echo -e "${YELLOW}没有可修复的崩溃，无需生成补丁${NC}"
        exit 0
    fi

    echo -e "${CYAN}找到可修复的崩溃，生成补丁文件...${NC}"
    echo ""

    local patch_count=0

    # 为每个可修复的崩溃生成补丁
    echo "$fixable_crashes" | while read -r crash; do
        if [[ -z "$crash" ]]; then
            continue
        fi

        local patch_file=$(create_patch "$PACKAGE" "$VERSION" "$crash" "$WORKSPACE" "$WITH_AI")

        if [[ -n "$patch_file" ]]; then
            echo -e "  ✅ 生成补丁: $(basename "$patch_file")"
            patch_count=$((patch_count + 1))
        fi
    done

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ 补丁文件生成完成${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "补丁目录: $patch_dir"
    echo -e "可以使用 submit_to_gerrit.sh 提交到Gerrit"
    echo ""
}

# 运行
main "$@"
