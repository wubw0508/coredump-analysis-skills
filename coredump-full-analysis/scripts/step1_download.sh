#!/bin/bash
#=============================================================================
# 步骤1: 数据下载 - coredump-data-download skill
#=============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
SKILLS_DATA_DOWNLOAD="$SCRIPT_DIR/../../coredump-data-download/scripts"
LOAD_ACCOUNTS_SCRIPT="$SCRIPT_DIR/load_accounts.sh"

source "$LOAD_ACCOUNTS_SCRIPT"
load_accounts_or_die metabase

# 默认值
PACKAGE="${PACKAGE:-}"
START_DATE="${START_DATE:-}"
END_DATE="${END_DATE:-}"
SYS_VERSION="${SYS_VERSION:-1070-1075}"
# 如果未指定 WORKSPACE，自动创建带时间戳的目录
if [[ -z "$WORKSPACE" ]] || [[ "$WORKSPACE" == "./workspace" ]]; then
    WORKSPACE="$HOME/coredump-workspace-$(date +%Y%m%d-%H%M%S)"
fi

# 帮助信息
show_help() {
    cat << EOF
${BLUE}=============================================================================
步骤1: 数据下载${NC}

${GREEN}用法:${NC}
    $0 --package <name> [选项]

${GREEN}选项:${NC}
    --package <name>       包名（必需）
    --start-date <date>   开始日期（格式: YYYY-MM-DD；默认不限制）
    --end-date <date>     结束日期（格式: YYYY-MM-DD；默认不限制）
    --sys-version <ver>   系统版本范围（默认: 1070-1075）
    --workspace <dir>      工作目录（默认: 自动创建带时间戳的目录 ~/coredump-workspace-YYYYMMDD-HHMMSS）
    --help, -h            显示此帮助信息

${GREEN}示例:${NC}
    $0 --package dde-session-shell --start-date 2026-03-10 --end-date 2026-04-09 --sys-version 1070-1075

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
        --workspace)
            WORKSPACE="$2"
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

if [[ -z "$PACKAGE" ]]; then
    echo -e "${RED}错误: 必须指定 --package 参数${NC}"
    show_help
    exit 1
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}步骤1: 数据下载${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ -z "$START_DATE" && -z "$END_DATE" ]]; then
    echo -e "${YELLOW}日期范围: 全部可下载数据（不按日期过滤）${NC}"
elif [[ -n "$START_DATE" && -n "$END_DATE" ]]; then
    echo -e "${YELLOW}日期范围: $START_DATE 至 $END_DATE${NC}"
elif [[ -n "$START_DATE" ]]; then
    echo -e "${YELLOW}日期范围: $START_DATE 至 最新可下载${NC}"
else
    echo -e "${YELLOW}日期范围: 最早可下载 至 $END_DATE${NC}"
fi
echo ""

# 创建工作目录
mkdir -p "$WORKSPACE/1.数据下载"

# 下载脚本
DOWNLOAD_SCRIPT="$SKILLS_DATA_DOWNLOAD/download_metabase_csv.sh"

if [[ ! -f "$DOWNLOAD_SCRIPT" ]]; then
    echo -e "${RED}错误: 下载脚本不存在: $DOWNLOAD_SCRIPT${NC}"
    exit 1
fi

# 构建命令
CMD="bash $DOWNLOAD_SCRIPT"
[[ -n "$START_DATE" ]] && CMD="$CMD --start-date $START_DATE"
[[ -n "$END_DATE" ]] && CMD="$CMD --end-date $END_DATE"
[[ -n "$SYS_VERSION" ]] && CMD="$CMD --sys-version $SYS_VERSION"
CMD="$CMD $PACKAGE x86 crash"

echo -e "${YELLOW}执行: $CMD${NC}"
echo ""

cd "$WORKSPACE/1.数据下载"
eval "$CMD"

# 查找下载的文件
csv_file=$(find "$WORKSPACE/1.数据下载" -name "${PACKAGE}*crash*.csv" -type f 2>/dev/null | sort | tail -1)

if [[ -z "$csv_file" ]]; then
    echo ""
    echo -e "${RED}错误: 数据下载失败，未找到CSV文件${NC}"
    echo ""
    echo -e "${YELLOW}提示: Metabase 服务可能不可用 (504 Gateway Timeout)${NC}"
    echo "请稍后重试，或联系管理员检查 Metabase 服务状态"
    exit 1
fi

line_count=$(wc -l < "$csv_file" 2>/dev/null || echo "0")
echo ""
echo -e "${GREEN}✅ 数据下载完成: $csv_file ($line_count 行)${NC}"
echo ""

# 输出CSV文件路径供后续步骤使用
echo "$csv_file"
