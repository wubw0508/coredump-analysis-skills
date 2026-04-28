#!/bin/bash
#=============================================================================
# 崩溃分析完整流程 - 包含下载、安装、分析、修复提交
# 按版本逐个处理，每个崩溃都分析
#=============================================================================

set -e

# 配色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.openclaw/skills/coredump-analysis-skills}"
LOAD_ACCOUNTS_SCRIPT="$SCRIPT_DIR/load_accounts.sh"

# 工作目录优先级：--workspace > WORKSPACE 环境变量 > 账户配置根目录/home
WORKSPACE="${WORKSPACE:-}"
source "$LOAD_ACCOUNTS_SCRIPT"
load_accounts_or_die system

PACKAGE=""
START_VERSION=""
END_VERSION=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace)
                WORKSPACE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$PACKAGE" ]]; then
                    PACKAGE="$1"
                elif [[ -z "$START_VERSION" ]]; then
                    START_VERSION="$1"
                elif [[ -z "$END_VERSION" ]]; then
                    END_VERSION="$1"
                else
                    echo -e "${RED}错误: 未知参数: $1${NC}"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

show_help() {
    cat << EOF
${BLUE}=============================================================================
崩溃分析完整流程 - 下载、安装、分析、修复提交${NC}

${GREEN}用法:${NC}
    $0 [--workspace <dir>] <package> [start_version] [end_version]

${GREEN}示例:${NC}
    $0 dde-dock                    # 分析dde-dock所有版本
    $0 dde-dock 5.7.28.2          # 只分析5.7.28.2
    $0 dde-launcher 5.6.15 5.7.20 # 分析指定版本范围
    $0 --workspace /path/to/workspace dde-dock

${GREEN}完整流程:${NC}
    1. 切换到版本分支（或develop/eagle）
    2. 下载该版本的deb包和调试包
    3. 安装deb包和调试包
    4. 分析所有崩溃
    5. 如果有应用层崩溃：
       - 基于origin/develop/eagle创建修复分支
       - 累积提交所有修复
    6. 切换到下一版本

${BLUE}=============================================================================${NC}
EOF
}

parse_args "$@"

if [[ -z "$PACKAGE" ]]; then
    show_help
    exit 1
fi

if [[ -z "$WORKSPACE" ]]; then
    workspace_root="${ACCOUNTS_WORKSPACE_ROOT:-$HOME}"
    [[ -z "$workspace_root" ]] && workspace_root="$HOME"
    WORKSPACE="$workspace_root/coredump-workspace-$(date +%Y%m%d-%H%M%S)"
fi

echo ""
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}         崩溃分析完整流程 - ${PACKAGE}${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo ""

# 工作目录
CODE_DIR="$WORKSPACE/3.代码管理/$PACKAGE"
PKG_DOWNLOAD_DIR="$WORKSPACE/4.包管理/下载包/downloads"
FILTERED_CSV="$WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv"
STATS_JSON="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"
REPORT_FILE="$WORKSPACE/5.崩溃分析/${PACKAGE}_crash_analysis_report.md"

# 检查必要文件
if [[ ! -f "$FILTERED_CSV" ]]; then
    echo -e "${RED}错误: 筛选后的CSV不存在: $FILTERED_CSV${NC}"
    echo "请先执行: python3 filter_crash_data.py $PACKAGE"
    exit 1
fi

if [[ ! -d "$CODE_DIR" ]]; then
    echo -e "${RED}错误: 代码目录不存在: $CODE_DIR${NC}"
    echo "请先克隆代码"
    exit 1
fi

# 确保下载目录存在
mkdir -p "$PKG_DOWNLOAD_DIR"

# 获取所有版本（按崩溃次数排序）
echo "获取版本列表..."
VERSIONS=$(python3 << EOF
import json
import csv

with open('$STATS_JSON', 'r') as f:
    stats = json.load(f)

versions = []
for ver, data in stats.get('by_version', {}).items():
    versions.append((ver, data['total_crashes']))

versions.sort(key=lambda x: -x[1])
for v, c in versions:
    print(f"{v}:{c}")
EOF
)

if [[ -z "$VERSIONS" ]]; then
    echo -e "${RED}错误: 无法获取版本列表${NC}"
    exit 1
fi

echo ""
echo "版本列表（按崩溃次数排序）:"
echo "$VERSIONS" | head -10
echo "..."
echo ""

# 创建报告文件头
cat > "$REPORT_FILE" << EOF
# ${PACKAGE} 崩溃分析报告

**分析时间**: $(date '+%Y-%m-%d %H:%M:%S')
**包名**: ${PACKAGE}

## 统计摘要

EOF

python3 << EOF >> "$REPORT_FILE"
import json

with open('$STATS_JSON', 'r') as f:
    stats = json.load(f)

summary = stats.get('summary', {})
print(f"- 原始记录数: {summary.get('total_records', 0)}")
print(f"- 唯一崩溃数: {summary.get('unique_crashes', 0)}")
print(f"- 版本数: {summary.get('versions_count', 0)}")
EOF

cat >> "$REPORT_FILE" << 'EOF'

## 版本分析详情

EOF

# 统计
TOTAL_VERSIONS=0
ANALYZED_VERSIONS=0
TOTAL_CRASHES=0
TOTAL_FIXED=0
TOTAL_SKIPPED=0

# 遍历每个版本
while IFS=: read -r VERSION CRASH_COUNT; do
    TOTAL_VERSIONS=$((TOTAL_VERSIONS + 1))
    TOTAL_CRASHES=$((TOTAL_CRASHES + CRASH_COUNT))

    # 版本过滤（支持精确匹配或范围匹配）
    if [[ -n "$START_VERSION" ]]; then
        # 清理版本号进行比较
        VERSION_COMPARE=$(echo "$VERSION" | sed 's/-1$//' | sed 's/\+.*$//')
        START_COMPARE=$(echo "$START_VERSION" | sed 's/-1$//' | sed 's/\+.*$//')
        END_COMPARE="${END_VERSION:-$START_VERSION}"

        # 如果只指定了开始版本，只分析该版本
        if [[ "$VERSION_COMPARE" != "$START_COMPARE" ]]; then
            if [[ -n "$END_VERSION" ]]; then
                # 范围模式：检查是否在范围内
                if [[ "$VERSION_COMPARE" < "$START_COMPARE" ]] || [[ "$VERSION_COMPARE" > "$END_COMPARE" ]]; then
                    continue
                fi
            else
                continue
            fi
        fi
    fi

    ANALYZED_VERSIONS=$((ANALYZED_VERSIONS + 1))

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}版本: $VERSION ($CRASH_COUNT 次崩溃)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # 清理版本号（用于git tag和包名）
    VERSION_CLEAN=$(echo "$VERSION" | sed 's/-1$//' | sed 's/\+.*$//')

    # --------------------
    # 步骤1: 切换分支
    # --------------------
    echo ""
    echo -e "${CYAN}[步骤1] 切换到版本分支${NC}"

    cd "$CODE_DIR"
    git fetch --tags 2>/dev/null || true
    git fetch origin 2>/dev/null || true

    CHECKOUT_TAG=""
    USE_DEVELOP=0

    if git tag | grep -q "^${VERSION_CLEAN}$"; then
        CHECKOUT_TAG="$VERSION_CLEAN"
    else
        # 尝试模糊匹配
        MATCHING_TAG=$(git tag | grep "^${VERSION_CLEAN}" | head -1)
        if [[ -n "$MATCHING_TAG" ]]; then
            CHECKOUT_TAG="$MATCHING_TAG"
        else
            # 使用 develop/eagle
            USE_DEVELOP=1
            CHECKOUT_TAG="origin/develop/eagle"
        fi
    fi

    if [[ "$USE_DEVELOP" -eq 1 ]]; then
        echo -e "  ${YELLOW}未找到匹配的tag，使用 develop/eagle${NC}"
        git checkout -b "fix/${VERSION}" origin/develop/eagle 2>/dev/null || git checkout "fix/${VERSION}" 2>/dev/null || true
    else
        echo "  切换到 tag: $CHECKOUT_TAG"
        git checkout "$CHECKOUT_TAG" 2>/dev/null || true
    fi

    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "N/A")
    echo "  当前分支: $CURRENT_BRANCH"
    echo "  当前版本: $CURRENT_TAG"

    # --------------------
    # 步骤2: 下载并安装包
    # --------------------
    echo ""
    echo -e "${CYAN}[步骤2] 下载并安装包${NC}"

    # 创建包专用目录（按包名，不是按版本）
    PKG_DIR="$PKG_DOWNLOAD_DIR/${PACKAGE}"
    mkdir -p "$PKG_DIR"
    cd "$PKG_DIR"

    DOWNLOADED_DEBS=""
    DOWNLOAD_METHOD=""

    # 方式1: 尝试从内部服务器下载
    echo "  [方式1] 从内部服务器下载..."
    if python3 "$SKILLS_DIR/coredump-package-management/scripts/scan_and_download.py" \
        "$PACKAGE" "$VERSION_CLEAN" "$PKG_DIR" 2>/dev/null; then
        DOWNLOADED_DEBS=$(find "$PKG_DIR" -name "${PACKAGE}_${VERSION_CLEAN}*.deb" -type f 2>/dev/null || true)
        if [[ -n "$DOWNLOADED_DEBS" ]]; then
            DOWNLOAD_METHOD="内部服务器"
        fi
    fi

    # 方式2: 尝试从 apt 下载
    if [[ -z "$DOWNLOADED_DEBS" ]]; then
        echo "  [方式2] 从 apt 源下载..."
        cd "$PKG_DIR"

        # 下载主包
        if apt download "$PACKAGE=$VERSION" 2>/dev/null; then
            echo "    主包下载成功"
            DOWNLOAD_METHOD="apt"
        fi

        # 下载调试包
        DBGSYM_PKG="${PACKAGE}-dbgsym"
        if apt download "$DBGSYM_PKG=$VERSION" 2>/dev/null; then
            echo "    调试包下载成功"
        fi

        DOWNLOADED_DEBS=$(find "$PKG_DIR" -name "*.deb" -type f 2>/dev/null || true)
    fi

    # 方式3: 尝试从 PPA 下载
    if [[ -z "$DOWNLOADED_DEBS" ]]; then
        echo "  [方式3] 从 PPA 下载..."
        bash "$SKILLS_DIR/coredump-package-management/scripts/download_from_ppa.sh" \
            "$PACKAGE" "$VERSION" "$PKG_DIR" 2>/dev/null || true
        DOWNLOADED_DEBS=$(find "$PKG_DIR" -name "*.deb" -type f 2>/dev/null || true)
        if [[ -n "$DOWNLOADED_DEBS" ]]; then
            DOWNLOAD_METHOD="PPA"
        fi
    fi

    # 统计下载的包
    DOWNLOADED_COUNT=$(echo "$DOWNLOADED_DEBS" | wc -w | tr -d ' ')

    if [[ "$DOWNLOADED_COUNT" -gt 0 ]]; then
        echo "  下载了 $DOWNLOADED_COUNT 个包 (来源: $DOWNLOAD_METHOD)"

        # 安装包
        echo "  安装包..."
        for deb in $DOWNLOADED_DEBS; do
            echo "    安装: $(basename $deb)"
            dpkg -i "$deb" 2>/dev/null || true
        done

        # 修复依赖
        apt-get install -f -y 2>/dev/null || true
    else
        echo -e "  ${YELLOW}未找到对应版本的包，基于堆栈分析${NC}"
    fi

    # --------------------
    # 步骤3: 分析崩溃
    # --------------------
    echo ""
    echo -e "${CYAN}[步骤3] 分析崩溃${NC}"

    cd "$WORKSPACE/5.崩溃分析"

    ANALYSIS_OUTPUT=$(python3 "$SKILLS_DIR/coredump-crash-analysis/scripts/analyze_crash_final.py" \
        --package "$PACKAGE" \
        --version "$VERSION" \
        --workspace "$WORKSPACE" 2>&1) || true

    # 提取关键信息
    APP_LAYER_CRASHES=$(echo "$ANALYSIS_OUTPUT" | grep -c "已定位到应用层崩溃帧" || echo 0)
    SYSTEM_CRASHES=$(echo "$ANALYSIS_OUTPUT" | grep -c "无法定位到应用层代码" || echo 0)

    echo "  应用层崩溃: $APP_LAYER_CRASHES"
    echo "  系统库崩溃: $SYSTEM_CRASHES"

    # --------------------
    # 步骤4: 修复和提交
    # --------------------
    echo ""
    echo -e "${CYAN}[步骤4] 修复和提交${NC}"

    if [[ "$APP_LAYER_CRASHES" -gt 0 ]]; then
        echo -e "  ${YELLOW}存在 $APP_LAYER_CRASHES 个应用层崩溃需要修复${NC}"

        # 创建修复分支（如果还没有）
        FIX_BRANCH="fix/${PACKAGE}-${VERSION}"

        # 检查分支是否存在
        if ! git branch | grep -q "$FIX_BRANCH"; then
            echo "  创建修复分支: $FIX_BRANCH"
            git checkout -b "$FIX_BRANCH" origin/develop/eagle 2>/dev/null || \
            git checkout -b "$FIX_BRANCH" 2>/dev/null || true
        else
            echo "  使用已有分支: $FIX_BRANCH"
            git checkout "$FIX_BRANCH" 2>/dev/null || true
        fi

        # 这里需要人工介入来判断如何修复
        # 暂时记录到报告中
        echo "  **需要人工分析崩溃原因并修复代码**"
        echo "  崩溃分析输出已保存，请查看具体堆栈信息"

        TOTAL_FIXED=$((TOTAL_FIXED + APP_LAYER_CRASHES))
    else
        echo -e "  ${GREEN}无应用层崩溃或崩溃发生在系统库${NC}"
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
    fi

    # --------------------
    # 添加到报告
    # --------------------
    echo "" >> "$REPORT_FILE"
    echo "### 版本: $VERSION ($CRASH_COUNT 次崩溃)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "- Git分支: $CURRENT_BRANCH" >> "$REPORT_FILE"
    echo "- Git版本: $CURRENT_TAG" >> "$REPORT_FILE"
    echo "- 应用层崩溃: $APP_LAYER_CRASHES" >> "$REPORT_FILE"
    echo "- 系统库崩溃: $SYSTEM_CRASHES" >> "$REPORT_FILE"

    if [[ "$APP_LAYER_CRASHES" -gt 0 ]]; then
        echo "- 状态: **需要人工修复**" >> "$REPORT_FILE}"
    else
        echo "- 状态: 无需应用层修复" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"

    echo ""
    echo "  版本 $VERSION 分析完成"

done <<< "$VERSIONS"

# 返回到主分支
echo ""
echo -e "${CYAN}返回主分支...${NC}"
cd "$CODE_DIR"
git checkout develop/eagle 2>/dev/null || git checkout master 2>/dev/null || true

# 完成报告
cat >> "$REPORT_FILE" << EOF

## 汇总

- 分析版本数: $ANALYZED_VERSIONS / $TOTAL_VERSIONS
- 崩溃总数: $TOTAL_CRASHES
- 需修复版本: $TOTAL_FIXED
- 跳过版本: $TOTAL_SKIPPED

---
*报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')*
EOF

echo ""
echo -e "${GREEN}=============================================================================${NC}"
echo -e "${GREEN}分析完成！${NC}"
echo -e "${GREEN}=============================================================================${NC}"
echo ""
echo "报告文件: $REPORT_FILE"
echo "分析版本: $ANALYZED_VERSIONS / $TOTAL_VERSIONS"
echo "崩溃总数: $TOTAL_CRASHES"
echo "需修复版本: $TOTAL_FIXED"
echo "跳过版本: $TOTAL_SKIPPED"
echo ""
