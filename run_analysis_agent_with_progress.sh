#!/bin/bash
#=============================================================================
# 崩溃分析 Agent 调用脚本 - 带进度监控
# 每3分钟自动报告当前分析进度
#=============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 生成带时间戳的workspace路径
generate_workspace_with_timestamp() {
    echo "$HOME/coredump-workspace-$(date +%Y%m%d_%H%M%S)"
}

# 默认值
PACKAGE=""
START_DATE=""
END_DATE=""
SYS_VERSION="1070-1075"
ARCH="x86"
WORKSPACE=$(generate_workspace_with_timestamp)
PROGRESS_INTERVAL=180  # 3分钟 = 180秒

# 显示帮助
show_help() {
    cat << EOF
${BLUE}=============================================================================
崩溃分析 Agent - 带进度监控版本
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 --package <包名> [选项]

${GREEN}必需参数:${NC}
    --package <name>       要分析的包名

${GREEN}可选参数:${NC}
    --start-date <date>   开始日期 (默认: 7天前)
    --end-date <date>     结束日期 (默认: 今天)
    --sys-version <ver>   系统版本范围 (默认: 1070-1075)
    --arch <arch>         架构 (默认: x86)
    --workspace <dir>     工作目录 (默认: ~/coredump-workspace-YYYYMMDD_HHMMSS)
    --interval <seconds>  进度报告间隔 (默认: 180秒)
    --help, -h           显示帮助

${GREEN}示例:${NC}
    $0 --package dde-session-ui --start-date 2026-03-14 --end-date 2026-04-14
    $0 --package dde-dock --interval 120  # 每2分钟报告一次

${BLUE}=============================================================================${NC}
EOF
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --package)
            PACKAGE="$2"
            shift 2
            ;;
        --start-date)
            START_DATE="$2"
            shift 2
            ;;
        --end-date)
            END_DATE="$2"
            shift 2
            ;;
        --sys-version)
            SYS_VERSION="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        --interval)
            PROGRESS_INTERVAL="$2"
            shift 2
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
if [[ -z "$PACKAGE" ]]; then
    echo -e "${RED}错误: 必须指定 --package 参数${NC}"
    show_help
    exit 1
fi

# 计算默认日期
if [[ -z "$START_DATE" ]]; then
    START_DATE=$(date -d '7 days ago' +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)
fi

echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}           崩溃分析 Agent (带进度监控) 启动${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo ""
echo -e "${GREEN}分析参数:${NC}"
echo "  包名: $PACKAGE"
echo "  架构: $ARCH"
echo "  开始日期: $START_DATE"
echo "  结束日期: $END_DATE"
echo "  系统版本: $SYS_VERSION"
echo "  工作目录: $WORKSPACE"
echo "  进度报告间隔: ${PROGRESS_INTERVAL}秒"
echo ""

# 进度报告函数
report_progress() {
    local elapsed=$1
    local step=$2
    local step_name=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[$timestamp] 进度报告 (已运行 ${elapsed}秒)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # 统计下载目录中的CSV文件
    local download_dir="$WORKSPACE/1.数据下载"
    if [[ -d "$download_dir" ]]; then
        local csv_count=$(find "$download_dir" -name "*.csv" 2>/dev/null | wc -l)
        echo -e "${GREEN}步骤① 数据下载:${NC} 已完成 CSV文件: ${csv_count}个"
    fi

    # 统计筛选数据
    local filtered_file="$WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv"
    local stats_file="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"
    if [[ -f "$filtered_file" ]]; then
        local filtered_lines=$(wc -l < "$filtered_file" 2>/dev/null || echo "0")
        echo -e "${GREEN}步骤② 数据筛选:${NC} 筛选后记录数: $((filtered_lines - 1))"
    fi
    if [[ -f "$stats_file" ]] && command -v jq &> /dev/null; then
        local unique=$(jq -r '.unique_crashes // .统计摘要.唯一崩溃数 // 0' "$stats_file" 2>/dev/null || echo "未知")
        local total=$(jq -r '.total_records // .统计摘要.总记录数 // 0' "$stats_file" 2>/dev/null || echo "未知")
        echo -e "  唯一崩溃数: ${unique}, 总记录数: ${total}"
    fi

    # 统计代码管理（已切换的版本）
    local code_dir="$WORKSPACE/3.代码管理/$PACKAGE"
    if [[ -d "$code_dir" ]]; then
        local branches=$(git -C "$code_dir" branch -l 2>/dev/null | wc -l || echo "0")
        echo -e "${GREEN}步骤③ 代码管理:${NC} 已创建分支: ${branches}个"
    fi

    # 统计包管理（已下载的包）
    local pkg_dir="$WORKSPACE/4.包管理/downloads"
    if [[ -d "$pkg_dir" ]]; then
        local deb_count=$(find "$pkg_dir" -name "*.deb" 2>/dev/null | wc -l)
        echo -e "${GREEN}步骤④ 包管理:${NC} 已下载deb包: ${deb_count}个"
    fi

    # 统计崩溃分析（已分析的版本）
    local analysis_dir="$WORKSPACE/5.崩溃分析"
    if [[ -d "$analysis_dir" ]]; then
        local version_count=$(find "$analysis_dir" -name "analysis.json" 2>/dev/null | wc -l)
        echo -e "${GREEN}步骤⑤ 崩溃分析:${NC} 已分析版本: ${version_count}个"
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# 检查进程是否还在运行
is_running() {
    kill -0 "$1" 2>/dev/null
}

# 启动主分析进程
echo -e "${YELLOW}启动崩溃分析...${NC}"

# 构建命令
CMD="cd $HOME/.claude/skills/coredump-analysis-skills/coredump-full-analysis/scripts && \
bash analyze_crash_complete.sh \
    --package $PACKAGE \
    --arch $ARCH \
    --start-date $START_DATE \
    --end-date $END_DATE \
    --sys-version $SYS_VERSION \
    --workspace \"$WORKSPACE\" 2>&1"

# 启动后台进程
eval "$CMD" &
MAIN_PID=$!

echo -e "${GREEN}分析进程已启动 (PID: $MAIN_PID)${NC}"
echo ""

# 初始化
START_TIME=$(date +%s)
LAST_REPORT_TIME=$START_TIME
LAST_VERSION_COUNT=0

# 监控循环
while is_running $MAIN_PID; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    INTERVAL_PASSED=$((CURRENT_TIME - LAST_REPORT_TIME))

    # 检查是否需要报告进度
    if [[ $INTERVAL_PASSED -ge $PROGRESS_INTERVAL ]]; then
        report_progress $ELAPSED
        LAST_REPORT_TIME=$CURRENT_TIME
    fi

    sleep 5  # 每5秒检查一次
done

# 等待进程结束
wait $MAIN_PID
EXIT_CODE=$?

# 最终进度报告
END_TIME=$(date +%s)
TOTAL_ELAPSED=$((END_TIME - START_TIME))

echo ""
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}                    分析流程已结束${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo ""
echo -e "${GREEN}最终状态:${NC}"
echo "  退出码: $EXIT_CODE"
echo "  总耗时: ${TOTAL_ELAPSED}秒 ($(($TOTAL_ELAPSED / 60))分$(($TOTAL_ELAPSED % 60))秒)"
echo ""

# 输出最终统计
report_progress $TOTAL_ELAPSED

# 报告文件位置
echo -e "${GREEN}输出文件:${NC}"
echo "  统计报告: $WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"
echo "  筛选数据: $WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv"
echo "  最终报告: $WORKSPACE/7.总结报告/final_conclusion.md"

if [[ $EXIT_CODE -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ 崩溃分析流程完成！${NC}"
else
    echo ""
    echo -e "${RED}❌ 分析流程异常退出 (退出码: $EXIT_CODE)${NC}"
fi
