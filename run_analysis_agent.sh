#!/bin/bash
#=============================================================================
# 崩溃分析 Agent 调用脚本
# 用法: bash run_analysis_agent.sh --package dde-session-ui [--start-date 2026-03-14] [--end-date 2026-04-14] [--sys-version 1070-1075]
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
PACKAGES=""
START_DATE=""
END_DATE=""
SYS_VERSION="1070-1075"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.openclaw/skills/coredump-analysis-skills}"
PACKAGES_FILE="$SKILLS_DIR/packages.txt"

ARCH="x86"
WORKSPACE=$(generate_workspace_with_timestamp)
RUN_BACKGROUND=false
PROGRESS_INTERVAL=0  # 0表示禁用进度监控，非0表示启用(秒)

# 显示帮助
show_help() {
    cat << EOF
${BLUE}=============================================================================
崩溃分析 Agent - 可复用的自动化崩溃分析工具
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 --packages <包名列表> [选项]

${GREEN}必需参数:${NC}
    --packages <names>     要分析的包名（支持多包，逗号分隔）
                           例如: dde-session-ui
                           多包: dde-control-center,dde-dock,dde-launcher
                           不指定: 自动从 packages.txt 读取24个默认项目

${GREEN}可选参数:${NC}
    --start-date <date>   开始日期 (默认: 不限制，下载所有可取数据)
                           例如: 2026-03-14
    --end-date <date>     结束日期 (默认: 不限制，下载所有可取数据)
                           例如: 2026-04-14
    --sys-version <ver>   系统版本范围 (默认: 1070-1075)
                           例如: 1070, 1070-1075, 1070-1075
    --arch <arch>        架构 (默认: x86)
                           例如: x86, x86_64, arm64
    --workspace <dir>      工作目录 (默认: ~/coredump-workspace-YYYYMMDD_HHMMSS)
    --background          后台运行
    --progress [秒]       启用进度监控 (默认: 180秒)
    --interval <秒>       进度报告间隔 (默认: 180秒)
    --help, -h           显示帮助

${GREEN}示例:${NC}
    # 全量分析（读取 packages.txt，分析全部24个默认项目）
    $0

    # 分析单个包所有能下载的崩溃 (x86)
    $0 --packages dde-session-ui

    # 分析单个包指定日期范围内的崩溃 (x86)
    $0 --packages dde-session-ui --start-date 2026-03-14 --end-date 2026-04-14

    # 并行分析多个包
    $0 --packages dde-control-center,dde-dock,dde-launcher,dde-session-ui,dde-session-shell,startdde,dde-daemon

    # 多包 + 进度监控 (每3分钟报告一次)
    $0 --packages dde-control-center,dde-dock --progress 180

    # 分析 dde-dock 指定版本范围
    $0 --package dde-dock --sys-version 1060-1075

    # 后台运行
    $0 --package dde-session-ui --background

    # 带进度监控 (每3分钟报告一次)
    $0 --package dde-session-ui --progress

    # 带进度监控 (每2分钟报告一次)
    $0 --package dde-session-ui --progress 120

${GREEN}输出文件:${NC}
    <workspace>/2.数据筛选/<package>_crash_statistics.json  - 统计报告
    <workspace>/2.数据筛选/filtered_<package>_crash_data.csv - 筛选后数据

${BLUE}=============================================================================
${NC}
EOF
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --package)
            # 兼容单包参数
            PACKAGES="$2"
            shift 2
            ;;
        --packages)
            # 支持逗号分隔的多包列表
            PACKAGES="$2"
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
        --background)
            RUN_BACKGROUND=true
            shift
            ;;
        --progress)
            PROGRESS_INTERVAL="${2:-180}"
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
if [[ -z "$PACKAGES" ]]; then
    # 未指定 --packages，尝试从 packages.txt 读取默认项目列表
    if [[ -f "$PACKAGES_FILE" ]]; then
        echo -e "${YELLOW}未指定 --packages，从 $PACKAGES_FILE 读取默认项目列表${NC}"
        PACKAGES=$(grep -v '^#' "$PACKAGES_FILE" | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
        if [[ -z "$PACKAGES" ]]; then
            echo -e "${RED}错误: packages.txt 为空${NC}"
            exit 1
        fi
        echo -e "${GREEN}已加载 $(echo "$PACKAGES" | tr ',' '\n' | wc -l) 个分析项目${NC}"
    else
        echo -e "${RED}错误: 必须指定 --packages 参数，且 packages.txt 不存在${NC}"
        show_help
        exit 1
    fi
fi

# 转换为数组（支持逗号分隔）
IFS=',' read -ra PACKAGE_ARRAY <<< "$PACKAGES"
PACKAGE_COUNT=${#PACKAGE_ARRAY[@]}

if [[ -z "$START_DATE" && -z "$END_DATE" ]]; then
    DATE_RANGE_LABEL="全部可下载数据（不按日期过滤）"
elif [[ -n "$START_DATE" && -n "$END_DATE" ]]; then
    DATE_RANGE_LABEL="$START_DATE 至 $END_DATE"
elif [[ -n "$START_DATE" ]]; then
    DATE_RANGE_LABEL="$START_DATE 至 最新可下载"
else
    DATE_RANGE_LABEL="最早可下载 至 $END_DATE"
fi

echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}                    崩溃分析 Agent 启动${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo ""
echo -e "${GREEN}分析参数:${NC}"
echo "  包名: $PACKAGES"
echo "  待分析包数量: $PACKAGE_COUNT"
echo "  架构: $ARCH"
echo "  日期范围: $DATE_RANGE_LABEL"
echo "  系统版本: $SYS_VERSION"
echo "  工作目录: $WORKSPACE"
if [[ "$PROGRESS_INTERVAL" -gt 0 ]]; then
    echo "  进度监控: ${PROGRESS_INTERVAL}秒"
fi
echo ""

# 从 accounts.json 读取凭据并写入环境配置
CONFIG_FILE="$HOME/.openclaw/skills/coredump-analysis-skills/accounts.json"
SETUP_ACCOUNTS_SCRIPT="$HOME/.openclaw/skills/coredump-analysis-skills/coredump-full-analysis/scripts/setup_accounts.py"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}错误: 配置文件不存在: $CONFIG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}请先配置账号信息，运行以下命令:${NC}"
    echo "    python3 $SETUP_ACCOUNTS_SCRIPT"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}错误: jq 未安装，无法读取配置文件${NC}"
    exit 1
fi

# 读取并验证账号配置
export SHUTTLE_USERNAME=$(jq -r '.shuttle.account.username' "$CONFIG_FILE")
export SHUTTLE_PASSWORD=$(jq -r '.shuttle.account.password' "$CONFIG_FILE")
export GERRIT_USERNAME=$(jq -r '.gerrit.account.username' "$CONFIG_FILE")
export GERRIT_PASSWORD=$(jq -r '.gerrit.account.password' "$CONFIG_FILE")
export GERRIT_SSH_KEY=$(eval echo $(jq -r '.gerrit.ssh_key // "~/.ssh/id_rsa"' "$CONFIG_FILE"))
export SUDO_PASSWORD=$(jq -r '.system.sudo_password' "$CONFIG_FILE")

# 检查是否有占位符（未配置）
PLACEHOLDER_PATTERN="在此处输入"
if [[ -z "$GERRIT_USERNAME" || "$GERRIT_USERNAME" == "null" || "$GERRIT_USERNAME" == "$PLACEHOLDER_PATTERN"* ]]; then
    echo -e "${RED}错误: Gerrit 用户名未配置${NC}"
    echo ""
    echo -e "${YELLOW}请先配置账号信息，运行以下命令:${NC}"
    echo "    python3 $SETUP_ACCOUNTS_SCRIPT"
    exit 1
fi

OPTIONAL_CONFIG_WARNINGS=()
[[ -z "$SHUTTLE_USERNAME" || "$SHUTTLE_USERNAME" == "null" || "$SHUTTLE_USERNAME" == "$PLACEHOLDER_PATTERN"* ]] && OPTIONAL_CONFIG_WARNINGS+=("shuttle.username")
[[ -z "$SHUTTLE_PASSWORD" || "$SHUTTLE_PASSWORD" == "null" || "$SHUTTLE_PASSWORD" == "$PLACEHOLDER_PATTERN"* ]] && OPTIONAL_CONFIG_WARNINGS+=("shuttle.password")
[[ -z "$GERRIT_PASSWORD" || "$GERRIT_PASSWORD" == "null" || "$GERRIT_PASSWORD" == "$PLACEHOLDER_PATTERN"* ]] && OPTIONAL_CONFIG_WARNINGS+=("gerrit.password")

if [[ ${#OPTIONAL_CONFIG_WARNINGS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}警告: 以下可选账号字段未配置，本次流程将继续使用 SSH/内部包服务:${NC}"
    printf '  - %s\n' "${OPTIONAL_CONFIG_WARNINGS[@]}"
fi

# 生成环境配置文件
echo -e "${YELLOW}从 accounts.json 写入配置...${NC}"
python3 "$SETUP_ACCOUNTS_SCRIPT" --config "$CONFIG_FILE" 2>/dev/null || true
echo -e "${GREEN}✅ 配置已写入${NC}"

# 进度报告函数
report_progress() {
    local elapsed=$1
    local pkg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[$timestamp] 进度报告 (已运行 ${elapsed}秒)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local pkg_index=1
    for pkg in "${PACKAGE_ARRAY[@]}"; do
        echo -e "${GREEN}【${pkg_index}/${PACKAGE_COUNT}】${pkg}${NC}"

        # 统计下载目录中的CSV文件
        local csv_count=$(find "$WORKSPACE/1.数据下载" -name "${pkg}_X86_crash_*.csv" 2>/dev/null | wc -l)
        echo -e "  步骤① 数据下载: CSV文件: ${csv_count}个"

        # 统计筛选数据
        local filtered_file="$WORKSPACE/2.数据筛选/filtered_${pkg}_crash_data.csv"
        local stats_file="$WORKSPACE/2.数据筛选/${pkg}_crash_statistics.json"
        if [[ -f "$filtered_file" ]]; then
            local filtered_lines=$(wc -l < "$filtered_file" 2>/dev/null || echo "0")
            echo -e "  步骤② 数据筛选: 筛选后记录数: $((filtered_lines - 1))"
        fi
        if [[ -f "$stats_file" ]] && command -v jq &> /dev/null; then
            local unique=$(jq -r '.unique_crashes // .统计摘要.唯一崩溃数 // 0' "$stats_file" 2>/dev/null || echo "未知")
            local total=$(jq -r '.total_records // .统计摘要.总记录数 // 0' "$stats_file" 2>/dev/null || echo "未知")
            echo -e "    唯一崩溃: ${unique}, 总记录: ${total}"
        fi

        # 统计崩溃分析（已分析的版本）
        local analysis_dir="$WORKSPACE/5.崩溃分析/${pkg}"
        if [[ -d "$analysis_dir" ]]; then
            local version_count=$(find "$analysis_dir" -name "analysis.json" 2>/dev/null | wc -l)
            echo -e "  步骤⑤ 崩溃分析: 已分析版本: ${version_count}个"
        fi

        ((pkg_index++)) || true
    done

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# 检查进程是否还在运行
is_running() {
    kill -0 "$1" 2>/dev/null
}

# 启动单个包的崩溃分析
launch_package() {
    local pkg="$1"
    local log_file="/tmp/analysis_${pkg}.log"
    cd "$HOME/.openclaw/skills/coredump-analysis-skills/coredump-full-analysis/scripts"
    local cmd=(bash analyze_crash_complete.sh
        --package "$pkg"
        --arch "$ARCH"
        --sys-version "$SYS_VERSION"
        --workspace "$WORKSPACE")
    [[ -n "$START_DATE" ]] && cmd+=(--start-date "$START_DATE")
    [[ -n "$END_DATE" ]] && cmd+=(--end-date "$END_DATE")
    SUDO_PASSWORD="$SUDO_PASSWORD" PROGRESS_INTERVAL="$PROGRESS_INTERVAL" "${cmd[@]}" 2>&1
}

# 并行启动所有包的分析
if [[ "$RUN_BACKGROUND" == "true" ]]; then
    echo -e "${YELLOW}后台运行模式${NC}"
    echo "并行启动 $PACKAGE_COUNT 个包的分析..."
    for pkg in "${PACKAGE_ARRAY[@]}"; do
        launch_package "$pkg" > "/tmp/analysis_${pkg}.log" 2>&1 &
        echo -e "${GREEN}✅ $pkg 已启动 (PID: $!)${NC}"
    done
    echo ""
    echo "使用 'jobs' 查看后台任务，或查看各包日志:"
    for pkg in "${PACKAGE_ARRAY[@]}"; do
        echo "  tail -f /tmp/analysis_${pkg}.log  # $pkg"
    done

elif [[ "$PROGRESS_INTERVAL" -gt 0 ]]; then
    # 启用进度监控模式：并行启动所有包
    echo -e "${YELLOW}启用进度监控 (间隔: ${PROGRESS_INTERVAL}秒)${NC}"
    echo "并行启动 $PACKAGE_COUNT 个包的分析..."
    echo ""

    declare -a PIDS
    for pkg in "${PACKAGE_ARRAY[@]}"; do
        launch_package "$pkg" > "/tmp/analysis_${pkg}.log" 2>&1 &
        pid=$!
        PIDS+=($pid)
        echo -e "${GREEN}🚀 $pkg 已启动 (PID: $pid)${NC}"
    done

    # 初始化
    START_TIME=$(date +%s)
    LAST_REPORT_TIME=$START_TIME

    # 监控循环：检查所有进程是否结束
    any_running() {
        for pid in "${PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                return 0
            fi
        done
        return 1
    }

    while any_running; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        INTERVAL_PASSED=$((CURRENT_TIME - LAST_REPORT_TIME))

        if [[ $INTERVAL_PASSED -ge $PROGRESS_INTERVAL ]]; then
            report_progress $ELAPSED ""
            LAST_REPORT_TIME=$CURRENT_TIME
        fi

        sleep 5  # 每5秒检查一次
    done

    # 等待所有进程结束
    ALL_EXIT_CODE=0
    for pid in "${PIDS[@]}"; do
        wait "$pid" || ALL_EXIT_CODE=$?
    done

    # 最终进度报告
    END_TIME=$(date +%s)
    TOTAL_ELAPSED=$((END_TIME - START_TIME))

    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}                    分析流程已结束${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
    echo -e "${GREEN}最终状态:${NC}"
    echo "  总耗时: ${TOTAL_ELAPSED}秒 ($(($TOTAL_ELAPSED / 60))分$(($TOTAL_ELAPSED % 60))秒)"
    echo ""

    report_progress $TOTAL_ELAPSED ""

    echo -e "${GREEN}输出文件:${NC}"
    for pkg in "${PACKAGE_ARRAY[@]}"; do
        echo "  $pkg:"
        echo "    统计报告: $WORKSPACE/2.数据筛选/${pkg}_crash_statistics.json"
        echo "    筛选数据: $WORKSPACE/2.数据筛选/filtered_${pkg}_crash_data.csv"
        echo "    分析报告: $WORKSPACE/5.崩溃分析/${pkg}/"
    done
    echo "  最终报告: $WORKSPACE/7.总结报告/final_conclusion.md"

    if [[ $ALL_EXIT_CODE -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}✅ 所有包崩溃分析流程完成！${NC}"
    else
        echo ""
        echo -e "${RED}❌ 分析流程异常退出${NC}"
    fi

    exit $ALL_EXIT_CODE

else
    # 前台顺序执行
    PACKAGE_IDX=1
    OVERALL_EXIT_CODE=0
    FAILED_PACKAGES=()
    for pkg in "${PACKAGE_ARRAY[@]}"; do
        echo -e "${BLUE}=============================================================================${NC}"
        echo -e "${BLUE}  [$PACKAGE_IDX/$PACKAGE_COUNT] 分析包: $pkg${NC}"
        echo -e "${BLUE}=============================================================================${NC}"
        if launch_package "$pkg"; then
            echo -e "${GREEN}✅ $pkg 分析完成${NC}"
        else
            pkg_exit_code=$?
            OVERALL_EXIT_CODE=$pkg_exit_code
            FAILED_PACKAGES+=("$pkg")
            echo -e "${RED}❌ $pkg 分析失败，继续下一个包${NC}"
        fi
        ((PACKAGE_IDX++)) || true
    done

    if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}以下包分析失败:${NC}"
        printf '  - %s\n' "${FAILED_PACKAGES[@]}"
        exit "$OVERALL_EXIT_CODE"
    fi
fi
