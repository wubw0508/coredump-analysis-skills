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
NC='\033[0m'

# 默认值
PACKAGE=""
START_DATE=""
END_DATE=""
SYS_VERSION="1070-1075"
ARCH="x86"
WORKSPACE="$HOME/coredump-workspace"
RUN_BACKGROUND=false

# 显示帮助
show_help() {
    cat << EOF
${BLUE}=============================================================================
崩溃分析 Agent - 可复用的自动化崩溃分析工具
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 --package <包名> [选项]

${GREEN}必需参数:${NC}
    --package <name>       要分析的包名
                           例如: dde-session-ui, dde-dock, dde-launcher

${GREEN}可选参数:${NC}
    --start-date <date>   开始日期 (默认: 7天前)
                           例如: 2026-03-14
    --end-date <date>     结束日期 (默认: 今天)
                           例如: 2026-04-14
    --sys-version <ver>   系统版本范围 (默认: 1070-1075)
                           例如: 1070, 1070-1075, 1070-1075
    --arch <arch>        架构 (默认: x86)
                           例如: x86, x86_64, arm64
    --workspace <dir>      工作目录 (默认: ~/coredump-workspace)
    --background          后台运行
    --help, -h           显示帮助

${GREEN}示例:${NC}
    # 分析 dde-session-ui 最近一个月崩溃 (x86)
    $0 --package dde-session-ui --start-date 2026-03-14 --end-date 2026-04-14

    # 分析 dde-session-ui arm64 架构
    $0 --package dde-session-ui --arch arm64 --start-date 2026-03-14 --end-date 2026-04-14

    # 分析 dde-dock 指定版本范围
    $0 --package dde-dock --sys-version 1060-1075

    # 后台运行
    $0 --package dde-session-ui --background

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
        --background)
            RUN_BACKGROUND=true
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
if [[ -z "$PACKAGE" ]]; then
    echo -e "${RED}错误: 必须指定 --package 参数${NC}"
    show_help
    exit 1
fi

# 计算默认日期
if [[ -z "$START_DATE" ]]; then
    START_DATE=$(date -d '7 days ago' +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)
    echo -e "${YELLOW}使用默认日期范围: $START_DATE 至 $END_DATE${NC}"
fi

echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}                    崩溃分析 Agent 启动${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo ""
echo -e "${GREEN}分析参数:${NC}"
echo "  包名: $PACKAGE"
echo "  架构: $ARCH"
echo "  开始日期: $START_DATE"
echo "  结束日期: $END_DATE"
echo "  系统版本: $SYS_VERSION"
echo "  工作目录: $WORKSPACE"
echo ""

# 从 accounts.json 读取凭据并写入环境配置
CONFIG_FILE="$HOME/.claude/skills/coredump-analysis-skills/accounts.json"
SETUP_ACCOUNTS_SCRIPT="$HOME/.claude/skills/coredump-analysis-skills/coredump-full-analysis/scripts/setup_accounts.py"

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

# 检查是否有占位符（未配置）
PLACEHOLDER_PATTERN="在此处输入"
if [[ "$SHUTTLE_USERNAME" == "$PLACEHOLDER_PATTERN"* ]] || \
   [[ "$SHUTTLE_PASSWORD" == "$PLACEHOLDER_PATTERN"* ]] || \
   [[ "$GERRIT_USERNAME" == "$PLACEHOLDER_PATTERN"* ]] || \
   [[ "$GERRIT_PASSWORD" == "$PLACEHOLDER_PATTERN"* ]]; then
    echo -e "${RED}错误: 账号配置未完成，仍包含占位符${NC}"
    echo ""
    echo -e "${YELLOW}检测到以下配置未填写:${NC}"
    [[ "$SHUTTLE_USERNAME" == "$PLACEHOLDER_PATTERN"* ]] && echo "  - shuttle.username: $SHUTTLE_USERNAME"
    [[ "$SHUTTLE_PASSWORD" == "$PLACEHOLDER_PATTERN"* ]] && echo "  - shuttle.password: $SHUTTLE_PASSWORD"
    [[ "$GERRIT_USERNAME" == "$PLACEHOLDER_PATTERN"* ]] && echo "  - gerrit.username: $GERRIT_USERNAME"
    [[ "$GERRIT_PASSWORD" == "$PLACEHOLDER_PATTERN"* ]] && echo "  - gerrit.password: $GERRIT_PASSWORD"
    echo ""
    echo -e "${YELLOW}请先完成账号配置，运行以下命令:${NC}"
    echo "    python3 $SETUP_ACCOUNTS_SCRIPT"
    echo ""
    echo -e "${BLUE}或者直接编辑配置文件:${NC}"
    echo "    nano $CONFIG_FILE"
    exit 1
fi

# 生成环境配置文件
echo -e "${YELLOW}从 accounts.json 写入配置...${NC}"
python3 "$SETUP_ACCOUNTS_SCRIPT" --config "$CONFIG_FILE" 2>/dev/null || true
echo -e "${GREEN}✅ 配置已写入${NC}"

# 构建命令
CMD="cd $HOME/.claude/skills/coredump-analysis-skills/coredump-full-analysis/scripts && \
bash analyze_crash_complete.sh \
    --package $PACKAGE \
    --arch $ARCH \
    --start-date $START_DATE \
    --end-date $END_DATE \
    --sys-version $SYS_VERSION \
    --workspace \"$WORKSPACE\" 2>&1"

if [[ "$RUN_BACKGROUND" == "true" ]]; then
    echo -e "${YELLOW}后台运行模式${NC}"
    eval "$CMD" &
    echo -e "${GREEN}Agent 已启动 (PID: $!)${NC}"
    echo "使用 'jobs' 查看后台任务"
else
    eval "$CMD"
fi
