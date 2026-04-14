#!/bin/bash
#=============================================================================
# dde-dock/dde-control-center 等包的崩溃分析完整流程
# 组合使用5个Skills进行一站式崩溃分析
#=============================================================================

set -e

# 配色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Skills目录
SKILLS_DIR="/home/wubw/skills"

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

# 加载配置
source "$CONFIG_DIR/metabase.env" 2>/dev/null || true
source "$CONFIG_DIR/gerrit.env" 2>/dev/null || true
source "$CONFIG_DIR/package-server.env" 2>/dev/null || true
source "$CONFIG_DIR/shuttle.env" 2>/dev/null || true
source "$CONFIG_DIR/system.env" 2>/dev/null || true
source "$CONFIG_DIR/local.env" 2>/dev/null || true

# 默认值
PACKAGE="${PACKAGE:-}"
START_DATE="${START_DATE:-}"
END_DATE="${END_DATE:-}"
SYS_VERSION="${SYS_VERSION:-1070-1075}"
WORKSPACE="${WORKSPACE:-./workspace}"

# 帮助信息
show_help() {
    cat << EOF
${BLUE}=============================================================================
dde-dock/dde-control-center 等包崩溃分析完整流程
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 [选项]

${GREEN}首次使用:${NC}
    首次使用必须先配置账号信息:
    python3 setup_accounts.py

${GREEN}选项:${NC}
    --package <name>       包名（必需）
                           例如: dde-dock, dde-control-center, dde-launcher
    --start-date <date>   开始日期（格式: YYYY-MM-DD）
                           例如: 2026-04-05
    --end-date <date>     结束日期（格式: YYYY-MM-DD）
                           例如: 2026-04-08
    --sys-version <ver>   系统版本范围（默认: 1070-1075）
                           例如: 1070, 1070-1075
    --workspace <dir>      工作目录（默认: ./workspace）
    --help, -h            显示此帮助信息

${GREEN}示例:${NC}
    # 分析最近3天的dde-dock崩溃
    $0 --package dde-dock --start-date 2026-04-05 --end-date 2026-04-08

    # 分析最近30天的dde-control-center崩溃
    $0 --package dde-control-center --start-date 2026-03-08 --end-date 2026-04-08

    # 使用默认参数（最近7天）
    $0 --package dde-launcher

${BLUE}=============================================================================
${NC}
EOF
}

# 解析参数
parse_args() {
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

    # 验证必需参数
    if [[ -z "$PACKAGE" ]]; then
        echo -e "${RED}错误: 必须指定 --package 参数${NC}"
        show_help
        exit 1
    fi

    # 默认日期：如果未指定，使用最近7天
    if [[ -z "$START_DATE" ]]; then
        START_DATE=$(date -d '7 days ago' +%Y-%m-%d)
        END_DATE=$(date +%Y-%m-%d)
        echo -e "${YELLOW}使用默认日期范围: $START_DATE 至 $END_DATE${NC}"
    fi
}

# 打印进度
print_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}步骤 $1: $2${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 检查依赖
check_dependencies() {
    print_step 0 "检查依赖..."

    local deps=("curl" "jq" "python3" "git" "ssh")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}错误: 缺少依赖 '$dep'${NC}"
            exit 1
        fi
    done

    # 检查SSH密钥
    if [[ ! -f "$GERRIT_SSH_KEY" ]]; then
        echo -e "${YELLOW}警告: SSH密钥 $GERRIT_SSH_KEY 不存在${NC}"
        echo "Gerrit克隆可能需要手动配置SSH密钥"
    fi

    echo -e "${GREEN}✅ 依赖检查完成${NC}"
}

# 创建工作目录
setup_workspace() {
    print_step 1 "创建工作目录"

    mkdir -p "$WORKSPACE"/{1.数据下载,2.数据筛选,3.代码管理,4.包管理/下载包,5.崩溃分析}

    echo -e "${GREEN}✅ 工作目录已创建: $WORKSPACE${NC}"
}

# 步骤1: 下载数据
download_data() {
    print_step 1 "数据下载"

    local download_script="$SKILLS_DIR/coredump-data-download/scripts/download_metabase_csv.sh"

    if [[ ! -f "$download_script" ]]; then
        echo -e "${RED}错误: 下载脚本不存在: $download_script${NC}"
        exit 1
    fi

    # 复制脚本到工作目录
    cp "$download_script" "$WORKSPACE/1.数据下载/"
    chmod +x "$WORKSPACE/1.数据下载/download_metabase_csv.sh"

    # 构建命令
    local cmd="./download_metabase_csv.sh"
    [[ -n "$START_DATE" ]] && cmd="$cmd --start-date $START_DATE"
    [[ -n "$END_DATE" ]] && cmd="$cmd --end-date $END_DATE"
    [[ -n "$SYS_VERSION" ]] && cmd="$cmd --sys-version $SYS_VERSION"
    cmd="$cmd $PACKAGE x86 crash"

    echo -e "${YELLOW}执行: $cmd${NC}"
    echo ""

    cd "$WORKSPACE/1.数据下载"
    eval "$cmd"

    # 查找下载的文件
    local csv_file=$(find "$WORKSPACE/1.数据下载" -name "${PACKAGE}_X86_crash_*.csv" -type f | sort | tail -1)

    if [[ -z "$csv_file" ]]; then
        echo -e "${RED}错误: 数据下载失败，未找到CSV文件${NC}"
        exit 1
    fi

    local line_count=$(wc -l < "$csv_file")
    echo -e "${GREEN}✅ 数据下载完成: $csv_file ($line_count 行)${NC}"

    # 返回CSV文件路径
    echo "$csv_file"
}

# 步骤2: 数据筛选/去重
filter_data() {
    print_step 2 "数据筛选/去重"

    local input_csv="$1"
    local filter_script="$SKILLS_DIR/coredump-data-filter/scripts/filter_crash_data.py"

    if [[ ! -f "$filter_script" ]]; then
        echo -e "${RED}错误: 筛选脚本不存在: $filter_script${NC}"
        exit 1
    fi

    # 复制脚本
    cp "$filter_script" "$WORKSPACE/2.数据筛选/"
    chmod +x "$WORKSPACE/2.数据筛选/filter_crash_data.py"

    # 修改脚本中的路径
    sed -i "s|WORKSPACE = \"/home/wubw/Desktop/coredump/workspace\"|WORKSPACE = \"$WORKSPACE\"|g" \
        "$WORKSPACE/2.数据筛选/filter_crash_data.py"

    echo -e "${YELLOW}执行: python3 filter_crash_data.py $PACKAGE${NC}"
    echo ""

    cd "$WORKSPACE/2.数据筛选"
    python3 filter_crash_data.py "$PACKAGE"

    local filtered_csv="$WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv"
    local stats_json="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"

    if [[ -f "$filtered_csv" ]]; then
        echo -e "${GREEN}✅ 数据筛选完成: $filtered_csv${NC}"
    fi

    if [[ -f "$stats_json" ]]; then
        echo -e "${GREEN}✅ 统计报告已生成: $stats_json${NC}"
        echo ""
        echo -e "${YELLOW}统计摘要:${NC}"
        jq '.summary' "$stats_json" 2>/dev/null || cat "$stats_json"
    fi

    echo "$filtered_csv"
}

# 步骤3: 代码管理
download_source() {
    print_step 3 "代码管理"

    local filtered_csv="$1"
    local source_script="$SKILLS_DIR/coredump-code-management/scripts/download_crash_source.sh"

    if [[ ! -f "$source_script" ]]; then
        echo -e "${RED}错误: 代码管理脚本不存在: $source_script${NC}"
        exit 1
    fi

    # 复制脚本
    cp "$source_script" "$WORKSPACE/3.代码管理/"
    chmod +x "$WORKSPACE/3.代码管理/download_crash_source.sh"

    echo -e "${YELLOW}执行: ./download_crash_source.sh $filtered_csv 2${NC}"
    echo ""

    cd "$WORKSPACE/3.代码管理"
    ./download_crash_source.sh "$filtered_csv" 2

    if [[ -d "$WORKSPACE/3.代码管理/$PACKAGE" ]]; then
        echo -e "${GREEN}✅ 源码已克隆: $WORKSPACE/3.代码管理/$PACKAGE${NC}"
    fi
}

# 步骤4: 包管理
download_packages() {
    print_step 4 "包管理"

    local filtered_csv="$1"
    local gen_script="$SKILLS_DIR/coredump-package-management/scripts/generate_tasks.py"
    local dl_script="$SKILLS_DIR/coredump-package-management/scripts/scan_and_download.py"

    if [[ ! -f "$gen_script" ]]; then
        echo -e "${RED}错误: 任务生成脚本不存在: $gen_script${NC}"
        exit 1
    fi

    # 复制脚本
    cp "$gen_script" "$WORKSPACE/4.包管理/下载包/"
    chmod +x "$WORKSPACE/4.包管理/下载包/"*.py

    # 修改脚本路径
    sed -i "s|WORKSPACE = \"/home/wubw/Desktop/coredump/workspace\"|WORKSPACE = \"$WORKSPACE\"|g" \
        "$WORKSPACE/4.包管理/下载包/generate_tasks.py"

    echo -e "${YELLOW}生成下载任务...${NC}"
    cd "$WORKSPACE/4.包管理/下载包"
    python3 generate_tasks.py

    if [[ -f "download_tasks.json" ]]; then
        echo -e "${GREEN}✅ 下载任务已生成: download_tasks.json${NC}"

        # 询问是否下载
        echo ""
        read -p "是否下载包？(y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp "$dl_script" .
            python3 scan_and_download.py --batch download_tasks.json
            echo -e "${GREEN}✅ 包下载完成${NC}"
        fi
    fi
}

# 步骤5: 崩溃分析
analyze_crashes() {
    print_step 5 "崩溃分析"

    local filtered_csv="$1"
    local analyze_script="$SKILLS_DIR/coredump-crash-analysis/scripts/analyze_crash_final.py"

    if [[ ! -f "$analyze_script" ]]; then
        echo -e "${RED}错误: 分析脚本不存在: $analyze_script${NC}"
        exit 1
    fi

    # 复制脚本
    cp "$analyze_script" "$WORKSPACE/5.崩溃分析/"
    chmod +x "$WORKSPACE/5.崩溃分析/analyze_crash_final.py"

    echo -e "${YELLOW}执行崩溃分析...${NC}"
    echo ""

    cd "$WORKSPACE/5.崩溃分析"
    python3 analyze_crash_final.py

    # 生成分析报告
    local report_file="$WORKSPACE/5.崩溃分析/${PACKAGE}_crash_analysis_report.md"

    cat > "$report_file" << EOF
# $PACKAGE 崩溃分析报告

**分析时间**: $(date '+%Y-%m-%d %H:%M:%S')
**数据范围**: $START_DATE 至 $END_DATE
**包名**: $PACKAGE

## 分析结果

分析结果已保存到对应目录，请查看：

- 统计报告: \`$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json\`
- 筛选数据: \`$WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv\`
- 源码目录: \`$WORKSPACE/3.代码管理/$PACKAGE\`
- 下载的包: \`$WORKSPACE/4.包管理/downloads/\`

---
*报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')*
EOF

    echo -e "${GREEN}✅ 分析报告已生成: $report_file${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}"
    echo "============================================================================="
    echo "            dde-dock/dde-control-center 崩溃分析完整流程"
    echo "============================================================================="
    echo -e "${NC}"

    parse_args "$@"
    check_dependencies
    setup_workspace

    # 执行5个步骤
    local csv_file=$(download_data)
    local filtered_csv=$(filter_data "$csv_file")
    download_source "$filtered_csv"
    download_packages "$filtered_csv"
    analyze_crashes "$filtered_csv"

    echo ""
    echo -e "${GREEN}"
    echo "============================================================================="
    echo "✅ 崩溃分析流程完成！"
    echo "============================================================================="
    echo -e "${NC}"
    echo "📊 统计报告: $WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"
    echo "📋 筛选数据: $WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv"
    echo "📄 分析报告: $WORKSPACE/5.崩溃分析/${PACKAGE}_crash_analysis_report.md"
    echo ""
}

# 运行
main "$@"
