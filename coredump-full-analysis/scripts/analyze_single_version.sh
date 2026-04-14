#!/bin/bash
#=============================================================================
# 单版本分析脚本
# 功能：分析单个版本的崩溃，包括版本同步、崩溃分析和修复/文档生成
#=============================================================================

set -e

# 配色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Skills脚本目录
SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 帮助信息
show_help() {
    cat << EOF
${BLUE}=============================================================================
  单版本分析脚本 - 分析指定版本的崩溃
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 [选项] --package <name> --version <version> --workspace <dir>

${GREEN}选项:${NC}
    --package <name>       包名（必需）
    --version <version>    版本号（必需）
    --workspace <dir>      工作目录（必需）
    --auto-submit-gerrit  自动提交到Gerrit（默认: false）
    --skip-sync           跳过版本同步
    --skip-analysis       跳过崩溃分析
    --help, -h            显示此帮助信息

${GREEN}示例:${NC}
    # 完整分析（同步 + 分析 + 修复）
    $0 --package dde-session-ui --version 1:5.9.6-1 --workspace /path/to/workspace

    # 仅分析，不同步
    $0 --package dde-session-ui --version 5.8.32 --workspace /path --skip-sync

    # 自动提交Gerrit
    $0 --package dde-session-ui --version 5.7.41.11 --workspace /path --auto-submit-gerrit

${BLUE}=============================================================================
${NC}
EOF
}

# 解析参数
parse_args() {
    PACKAGE=""
    VERSION=""
    WORKSPACE=""
    AUTO_SUBMIT_GERRIT="false"
    SKIP_SYNC=false
    SKIP_ANALYSIS=false

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
            --auto-submit-gerrit)
                AUTO_SUBMIT_GERRIT="true"
                shift
                ;;
            --skip-sync)
                SKIP_SYNC=true
                shift
                ;;
            --skip-analysis)
                SKIP_ANALYSIS=true
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

# 步骤1: 版本同步
step1_sync() {
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}步骤 1: 版本同步${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [[ "$SKIP_SYNC" = true ]]; then
        echo -e "${YELLOW}  → 跳过版本同步${NC}"
        return 0
    fi

    # 使用skills目录中的sync_version.sh
    local sync_script="$SKILLS_DIR/sync_version.sh"

    if [[ ! -f "$sync_script" ]]; then
        echo -e "${RED}    错误: sync_version.sh 不存在: $sync_script${NC}"
        return 1
    fi

    chmod +x "$sync_script"

    if bash "$sync_script" --package "$PACKAGE" --version "$VERSION" --workspace "$WORKSPACE"; then
        echo -e "${GREEN}  ✅ 版本同步成功${NC}"
        return 0
    else
        echo -e "${YELLOW}  ⚠️  版本同步有警告，但继续分析${NC}"
        return 0
    fi
}

# 步骤2: 崩溃分析
step2_analyze() {
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}步骤 2: 崩溃分析${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [[ "$SKIP_ANALYSIS" = true ]]; then
        echo -e "${YELLOW}  → 跳过崩溃分析${NC}"
        return 0
    fi

    # 使用skills目录中的analyze_crash_per_version.py
    local analyze_script="$SKILLS_DIR/analyze_crash_per_version.py"

    if [[ ! -f "$analyze_script" ]]; then
        echo -e "${RED}    错误: analyze_crash_per_version.py 不存在: $analyze_script${NC}"
        return 1
    fi

    chmod +x "$analyze_script"

    if python3 "$analyze_script" \
        --package "$PACKAGE" \
        --version "$VERSION" \
        --workspace "$WORKSPACE"; then

        # 获取分析结果
        local version_clean=$(clean_version "$VERSION")
        local version_dir=$(version_to_dir "$version_clean")
        local analysis_file="$WORKSPACE/5.崩溃分析/${version_dir}/analysis.json"

        if [[ -f "$analysis_file" ]]; then
            # 分析结果
            local total=$(jq -r '.summary.unique_crashes' "$analysis_file" 2>/dev/null || echo "0")
            local fixable=$(jq -r '.summary.fixable_count' "$analysis_file" 2>/dev/null || echo "0")
            local total_count=$(jq -r '.summary.total_crash_records' "$analysis_file" 2>/dev/null || echo "0")

            echo ""
            echo -e "${CYAN}分析摘要:${NC}"
            echo -e "  唯一崩溃数: $total"
            echo -e "  总崩溃次数: $total_count"
            echo -e "  可修复: $fixable"
            echo -e "  分析报告: $analysis_file"

            echo "$analysis_file"
        fi

        echo -e "${GREEN}  ✅ 崩溃分析完成${NC}"
        return 0
    else
        echo -e "${RED}    ❌ 崩溃分析失败${NC}"
        return 1
    fi
}

# 步骤3: 处理修复（创建补丁或生成文档）
step3_process_fixes() {
    local analysis_file="$1"

    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}步骤 3: 处理修复${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [[ ! -f "$analysis_file" ]]; then
        echo -e "${YELLOW}  → 没有分析结果，跳过${NC}"
        return 0
    fi

    local version_clean=$(clean_version "$VERSION")
    local version_dir=$(version_to_dir "$version_clean")
    local output_dir="$WORKSPACE/5.崩溃分析/${version_dir}"

    # 统计可修复和不可修复的崩溃
    local fixable=$(jq -r '.crashes[] | select(.fixable == true) | .count' "$analysis_file" | awk '{s+=$1} END {print s+0}')
    local non_fixable=$(jq -r '.crashes[] | select(.fixable == false) | .count' "$analysis_file" | awk '{s+=$1} END {print s+0}')
    local uncertain=$(jq -r '.crashes[] | select(.fixable == "uncertain") | .count' "$analysis_file" | awk '{s+=$1} END {print s+0}')

    local total_fixable_crashes=$(jq -r '.summary.fixable_count' "$analysis_file" 2>/dev/null || echo "0")
    local total_non_fixable=$(jq -r '.summary.non_fixable_count' "$analysis_file" 2>/dev/null || echo "0")
    local total_uncertain=$(jq -r '.summary.uncertain_count' "$analysis_file" 2>/dev/null || echo "0")

    echo -e "${CYAN}修复统计:${NC}"
    echo -e "  可修复: $total_fixable_crashes 个崩溃，共 $fixable 次记录"
    echo -e "  不可修复: $total_non_fixable 个崩溃，共 $non_fixable 次记录"
    echo -e "  需人工判断: $total_uncertain 个崩溃，共 $uncertain 次记录"
    echo ""

    # 处理可修复的崩溃
    if [[ "$total_fixable_crashes" -gt 0 ]]; then
        echo -e "${CYAN}  → 处理可修复崩溃...${NC}"

        # 提取可修复的崩溃信息
        local fixable_crashes=$(jq -c '.crashes[] | select(.fixable == true)' "$analysis_file")

        # 创建补丁目录
        mkdir -p "$output_dir/fixes"

        echo "$fixable_crashes" | while read -r crash; do
            if [[ -z "$crash" ]]; then
                continue
            fi

            local crash_id=$(echo "$crash" | jq -r '.id' | head -c 10)
            local crash_signal=$(echo "$crash" | jq -r '.signal')
            local crash_symbol=$(echo "$crash" | jq -r '.app_layer_symbol')
            local crash_count=$(echo "$crash" | jq -r '.count')
            local fix_type=$(echo "$crash" | jq -r '.fix_type')
            local fix_reason=$(echo "$crash" | jq -r '.fix_reason')

            # 生成补丁文件
            local patch_file="$output_dir/fixes/patch_${crash_id}.txt"
            cat > "$patch_file" << EOF
崩溃修复补丁: ${crash_id}
=====================================

包名: $PACKAGE
版本: $VERSION
崩溃ID: $(echo "$crash" | jq -r '.id')
崩溃次数: $crash_count
信号类型: $crash_signal
应用层函数: $crash_symbol

问题描述:
- 原因: $fix_reason

修复建议:
- 类型: $fix_type

修复步骤:
1. 定位到崩溃函数: $crash_symbol
2. 检查函数参数和返回值
3. 添加相应的检查代码

注意:
- 需要切换到相应版本代码
- 修改后需要测试
- 提交时需要关联崩溃ID

EOF

            echo -e "    生成补丁文件: $(basename "$patch_file")"
        done

        # 提交到Gerrit（如果启用）
        if [[ "$AUTO_SUBMIT_GERRIT" = true ]]; then
            echo -e "${CYAN}  → 提交补丁到Gerrit...${NC}"

            # 使用skills目录中的submit_to_gerrit.sh
            local gerrit_script="$SKILLS_DIR/submit_to_gerrit.sh"

            if [[ -f "$gerrit_script" ]]; then
                chmod +x "$gerrit_script"

                if bash "$gerrit_script" \
                    --package "$PACKAGE" \
                    --version "$VERSION" \
                    --workspace "$WORKSPACE"; then
                    echo -e "${GREEN}    ✅ Gerrit提交成功${NC}"
                else
                    echo -e "${YELLOW}    ⚠️  Gerrit提交失败，请检查错误${NC}"
                fi
            else
                echo -e "${YELLOW}    警告: submit_to_gerrit.sh 不存在: $gerrit_script${NC}"
            fi
        else
            echo -e "${YELLOW}    → 已生成补丁文件，使用 --auto-submit-gerrit 参数提交到Gerrit${NC}"
        fi
    fi

    # 处理不可修复的崩溃
    if [[ "$total_non_fixable" -gt 0 ]]; then
        echo -e "${CYAN}  → 处理不可修复崩溃...${NC}"

        # 创建问题文档目录
        mkdir -p "$output_dir/issues"

        local non_fixable_crashes=$(jq -c '.crashes[] | select(.fixable == false)' "$analysis_file")

        echo "$non_fixable_crashes" | while read -r crash; do
            if [[ -z "$crash" ]]; then
                continue
            fi

            local crash_id=$(echo "$crash" | jq -r '.id' | head -c 10)
            local crash_signal=$(echo "$crash" | jq -r '.signal')
            local crash_symbol=$(echo "$crash" | jq -r '.app_layer_symbol')
            local crash_count=$(echo "$crash" | jq -r '.count')
            local fix_reason=$(echo "$crash" | jq -r '.fix_reason')

            # 生成问题文档
            local issue_file="$output_dir/issues/issue_${crash_id}.md"
            cat > "$issue_file" << EOF
# 崩溃问题文档: ${crash_id}

**包名**: $PACKAGE
**版本**: $VERSION
**崩溃ID**: $(echo "$crash" | jq -r '.id')
**崩溃次数**: $crash_count
**信号类型**: $crash_signal
**应用层函数**: $crash_symbol

## 问题原因

$fix_reason

## 崩溃详情

$(echo "$crash" | jq -r '.description')

## 分析结论

此崩溃位于系统库或第三方库中，需要在应用层面进行防护处理。

## 建议处理方式

1. 检查应用代码中传递给库的参数是否正确
2. 添加参数验证和错误处理
3. 检查对象生命周期管理
4. 如需上游修复，提供完整的崩溃堆栈和复现步骤

## 堆栈信息

\`\`\`
$(echo "$crash" | jq -r '.stack_info' | head -n 20)
\`\`\`
EOF

            echo -e "    生成问题文档: $(basename "$issue_file")"
        done
    fi

    echo -e "${GREEN}  ✅ 修复处理完成${NC}"
}

# 主函数
main() {
    parse_args "$@"

    echo ""
    echo -e "${BLUE}"
    echo "============================================================================="
    echo "               单版本分析: $PACKAGE $VERSION"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "工作目录: ${WORKSPACE}"
    echo -e "自动提交Gerrit: ${AUTO_SUBMIT_GERRIT}"
    echo ""

    local analysis_file=""
    local exit_code=0

    # 步骤1: 版本同步
    if ! step1_sync "$WORKSPACE"; then
        echo -e "${RED}版本同步失败，继续执行后续步骤${NC}"
        exit_code=1
    fi

    # 步骤2: 崩溃分析
    if ! step2_analyze; then
        echo -e "${RED}崩溃分析失败${NC}"
        exit_code=1
    else
        # 获取分析结果文件路径
        local version_clean=$(clean_version "$VERSION")
        local version_dir=$(version_to_dir "$version_clean")
        analysis_file="$WORKSPACE/5.崩溃分析/${version_dir}/analysis.json"
    fi

    # 步骤3: 处理修复
    if [[ -n "$analysis_file" ]] && [[ -f "$analysis_file" ]]; then
        step3_process_fixes "$analysis_file"
    elif [[ "$SKIP_ANALYSIS" = false ]]; then
        echo -e "${YELLOW}没有找到分析结果，跳过修复处理${NC}"
    fi

    echo ""
    echo -e "${BLUE}============================================================================="
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✅ 版本 $VERSION 分析完成${NC}"
    else
        echo -e "${YELLOW}⚠️  版本 $VERSION 分析完成（有错误）${NC}"
    fi
    echo -e "${BLUE}============================================================================="
    echo ""

    exit $exit_code
}

# 运行
main "$@"
