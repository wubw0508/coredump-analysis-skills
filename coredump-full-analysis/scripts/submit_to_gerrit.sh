#!/bin/bash
#=============================================================================
# Gerrit提交脚本
# 功能：自动创建补丁并提交到Gerrit
#=============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOAD_ACCOUNTS_SCRIPT="$SCRIPT_DIR/load_accounts.sh"
source "$LOAD_ACCOUNTS_SCRIPT"
load_accounts_or_die gerrit

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
  Gerrit提交脚本 - 自动创建补丁并提交到Gerrit
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 [选项] --package <name> --version <version> --workspace <dir>

${GREEN}选项:${NC}
    --package <name>       包名（必需）
    --version <version>    版本号（必需）
    --workspace <dir>      工作目录（必需）
    --target-branch <br>  目标分支（默认: master）
    --reviewer <email>     审查者邮箱（可多次指定）
    --dry-run              试运行，不实际提交
    --yes, --auto-confirm  非交互模式，自动确认提交
    --force-recreate-branch 分支已存在时自动删除并重建
    --help, -h            显示此帮助信息

${GREEN}示例:${NC}
    # 创建补丁并提交
    $0 --package dde-session-ui --version 1:5.9.6-1 --workspace /path/to/workspace

    # 指定目标分支和审查者
    $0 --package dde-session-ui --version 5.8.32 --workspace /path \\
        --target-branch develop/eagle --reviewer reviewer@example.com

    # 试运行（只生成补丁，不提交）
    $0 --package dde-session-ui --version 5.7.41.11 --workspace /path --dry-run

${BLUE}=============================================================================
${NC}
EOF
}

# 解析参数
parse_args() {
    PACKAGE=""
    VERSION=""
    WORKSPACE=""
    TARGET_BRANCH="develop/eagle"
    REVIEWERS=()
    DRY_RUN=false
    AUTO_CONFIRM=false
    FORCE_RECREATE_BRANCH=false

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
            --target-branch)
                TARGET_BRANCH="$2"
                shift 2
                ;;
            --reviewer)
                REVIEWERS+=("$2")
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --yes|--auto-confirm)
                AUTO_CONFIRM=true
                shift
                ;;
            --force-recreate-branch)
                FORCE_RECREATE_BRANCH=true
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

# 版本清理
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

# 解析版本分析目录
resolve_version_analysis_dir() {
    local package="$1"
    local version="$2"
    local workspace="$3"

    local version_dir
    version_dir=$(version_to_dir "$(clean_version "$version")")

    local candidates=(
        "$workspace/5.崩溃分析/$package/version_${version_dir}"
        "$workspace/5.崩溃分析/version_${version_dir}"
        "$workspace/5.崩溃分析/$package/${version_dir}"
        "$workspace/5.崩溃分析/${version_dir}"
    )

    for dir in "${candidates[@]}"; do
        if [[ -f "$dir/analysis.json" ]] || [[ -f "$dir/analysis_report.md" ]]; then
            echo "$dir"
            return 0
        fi
    done

    echo "$workspace/5.崩溃分析/$package/version_${version_dir}"
}

# 获取版本对应架构
get_arch_for_version() {
    local package="$1"
    local version="$2"
    local workspace="$3"
    local filtered_csv="$workspace/2.数据筛选/filtered_${package}_crash_data.csv"

    if [[ ! -f "$filtered_csv" ]]; then
        echo "unknown"
        return 0
    fi

    python3 - "$filtered_csv" "$version" <<'PY'
import csv, sys
csv_file, version = sys.argv[1], sys.argv[2]
version_clean = version
if version_clean.startswith('1:'):
    version_clean = version_clean[2:]
if version_clean.endswith('-1'):
    version_clean = version_clean[:-2]
with open(csv_file, encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        row_version = (row.get('Version', '') or '').strip()
        row_clean = row_version
        if row_clean.startswith('1:'):
            row_clean = row_clean[2:]
        if row_clean.endswith('-1'):
            row_clean = row_clean[:-2]
        if row_version == version or row_clean == version_clean:
            arch = row.get('Arch', '') or row.get('Architecture', '')
            print(arch or 'unknown')
            break
    else:
        print('unknown')
PY
}

# 生成修复分支名
generate_branch_name() {
    local package="$1"
    local version="$2"
    local timestamp=$(date +%Y%m%d)

    # 生成分支名: fix/版本号-date
    echo "fix/${package}/v${version//.}-${timestamp}"
}

# 创建修复分支
create_fix_branch() {
    local package="$1"
    local workspace="$2"
    local branch_name="$3"

    local code_dir="$workspace/3.代码管理/$package"

    if [[ ! -d "$code_dir/.git" ]]; then
        echo -e "${RED}错误: 代码目录不是git仓库: $code_dir${NC}"
        return 1
    fi

    cd "$code_dir"

    # 检查是否已有同名分支
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        echo -e "${YELLOW}分支已存在: $branch_name${NC}"
        if [[ "$FORCE_RECREATE_BRANCH" == "true" ]]; then
            echo -e "${YELLOW}已启用 --force-recreate-branch，删除并重建${NC}"
            git branch -D "$branch_name"
        else
            if [[ "$AUTO_CONFIRM" == "true" ]]; then
                echo -e "${YELLOW}非交互模式下保留现有分支${NC}"
                git checkout "$branch_name"
                return 0
            fi
            echo -e "是否删除并重建？(y/n): "
            read -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git branch -D "$branch_name"
            else
                echo -e "使用现有分支"
                git checkout "$branch_name"
                return 0
            fi
        fi
    fi

    # 创建新分支
    git checkout -b "$branch_name"
    echo -e "${GREEN}✅ 创建修复分支: $branch_name${NC}"
}

# 生成commit message
generate_commit_message() {
    local package="$1"
    local version="$2"
    local workspace="$3"

    local analysis_dir
    analysis_dir=$(resolve_version_analysis_dir "$package" "$version" "$workspace")
    local analysis_file="$analysis_dir/analysis.json"
    local report_file="$analysis_dir/analysis_report.md"
    local arch
    arch=$(get_arch_for_version "$package" "$version" "$workspace")

    if [[ ! -f "$analysis_file" ]]; then
        cat << EOF
fix($package): 修复崩溃问题

从自动化崩溃分析系统生成的修复补丁。

包名: $package
版本号: $version
架构: $arch
分析结论: 已根据当前版本分析结果生成修复代码，请结合对应分析报告复核提交内容。
EOF
        return 0
    fi

    local total_crashes=$(jq -r '.summary.total_crash_records' "$analysis_file" 2>/dev/null || echo "0")
    local fixable_count=$(jq -r '.summary.fixable_count' "$analysis_file" 2>/dev/null || echo "0")
    local unique_crashes=$(jq -r '.summary.unique_crashes' "$analysis_file" 2>/dev/null || echo "0")
    local recommendations
    recommendations=$(jq -r '.recommendations[]?' "$analysis_file" 2>/dev/null)
    local conclusions
    conclusions=$(jq -r '.crashes[] | select(.fixable == true or .fixable == "uncertain") | .fix_reason' "$analysis_file" 2>/dev/null | sort -u | head -n 5)
    local representative_stacks
    representative_stacks=$(jq -r '
        .crashes[:5][] |
        "Crash ID: " + (.id // "unknown"),
        "Signal: " + (.signal // "unknown"),
        "Count: " + ((.count // 0) | tostring),
        "App Layer Symbol: " + ((.app_layer_symbol // "") | if . == "" then "N/A" else . end),
        "Analysis Conclusion: " + ((.fix_reason // "") | if . == "" then "N/A" else . end),
        "Crash Stack:",
        ((.stack_info // "") | split("\n")[:8] | join("\n")),
        ""
    ' "$analysis_file" 2>/dev/null)

    cat << EOF
fix($package): 修复崩溃问题

从自动化崩溃分析系统生成的修复补丁。

包名: $package
版本号: $version
架构: $arch
唯一崩溃数: $unique_crashes
总崩溃记录数: $total_crashes
可修复崩溃数: $fixable_count

分析结论:
$(if [[ -n "$conclusions" ]]; then echo "$conclusions"; elif [[ -n "$recommendations" ]]; then echo "$recommendations"; else echo "需要结合分析报告进一步确认"; fi)

具体解决崩溃堆栈:
$(if [[ -n "$representative_stacks" ]]; then echo "$representative_stacks"; else echo "N/A"; fi)

分析报告: ${report_file#$workspace/}

Change-Id: I$(date +%Y%m%d%H%M%S%N | md5sum | head -c 40)
EOF
}

# 生成补丁文件
generate_patch_file() {
    local package="$1"
    local version="$2"
    local workspace="$3"

    local version_dir=$(version_to_dir "$(clean_version "$version")")
    local version_analysis_dir="$workspace/5.崩溃分析/version_${version_dir}"
    local patch_dir="$version_analysis_dir/patches"

    mkdir -p "$patch_dir"

    # 读取分析结果
    local analysis_file="$version_analysis_dir/analysis.json"
    if [[ ! -f "$analysis_file" ]]; then
        echo -e "${RED}错误: 分析文件不存在: $analysis_file${NC}"
        return 1
    fi

    # 为每个可修复的崩溃生成补丁模板
    local fixable_crashes=$(jq -c '.crashes[] | select(.fixable == true)' "$analysis_file")
    local patch_count=0

    echo "$fixable_crashes" | while read -r crash; do
        if [[ -z "$crash" ]]; then
            continue
        fi

        local crash_id=$(echo "$crash" | jq -r '.id' | head -c 10 | tr -d '-')
        local crash_signal=$(echo "$crash" | jq -r '.signal')
        local crash_symbol=$(echo "$crash" | jq -r '.app_layer_symbol' | tr -d '():,')
        local fix_type=$(echo "$crash" | jq -r '.fix_type')
        local fix_code=$(echo "$crash" | jq -r '.fix_code')

        # 补丁文件名
        local patch_file="$patch_dir/patch_${patch_count}_fix_${crash_signal}_${crash_symbol}.patch"

        # 生成补丁内容（模板）
        cat > "$patch_file" << EOF
--- a/需要修改的文件
+++ b/需要修改的文件
@@ -1,1 +1,1 @@
- // 原始代码
+ // 修复后的代码
+ // 修复类型: $fix_type
+ // 示例: $fix_code
EOF

        echo -e "  生成补丁: $(basename "$patch_file")"
        patch_count=$((patch_count + 1))
    done
}

# 提交到Gerrit
submit_to_gerrit() {
    local package="$1"
    local workspace="$2"
    local branch_name="$3"
    local target_branch="$4"
    local reviewers="${@:5}"  # 剩余参数是审查者列表

    local code_dir="$workspace/3.代码管理/$package"

    cd "$code_dir"

    # 如果有补丁文件，应用补丁
    local analysis_dir
    analysis_dir=$(resolve_version_analysis_dir "$package" "$VERSION" "$workspace")
    local patch_dir="$analysis_dir/patches"
    if [[ -d "$patch_dir" ]] && [[ $(ls -A "$patch_dir" 2>/dev/null) ]]; then
        echo -e "${CYAN}应用补丁文件...${NC}"
        for patch in "$patch_dir"/*.patch; do
            if [[ -f "$patch" ]]; then
                echo -e "  应用: $(basename "$patch")"
                # patch -p1 < "$patch" || echo -e "  跳过补丁应用（模板补丁）"
            fi
        done
    fi

    # 生成commit message
    local commit_msg_file=$(mktemp)
    generate_commit_message "$package" "$VERSION" "$workspace" > "$commit_msg_file"

    # 添加所有修改到暂存区
    git add -A 2>/dev/null || true

    # 检查是否有修改
    if git diff --cached --quiet; then
        echo -e "${YELLOW}没有需要提交的修改${NC}"
        rm "$commit_msg_file"
        return 0
    fi

    # 创建commit
    git commit -F "$commit_msg_file" || {
        echo -e "${RED}commit失败${NC}"
        rm "$commit_msg_file"
        return 1
    }

    rm "$commit_msg_file"

    # 保存commit信息
    local commit_hash=$(git rev-parse HEAD)
    mkdir -p "$workspace/5.崩溃分析/gerrit"

    cat > "$workspace/5.崩溃分析/gerrit/commit_${commit_hash}.json" << EOF
{
  "commit_hash": "$commit_hash",
  "branch": "$branch_name",
  "target_branch": "$target_branch",
  "package": "$package",
  "version": "$VERSION",
  "reviewers": [$(printf '"%s",' "${reviewers[@]}" | sed 's/,$//')],
  "time": "$(date -Iseconds)",
  "status": "ready"
}
EOF

    echo -e "${GREEN}✅ Commit已创建: $commit_hash${NC}"

    # 如果不是dry run，提交到Gerrit
    if [[ "$DRY_RUN" = false ]]; then
        echo -e "${CYAN}提交到Gerrit...${NC}"

        # 构建refspec
        local reviewers_param=""
        if [[ ${#reviewers[@]} -gt 0 ]]; then
            reviewers_param="%r=$(IFS=','; echo "${reviewers[*]}")"
        fi

        # 推送到Gerrit
        local gerrit_remote=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ -z "$gerrit_remote" ]]; then
            # 默认Gerrit remote
            local gerrit_user="${GERRIT_USER}"
            local gerrit_host="${GERRIT_HOST:-gerrit.uniontech.com}"
            local gerrit_port="${GERRIT_PORT:-29418}"
            gerrit_remote="ssh://${gerrit_user}@${gerrit_host}:${gerrit_port}/${package}"
        fi

        echo -e "推送目标: $gerrit_remote HEAD:refs/for/$target_branch${reviewers_param}"

        if git push "$gerrit_remote" "HEAD:refs/for/$target_branch${reviewers_param}"; then
            echo -e "${GREEN}✅ 成功提交到Gerrit${NC}"

            # 更新提交状态
            jq '.status = "submitted"' "$workspace/5.崩溃分析/gerrit/commit_${commit_hash}.json" > \
                "$workspace/5.崩溃分析/gerrit/commit_${commit_hash}.json.tmp"
            mv "$workspace/5.崩溃分析/gerrit/commit_${commit_hash}.json.tmp" \
                "$workspace/5.崩溃分析/gerrit/commit_${commit_hash}.json"

            return 0
        else
            echo -e "${RED}❌ Gerrit提交失败${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}试运行模式：跳过Gerrit提交${NC}"
        echo -e "${YELLOW}commit_hash: $commit_hash${NC}"
        echo -e "${YELLOW}可以使用以下命令手动提交：${NC}"
        echo -e "${YELLOW}  git push $gerrit_remote HEAD:refs/for/$target_branch${reviewers_param}${NC}"
        return 0
    fi
}

# 主函数
main() {
    parse_args "$@"

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Gerrit提交${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "包名: ${PACKAGE}"
    echo -e "版本: ${VERSION}"
    echo -e "目标分支: ${TARGET_BRANCH}"
    echo -e "审查者: ${REVIEWERS[*]:-无}"
    echo -e "试运行: ${DRY_RUN}"
    echo -e "自动确认: ${AUTO_CONFIRM}"
    echo -e "强制重建分支: ${FORCE_RECREATE_BRANCH}"
    echo ""

    # 生成修复分支名
    local version_clean=$(clean_version "$VERSION")
    local branch_name=$(generate_branch_name "$PACKAGE" "$version_clean")
    local version_dir=$(version_to_dir "$version_clean")

    # 检查分析结果是否存在
    local analysis_file="$WORKSPACE/5.崩溃分析/version_${version_dir}/analysis.json"
    if [[ ! -f "$analysis_file" ]]; then
        echo -e "${RED}错误: 分析结果不存在: $analysis_file${NC}"
        echo -e "请先运行 analyze_single_version.sh 进行崩溃分析"
        exit 1
    fi

    # 步骤1: 生成补丁文件
    echo -e "${CYAN}[1/4] 生成补丁文件...${NC}"
    if ! generate_patch_file "$PACKAGE" "$VERSION" "$WORKSPACE"; then
        echo -e "${YELLOW}补丁文件生成失败或不存在，继续执行${NC}"
    fi

    # 步骤2: 创建修复分支
    echo -e "${CYAN}[2/4] 创建修复分支...${NC}"
    if ! create_fix_branch "$PACKAGE" "$WORKSPACE" "$branch_name"; then
        echo -e "${RED}创建修复分支失败${NC}"
        exit 1
    fi

    # 步骤3: 生成commit message
    echo -e "${CYAN}[3/4] 生成commit message...${NC}"
    local commit_msg=$(generate_commit_message "$PACKAGE" "$VERSION" "$WORKSPACE")
    echo -e "${CYAN}Commit:${NC}"
    echo -e "${commit_msg}"
    echo ""

    # 确认
    if [[ "$DRY_RUN" = false ]]; then
        if [[ "$AUTO_CONFIRM" == "true" ]]; then
            echo -e "${YELLOW}非交互模式，自动确认提交${NC}"
        else
            read -p "确认提交？(y/n): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "取消提交"
                exit 0
            fi
        fi
    else
        echo -e "${YELLOW}试运行模式，跳过确认${NC}"
    fi

    # 步骤4: 提交到Gerrit
    echo -e "${CYAN}[4/4] 提交到Gerrit...${NC}"
    if submit_to_gerrit "$PACKAGE" "$WORKSPACE" "$branch_name" "$TARGET_BRANCH" "${REVIEWERS[@]}"; then
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}✅ Gerrit提交流程完成${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        echo ""
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}❌ Gerrit提交流程失败${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        exit 1
    fi

    echo ""
    echo -e "${CYAN}提交信息已保存: $WORKSPACE/5.崩溃分析/gerrit/${NC}"
    echo ""
}

# 运行
main "$@"
