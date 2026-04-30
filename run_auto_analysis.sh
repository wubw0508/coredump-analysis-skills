#!/bin/bash
#=============================================================================
# 全量崩溃分析 + 自动修复提交 自动化脚本
# 用法: bash run_auto_analysis.sh [--background] [--interval 10800]
#=============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SKILLS_DIR="${SKILLS_DIR:-$HOME/.openclaw/skills/coredump-analysis-skills}"
PACKAGES_FILE="$SKILLS_DIR/packages.txt"
LOG_DIR="$HOME/coredump-auto-analysis-logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/auto_analysis_${TIMESTAMP}.log"

# 默认配置
TARGET_BRANCH="origin/develop/eagle"
ARCH="x86"
SYS_VERSION="1070-1075"
RUN_BACKGROUND=false
INTERVAL=10800  # 3小时 = 10800秒

# 显示帮助
show_help() {
    cat << EOF
${BLUE}=============================================================================
全量崩溃分析 + 自动修复提交 自动化脚本
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 [选项]

${GREEN}选项:${NC}
    --background          后台运行
    --interval <秒>       执行间隔（默认: 10800秒 = 3小时）
    --target-branch <br>  目标分支（默认: origin/develop/eagle）
    --arch <arch>         架构（默认: x86）
    --sys-version <ver>   系统版本（默认: 1070-1075）
    --help, -h           显示帮助

${GREEN}示例:${NC}
    # 前台运行（测试用）
    $0

    # 后台运行，每3小时执行一次
    $0 --background

    # 后台运行，每6小时执行一次
    $0 --background --interval 21600

    # 使用nohup后台运行
    nohup $0 --background > /dev/null 2>&1 &

${GREEN}功能:${NC}
    1. 读取packages.txt中的24个默认项目
    2. 对每个项目执行崩溃数据下载、筛选、分析
    3. 对有fixer的项目自动修复并提交到Gerrit
    4. 如果develop/eagle分支已修复则跳过
    5. 记录详细日志

${BLUE}=============================================================================
${NC}
EOF
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --background)
            RUN_BACKGROUND=true
            shift
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --target-branch)
            TARGET_BRANCH="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --sys-version)
            SYS_VERSION="$2"
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

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[$timestamp] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$timestamp] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# 执行单个包的分析和修复
analyze_and_fix_package() {
    local pkg="$1"
    local pkg_start_time=$(date +%s)

    log_info "=========================================="
    log_info "开始分析: $pkg"
    log_info "=========================================="

    # 创建工作目录
    local workspace="$HOME/coredump-workspace-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$workspace"

    # 步骤1: 运行崩溃分析
    log_info "步骤1: 运行崩溃分析..."
    cd "$SKILLS_DIR"
    if bash run_analysis_agent.sh \
        --packages "$pkg" \
        --arch "$ARCH" \
        --sys-version "$SYS_VERSION" \
        --workspace "$workspace" \
        --target-branch "$TARGET_BRANCH" \
        2>&1 | tee -a "$LOG_FILE"; then
        log_success "$pkg 崩溃分析完成"
    else
        log_error "$pkg 崩溃分析失败"
        return 1
    fi

    # 步骤2: 对有fixer的项目执行自动修复
    local fixable_projects=("dde-dock" "dde-launcher" "dde-control-center")
    for fixable_pkg in "${fixable_projects[@]}"; do
        if [[ "$pkg" == "$fixable_pkg" ]]; then
            log_info "步骤2: 执行自动修复提交 ($pkg)..."

            # 查找analysis.json文件
            local analysis_files=$(find "$workspace/5.崩溃分析/$pkg" -name "analysis.json" 2>/dev/null)
            if [[ -z "$analysis_files" ]]; then
                log_info "未找到analysis.json，跳过自动修复"
                continue
            fi

            # 对每个版本执行自动修复
            for analysis_file in $analysis_files; do
                local version_dir=$(dirname "$analysis_file")
                local version=$(basename "$version_dir")

                log_info "处理版本: $version"

                cd "$SKILLS_DIR/coredump-full-analysis/scripts"
                if python3 auto_fix_submit.py \
                    --package "$pkg" \
                    --version "$version" \
                    --workspace "$workspace" \
                    --target-branch "$TARGET_BRANCH" \
                    2>&1 | tee -a "$LOG_FILE"; then
                    log_success "$pkg $version 自动修复完成"
                else
                    log_error "$pkg $version 自动修复失败"
                fi
            done
            break
        fi
    done

    local pkg_end_time=$(date +%s)
    local pkg_elapsed=$((pkg_end_time - pkg_start_time))
    log_info "$pkg 处理完成，耗时: ${pkg_elapsed}秒"
}

# 主执行函数
main() {
    local start_time=$(date +%s)

    log_info "================================================================"
    log_info "全量崩溃分析 + 自动修复提交 开始"
    log_info "================================================================"
    log_info "配置:"
    log_info "  目标分支: $TARGET_BRANCH"
    log_info "  架构: $ARCH"
    log_info "  系统版本: $SYS_VERSION"
    log_info "  执行间隔: ${INTERVAL}秒"
    log_info "  日志文件: $LOG_FILE"
    log_info "================================================================"

    # 读取packages.txt
    if [[ ! -f "$PACKAGES_FILE" ]]; then
        log_error "packages.txt不存在: $PACKAGES_FILE"
        exit 1
    fi

    local packages=$(grep -v '^#' "$PACKAGES_FILE" | grep -v '^$' | tr '\n' ' ')
    local pkg_count=$(echo "$packages" | wc -w)

    log_info "待分析项目数: $pkg_count"
    log_info "项目列表: $packages"
    echo ""

    # 统计变量
    local success_count=0
    local fail_count=0
    local skip_count=0

    # 逐个分析
    local pkg_index=1
    for pkg in $packages; do
        log_info "[$pkg_index/$pkg_count] 处理项目: $pkg"

        if analyze_and_fix_package "$pkg"; then
            ((success_count++))
        else
            ((fail_count++))
        fi

        ((pkg_index++))
        echo ""
    done

    local end_time=$(date +%s)
    local total_elapsed=$((end_time - start_time))

    log_info "================================================================"
    log_info "全量崩溃分析 + 自动修复提交 完成"
    log_info "================================================================"
    log_info "统计:"
    log_info "  成功: $success_count"
    log_info "  失败: $fail_count"
    log_info "  总耗时: ${total_elapsed}秒 ($((total_elapsed / 60))分$((total_elapsed % 60))秒)"
    log_info "  日志文件: $LOG_FILE"
    log_info "================================================================"
}

# 循环执行（支持定时任务）
if [[ "$RUN_BACKGROUND" == "true" ]]; then
    log_info "后台模式启动，执行间隔: ${INTERVAL}秒"

    while true; do
        main

        log_info "等待 ${INTERVAL} 秒后执行下一次..."
        sleep "$INTERVAL"
    done
else
    # 前台执行一次
    main
fi
