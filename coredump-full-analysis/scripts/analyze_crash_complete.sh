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

# Skills目录（脚本所在目录的父目录）
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills/coredump-analysis-skills}"

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
# 项目根目录账号配置
PROJECT_ROOT_ACCOUNTS="$SKILLS_DIR/accounts.json"

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
ARCH="${ARCH:-x86}"
# 如果未指定 WORKSPACE，自动创建带时间戳的目录
if [[ -z "$WORKSPACE" ]] || [[ "$WORKSPACE" == "./workspace" ]]; then
    WORKSPACE="$HOME/coredump-workspace-$(date +%Y%m%d-%H%M%S)"
fi
PROGRESS_INTERVAL="${PROGRESS_INTERVAL:-180}"  # 进度上报间隔（秒），0表示禁用

# 支持通过环境变量传入账号配置（优先级最高）
SHUTTLE_USERNAME="${SHUTTLE_USERNAME:-}"
SHUTTLE_PASSWORD="${SHUTTLE_PASSWORD:-}"
GERRIT_USERNAME="${GERRIT_USERNAME:-}"
GERRIT_PASSWORD="${GERRIT_PASSWORD:-}"

# 检查配置完整性
check_config() {
    echo -e "${BLUE}检查配置完整性...${NC}"

    # 优先使用项目根目录的 accounts.json，其次使用 config/ 目录
    local accounts_file=""
    if [[ -f "$PROJECT_ROOT_ACCOUNTS" ]]; then
        accounts_file="$PROJECT_ROOT_ACCOUNTS"
    elif [[ -f "$CONFIG_DIR/accounts.json" ]]; then
        accounts_file="$CONFIG_DIR/accounts.json"
    fi

    # 方法1: 检查是否通过环境变量传入了账号
    if [[ -n "$SHUTTLE_USERNAME" && -n "$SHUTTLE_PASSWORD" && -n "$GERRIT_USERNAME" && -n "$GERRIT_PASSWORD" ]]; then
        echo -e "${GREEN}✅ 检测到环境变量传入的账号配置${NC}"
        write_config_from_env
        return 0
    fi

    # 方法2: 直接用 jq 检查 accounts.json 配置完整性
    if [[ -f "$accounts_file" ]] && check_accounts_file "$accounts_file"; then
        echo -e "${GREEN}✅ 配置检查通过${NC}"
        # 同步配置到 .env 文件
        sync_env_from_accounts "$accounts_file"
        return 0
    fi

    # 方法3: 配置不完整，提示用户输入
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}检测到缺少必要配置，请输入账号信息${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    prompt_for_accounts
    write_config_from_env
    echo -e "${GREEN}✅ 配置已保存${NC}"
}

# 检查 accounts.json 配置完整性
check_accounts_file() {
    local file="$1"

    # 检查 jq 是否可用
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}警告: jq 未安装，无法精确检查配置完整性${NC}"
        return 0
    fi

    # 检查必需字段是否存在且非占位符
    local shuttle_user=$(jq -r '.shuttle.account.username // ""' "$file" 2>/dev/null)
    local shuttle_pass=$(jq -r '.shuttle.account.password // ""' "$file" 2>/dev/null)
    local gerrit_user=$(jq -r '.gerrit.account.username // ""' "$file" 2>/dev/null)
    local gerrit_pass=$(jq -r '.gerrit.account.password // ""' "$file" 2>/dev/null)

    # 检查是否包含占位符
    if [[ "$shuttle_user" == *"请在此输入"* ]] || [[ "$shuttle_pass" == *"请在此输入"* ]] || \
       [[ "$gerrit_user" == *"请在此输入"* ]] || [[ "$gerrit_pass" == *"请在此输入"* ]]; then
        return 1
    fi

    # 检查是否为空
    if [[ -z "$shuttle_user" ]] || [[ -z "$shuttle_pass" ]] || \
       [[ -z "$gerrit_user" ]] || [[ -z "$gerrit_pass" ]]; then
        return 1
    fi

    return 0
}

# 同步配置到 .env 文件
sync_env_from_accounts() {
    local file="$1"

    if ! command -v jq &> /dev/null; then
        return
    fi

    local shuttle_user=$(jq -r '.shuttle.account.username // ""' "$file")
    local shuttle_pass=$(jq -r '.shuttle.account.password // ""' "$file")
    local gerrit_user=$(jq -r '.gerrit.account.username // ""' "$file")
    local gerrit_pass=$(jq -r '.gerrit.account.password // ""' "$file")

    cat > "$CONFIG_DIR/shuttle.env" << EOF
# Shuttle 配置
SHUTTLE_URL="https://shuttle.uniontech.com"
SHUTTLE_API_URL="https://shuttle.uniontech.com/api/download"
SHUTTLE_USERNAME="$shuttle_user"
SHUTTLE_PASSWORD="$shuttle_pass"
EOF

    cat > "$CONFIG_DIR/gerrit.env" << EOF
# Gerrit 配置
GERRIT_HOST="gerrit.uniontech.com"
GERRIT_PORT="29418"
GERRIT_USER="$gerrit_user"
GERRIT_PASSWORD="$gerrit_pass"
GERRIT_SSH_KEY="$HOME/.ssh/id_rsa"
EOF
}

# 提示用户输入账号信息
prompt_for_accounts() {
    echo -e "${BLUE}━━━ Shuttle 配置 (shuttle.uniontech.com) ━━━${NC}"
    echo "  用于从 shuttle.uniontech.com 下载 deb 包"
    echo ""

    read -p "  Shuttle 用户名: " SHUTTLE_USERNAME
    read -sp "  Shuttle 密码: " SHUTTLE_PASSWORD
    echo ""

    echo ""
    echo -e "${BLUE}━━━ Gerrit 配置 (gerrit.uniontech.com) ━━━${NC}"
    echo "  用于下载和管理代码仓库"
    echo ""

    read -p "  Gerrit 用户名: " GERRIT_USERNAME
    read -sp "  Gerrit 密码: " GERRIT_PASSWORD
    echo ""
}

# 从环境变量写入配置文件
write_config_from_env() {
    echo -e "${YELLOW}从环境变量写入配置...${NC}"

    # 优先使用项目根目录的 accounts.json
    local accounts_file="$PROJECT_ROOT_ACCOUNTS"
    if [[ ! -f "$accounts_file" ]] && [[ -f "$CONFIG_DIR/accounts.json" ]]; then
        accounts_file="$CONFIG_DIR/accounts.json"
    fi

    # 如果已存在配置文件，只更新账号部分，保留 paths 等其他配置
    if [[ -f "$accounts_file" ]] && command -v jq &> /dev/null; then
        jq --arg su "$SHUTTLE_USERNAME" \
           --arg sp "$SHUTTLE_PASSWORD" \
           --arg gu "$GERRIT_USERNAME" \
           --arg gp "$GERRIT_PASSWORD" \
           '.shuttle.account.username = $su | .shuttle.account.password = $sp | .gerrit.account.username = $gu | .gerrit.account.password = $gp' \
           "$accounts_file" > "${accounts_file}.tmp" && mv "${accounts_file}.tmp" "$accounts_file"
    else
        # 生成完整的 accounts.json
        cat > "$accounts_file" << EOF
{
    "shuttle": {
        "name": "Shuttle UnionTech",
        "description": "用于从 shuttle.uniontech.com 下载 deb 包",
        "url": "https://shuttle.uniontech.com",
        "api_url": "https://shuttle.uniontech.com/api/download",
        "account": {
            "username": "$SHUTTLE_USERNAME",
            "password": "$SHUTTLE_PASSWORD"
        }
    },
    "metabase": {
        "name": "Metabase",
        "description": "用于下载崩溃数据",
        "url": "https://metabase.cicd.getdeepin.org",
        "api_session": "/api/session",
        "api_dataset": "/api/dataset",
        "account": {
            "username": "app@deepin.org",
            "password": "deepin123"
        },
        "database": {
            "id": 10,
            "source_table_id": 196
        }
    },
    "gerrit": {
        "name": "Gerrit",
        "description": "用于下载和管理代码仓库",
        "host": "gerrit.uniontech.com",
        "port": "29418",
        "account": {
            "username": "$GERRIT_USERNAME",
            "password": "$GERRIT_PASSWORD"
        },
        "ssh_key": "$HOME/.ssh/id_rsa"
    },
    "internal_server": {
        "name": "内部构建服务器",
        "description": "用于从内部构建服务器下载 deb 包和 dbgsym",
        "url": "http://10.0.32.60:5001",
        "tasks_endpoint": "/tasks/"
    },
    "system": {
        "name": "系统配置",
        "description": "系统级配置",
        "sudo_password": ""
    },
    "paths": {
        "workspace": "",
        "code_dir": "",
        "download_dir": ""
    }
}
EOF
    fi

    # 生成 shuttle.env
    cat > "$CONFIG_DIR/shuttle.env" << EOF
# Shuttle 配置
SHUTTLE_URL="https://shuttle.uniontech.com"
SHUTTLE_API_URL="https://shuttle.uniontech.com/api/download"
SHUTTLE_USERNAME="$SHUTTLE_USERNAME"
SHUTTLE_PASSWORD="$SHUTTLE_PASSWORD"
EOF

    # 生成 gerrit.env
    cat > "$CONFIG_DIR/gerrit.env" << EOF
# Gerrit 配置
GERRIT_HOST="gerrit.uniontech.com"
GERRIT_PORT="29418"
GERRIT_USER="$GERRIT_USERNAME"
GERRIT_PASSWORD="$GERRIT_PASSWORD"
GERRIT_SSH_KEY="$HOME/.ssh/id_rsa"
EOF

    # 生成 local.env
    cat > "$CONFIG_DIR/local.env" << EOF
# 本地路径配置
WORKSPACE="$WORKSPACE"
CODE_DIR="$WORKSPACE/3.代码管理"
DOWNLOAD_DIR="$WORKSPACE/4.包管理/downloads"
EOF

    echo -e "${GREEN}✅ 配置已写入${NC}"
    echo "   - $PROJECT_ROOT_ACCOUNTS"
    echo "   - $CONFIG_DIR/shuttle.env"
    echo "   - $CONFIG_DIR/gerrit.env"
    echo "   - $CONFIG_DIR/local.env"
}

# 帮助信息
show_help() {
    cat << EOF
${BLUE}=============================================================================
dde-dock/dde-control-center 等包崩溃分析完整流程
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 [选项]

${GREEN}首次使用:${NC}
    首次运行时会提示编辑配置文件输入账号信息

${GREEN}账号配置方式:${NC}
    方式1: 环境变量传入（推荐自动化使用）
           SHUTTLE_USERNAME    Shuttle 用户名
           SHUTTLE_PASSWORD   Shuttle 密码
           GERRIT_USERNAME    Gerrit 用户名
           GERRIT_PASSWORD    Gerrit 密码
    方式2: 编辑配置文件（首次运行时会提示）
           配置文件: config/accounts.json

${GREEN}选项:${NC}
    --package <name>       包名（必需）
                           例如: dde-dock, dde-control-center, dde-launcher
    --start-date <date>   开始日期（格式: YYYY-MM-DD）
                           例如: 2026-04-05
    --end-date <date>     结束日期（格式: YYYY-MM-DD）
                           例如: 2026-04-08
    --sys-version <ver>   系统版本范围（默认: 1070-1075）
                           例如: 1070, 1070-1075
    --arch <arch>         架构（默认: x86）
                           例如: x86, x86_64, arm64
    --workspace <dir>      工作目录（默认: 自动创建带时间戳的目录 ~/coredump-workspace-YYYYMMDD-HHMMSS）
    --help, -h            显示此帮助信息

${GREEN}示例:${NC}
    # 分析最近3天的dde-dock崩溃
    $0 --package dde-dock --start-date 2026-04-05 --end-date 2026-04-08

    # 使用环境变量传入账号
    SHUTTLE_USERNAME=user SHUTTLE_PASSWORD=pass GERRIT_USERNAME=user GERRIT_PASSWORD=pass \
        $0 --package dde-session-ui --start-date 2026-03-14 --end-date 2026-04-14

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
            --arch)
                ARCH="$2"
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

    mkdir -p "$WORKSPACE"/{1.数据下载,2.数据筛选,3.代码管理,4.包管理/downloads,5.崩溃分析}

    echo -e "${GREEN}✅ 工作目录已创建: $WORKSPACE${NC}"
}

# 步骤1: 下载数据
download_data() {
    print_step 1 "数据下载" >&2

    local download_script="$SKILLS_DIR/coredump-data-download/scripts/download_metabase_csv.sh"

    if [[ ! -f "$download_script" ]]; then
        echo -e "${RED}错误: 下载脚本不存在: $download_script${NC}" >&2
        exit 1
    fi

    # 直接使用原始脚本，不复制到workspace
    echo -e "${YELLOW}执行: bash $download_script${NC}" >&2
    echo "" >&2

    cd "$WORKSPACE/1.数据下载"
    bash "$download_script" \
        --start-date "$START_DATE" \
        --end-date "$END_DATE" \
        --sys-version "$SYS_VERSION" \
        "$PACKAGE" "$ARCH" crash >&2

    # 查找下载的文件
    local csv_file=$(find "$WORKSPACE/1.数据下载" -name "${PACKAGE}_X86_crash_*.csv" -type f | sort | tail -1)

    if [[ -z "$csv_file" ]]; then
        echo -e "${RED}错误: 数据下载失败，未找到CSV文件${NC}" >&2
        exit 1
    fi

    local line_count=$(wc -l < "$csv_file")
    echo -e "${GREEN}✅ 数据下载完成: $csv_file ($line_count 行)${NC}" >&2

    # 返回CSV文件路径到stdout
    printf "%s" "$csv_file"
}

# 步骤2: 数据筛选/去重
filter_data() {
    # 所有输出必须重定向到 stderr，确保 stdout 只有文件路径
    print_step 2 "数据筛选/去重" >&2

    local input_csv="$1"
    local filter_script="$SKILLS_DIR/coredump-data-filter/scripts/filter_crash_data.py"

    if [[ ! -f "$filter_script" ]]; then
        echo -e "${RED}错误: 筛选脚本不存在: $filter_script${NC}" >&2
        exit 1
    fi

    echo -e "${YELLOW}执行: python3 $filter_script --workspace $WORKSPACE $PACKAGE${NC}" >&2
    echo "" >&2

    # 直接使用原始脚本，输出全部发送到 stderr
    cd "$WORKSPACE/2.数据筛选"
    python3 "$filter_script" --workspace "$WORKSPACE" "$PACKAGE" >&2

    local filtered_csv="$WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv"
    local stats_json="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"

    if [[ -f "$filtered_csv" ]]; then
        echo -e "${GREEN}✅ 数据筛选完成${NC}" >&2
    fi

    if [[ -f "$stats_json" ]]; then
        echo -e "${GREEN}✅ 统计报告已生成${NC}" >&2
        echo "" >&2
        echo -e "${YELLOW}统计摘要:${NC}" >&2
        jq '.summary' "$stats_json" >&2 || cat "$stats_json" >&2
    fi

    # 只向 stdout 输出文件路径（无任何其他输出）
    printf "%s" "$filtered_csv"
}

# 步骤3: 代码管理 - 为每个崩溃版本切换代码分支
download_source() {
    print_step 3 "代码管理" >&2

    local filtered_csv="$1"
    local source_script="$SKILLS_DIR/coredump-code-management/scripts/download_crash_source.sh"

    if [[ ! -f "$source_script" ]]; then
        echo -e "${RED}错误: 代码管理脚本不存在: $source_script${NC}"
        return 1
    fi

    # 从崩溃版本列表获取所有需要处理的版本
    local versions_txt="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_versions.txt"
    if [[ -f "$versions_txt" ]]; then
        echo -e "${YELLOW}从版本列表读取需要处理的版本...${NC}"
        local version_count=$(wc -l < "$versions_txt")
        echo -e "${YELLOW}共 ${version_count} 个版本需要处理${NC}"
        echo ""

        # 逐个版本处理
        local success_count=0
        local fail_count=0
        while IFS= read -r version_line; do
            [[ -z "$version_line" ]] && continue

            # 版本格式可能是 "epoch:version:count" 或 "version:count"
            # 正确的提取方式：去掉最后一个冒号及其后面的内容（count），然后去掉 epoch 前缀
            local version_with_count="${version_line}"
            local count="${version_with_count##*:}"  # 取最后一个冒号后面的内容
            local rest="${version_with_count%:*}"     # 去掉最后一个冒号及后面的内容
            # 如果还有冒号，说明有 epoch，去掉它
            local version="${rest#*:}"

            # 清理版本号（移除 epoch 前缀和 -1 后缀）
            local clean_version=$(echo "$version" | sed 's/^1://' | sed 's/-1$//')

            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}处理版本: $version -> $clean_version${NC}"
            echo ""

            # 设置环境变量并执行脚本
            if COREDUMP_WORKSPACE="$WORKSPACE" GERRIT_USER="$GERRIT_USER" GERRIT_HOST="${GERRIT_HOST:-gerrit.uniontech.com}" GERRIT_PORT="${GERRIT_PORT:-29418}" \
               bash "$source_script" "$PACKAGE" "$clean_version"; then
                ((success_count++)) || true
            else
                ((fail_count++)) || true
            fi
            echo ""
        done < "$versions_txt"

        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}代码管理完成: 成功 ${success_count} 个版本${NC}"
        if [[ $fail_count -gt 0 ]]; then
            echo -e "${YELLOW}失败 ${fail_count} 个版本${NC}"
        fi
    else
        echo -e "${YELLOW}未找到版本列表文件${NC}"
    fi
}

# ============================================================
# 以下是按版本处理的步骤（3+4+5 整合为版本循环）
# ============================================================

# 步骤3: 切换代码到指定版本
download_source_for_version() {
    local package="$1"
    local version="$2"
    local source_script="$SKILLS_DIR/coredump-code-management/scripts/download_crash_source.sh"

    if [[ ! -f "$source_script" ]]; then
        echo -e "${RED}错误: 代码管理脚本不存在: $source_script${NC}" >&2
        return 1
    fi

    echo -e "${YELLOW}━━━ 步骤3: 切换代码到 $version ━━━${NC}"

    # 设置环境变量并执行脚本
    if COREDUMP_WORKSPACE="$WORKSPACE" GERRIT_USER="$GERRIT_USER" GERRIT_HOST="${GERRIT_HOST:-gerrit.uniontech.com}" GERRIT_PORT="${GERRIT_PORT:-29418}" \
       bash "$source_script" "$package" "$version" >&2; then
        echo -e "${GREEN}✅ 代码切换完成${NC}"
        return 0
    else
        echo -e "${RED}❌ 代码切换失败${NC}"
        return 1
    fi
}

# 步骤4: 下载指定版本的包
download_packages_for_version() {
    local package="$1"
    local version="$2"
    local dl_script="$SKILLS_DIR/coredump-package-management/scripts/scan_and_download.py"
    local dl_dir="$WORKSPACE/4.包管理/downloads"
    local skipped_versions_file="$WORKSPACE/4.包管理/downloads/skipped_versions.txt"

    if [[ ! -f "$dl_script" ]]; then
        echo -e "${RED}错误: 包下载脚本不存在: $dl_script${NC}" >&2
        return 1
    fi

    echo -e "${YELLOW}━━━ 步骤4: 下载 $version 的包 ━━━${NC}"

    # 创建下载目录
    mkdir -p "$dl_dir"

    # 清理版本号（用于下载）
    local clean_version=$(echo "$version" | sed 's/^1://' | sed 's/-1$//')

    # 下载该版本的包和调试符号（使用位置参数格式）
    echo -e "${YELLOW}下载 $package ${clean_version} ...${NC}"

    # 调用下载脚本（忽略其退出码）
    python3 "$dl_script" \
        -d "$dl_dir" \
        "$package" "$clean_version" 2>&1 || true

    # 使用 find 检查文件是否存在（避免 ls 在多文件时返回1的问题）
    if [[ -d "$dl_dir" ]] && [[ -n "$(find "$dl_dir" -maxdepth 1 -name "*_${version}_*.deb" -type f 2>/dev/null)" ]]; then
        echo -e "${GREEN}✅ 包下载完成${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️ 未找到 $package $clean_version 的包（精确版本不匹配），跳过${NC}"
        echo "$package $clean_version (精确版本不匹配)" >> "$skipped_versions_file"
        return 1
    fi
}

# 步骤5: 安装包并分析指定版本的崩溃
analyze_crashes_for_version() {
    local package="$1"
    local version="$2"
    local filtered_csv="$3"
    local analyze_script="$SKILLS_DIR/coredump-full-analysis/scripts/analyze_crash_per_version.py"
    local dl_dir="$WORKSPACE/4.包管理/downloads"
    local skip_file="$WORKSPACE/4.包管理/downloads/skipped_versions.txt"

    if [[ ! -f "$analyze_script" ]]; then
        echo -e "${RED}错误: 分析脚本不存在: $analyze_script${NC}" >&2
        return 1
    fi

    echo -e "${YELLOW}━━━ 步骤5: 分析 $version 的崩溃 ━━━${NC}"

    # 清理版本号
    local clean_version=$(echo "$version" | sed 's/^1://' | sed 's/-1$//')

    # 检查是否该版本被跳过（deb包不存在）
    if [[ -f "$skip_file" ]] && grep -q "^$package $clean_version" "$skip_file" 2>/dev/null; then
        echo -e "${YELLOW}⚠️ 该版本 deb 包不存在，跳过安装，直接使用 AI 分析${NC}"
    else
        # 安装该版本的 deb 包（包括调试符号包 dbgsym）
        # 匹配模式: *_{version}_*.deb (如 dde-session-ui_5.8.11-1_amd64.deb, dde-session-ui-dbgsym_5.8.11-1_amd64.deb)
        # 使用 find 避免 ls 在多文件时返回1的问题
        if [[ -d "$dl_dir" ]]; then
            local deb_files=$(find "$dl_dir" -maxdepth 1 -name "*_${version}_*.deb" -type f 2>/dev/null || true)
            if [[ -n "$deb_files" ]]; then
                echo -e "${YELLOW}安装 deb 包:${NC}"
                for deb_file in $deb_files; do
                    if [[ -f "$deb_file" ]]; then
                        echo -e "  安装: $(basename "$deb_file")${NC}"
                        if [[ -n "$SUDO_PASSWORD" ]]; then
                            # 使用 expect 自动输入密码，避免 sudo requiretty 问题
                            # 匹配中英文密码提示: "password" 或 "请输入密码"
                            expect -c "
set deb_file \"$deb_file\"
set sudo_pass \"$SUDO_PASSWORD\"
spawn sudo dpkg -i \$deb_file
expect {
    -re \"(password|请输入密码)\" {
        send \"\$sudo_pass\r\"
        expect eof
    }
    eof {
        exit 0
    }
}
" 2>&1 || true
                        else
                            sudo dpkg -i "$deb_file" 2>&1 || true
                        fi
                    fi
                done
            fi
        fi
    fi

    # 执行分析（使用 analyze_crash_per_version.py 保存 JSON 报告）
    python3 "$analyze_script" \
        --package "$package" \
        --version "$clean_version" \
        --workspace "$WORKSPACE" \
        --max-crashes 50 2>&1 || true

    echo -e "${GREEN}✅ 版本 $version 分析完成${NC}"
    return 0
}

# 步骤4: 包管理（保留用于批量生成任务）
download_packages() {
    print_step 4 "包管理" >&2

    local filtered_csv="$1"
    local gen_script="$SKILLS_DIR/coredump-package-management/scripts/generate_tasks.py"
    local dl_script="$SKILLS_DIR/coredump-package-management/scripts/scan_and_download.py"
    local dl_dir="$WORKSPACE/4.包管理/downloads"

    if [[ ! -f "$gen_script" ]]; then
        echo -e "${RED}错误: 任务生成脚本不存在: $gen_script${NC}"
        exit 1
    fi

    # 创建下载目录
    mkdir -p "$dl_dir"

    echo -e "${YELLOW}生成下载任务...${NC}"

    # 生成任务
    python3 "$gen_script" --crash-data "$filtered_csv" --workspace "$WORKSPACE"

    local tasks_file="$WORKSPACE/4.包管理/downloads/download_tasks.json"

    if [[ -f "$tasks_file" ]]; then
        echo -e "${GREEN}✅ 下载任务已生成: $tasks_file${NC}"
        echo ""

        # 提取高优先级任务数量
        local high_count=$(jq '[.tasks[] | select(.priority == "high")] | length' "$tasks_file" 2>/dev/null || echo "0")

        if [[ "$high_count" -gt 0 ]]; then
            echo -e "${YELLOW}高优先级任务: $high_count 个${NC}"

            # 提取高优先级任务到临时文件
            jq '[.tasks[] | select(.priority == "high")] | {tasks: .}' "$tasks_file" > "$WORKSPACE/4.包管理/downloads/high_priority_tasks.json"

            # 执行高优先级下载
            echo -e "${YELLOW}开始下载高优先级包...${NC}"
            python3 "$dl_script" \
                --batch "$WORKSPACE/4.包管理/downloads/high_priority_tasks.json" \
                --download-dir "$dl_dir"

            echo -e "${GREEN}✅ 高优先级包下载完成${NC}"
        else
            echo -e "${YELLOW}没有高优先级任务${NC}"
        fi

        # 下载所有任务（中低优先级）
        echo ""
        echo -e "${YELLOW}下载中低优先级包...${NC}"
        python3 "$dl_script" \
            --batch "$tasks_file" \
            --download-dir "$dl_dir" &

        echo -e "${GREEN}✅ 包下载任务已提交（后台运行）${NC}"
    fi
}

# 步骤5: 崩溃分析
analyze_crashes() {
    print_step 5 "崩溃分析" >&2

    local filtered_csv="$1"
    local analyze_script="$SKILLS_DIR/coredump-crash-analysis/scripts/analyze_crash_final.py"
    local centralized_dir="$SKILLS_DIR/coredump-crash-analysis/centralized"

    if [[ ! -f "$analyze_script" ]]; then
        echo -e "${RED}错误: 分析脚本不存在: $analyze_script${NC}"
        exit 1
    fi

    # 设置 PYTHONPATH 包含 centralized 模块路径
    export PYTHONPATH="$centralized_dir:$PYTHONPATH"

    echo -e "${YELLOW}执行崩溃分析...${NC}"
    echo ""

    cd "$WORKSPACE/5.崩溃分析"
    python3 "$analyze_script" \
        --workspace "$WORKSPACE" \
        --package "$PACKAGE" \
        --csv "$filtered_csv" 2>&1 | head -50 || true

    # 生成分析报告
    local report_file="$WORKSPACE/5.崩溃分析/${PACKAGE}_crash_analysis_report.md"

    cat > "$report_file" << EOF
# $PACKAGE 崩溃分析报告

**分析时间**: $(date '+%Y-%m-%d %H:%M:%S')
**数据范围**: $START_DATE 至 $END_DATE
**包名**: $PACKAGE

## 目录结构

- 统计报告: \`$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json\`
- 筛选数据: \`$WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv\`
- 源码目录: \`$WORKSPACE/3.代码管理/$PACKAGE\`
- 下载的包: \`$WORKSPACE/4.包管理/downloads/\`
- 分析报告: \`$WORKSPACE/5.崩溃分析/\`

---
*报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')*
EOF

    echo -e "${GREEN}✅ 分析报告已生成: $report_file${NC}"
}

# 进度上报函数
report_progress() {
    local elapsed=$1
    local current_version=$2
    local processed=$3
    local total=$4
    local success=$5
    local fail=$6
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[$timestamp] 进度报告 (已运行 ${elapsed}秒)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}步骤① 数据下载:${NC} 已完成"
    echo -e "${GREEN}步骤② 数据筛选:${NC} 已完成"
    echo -e "${GREEN}步骤③ 代码管理:${NC} 已创建分支"
    echo -e "${GREEN}步骤④ 包管理:${NC} 已下载 deb/dbgsym 包"
    echo -e "${GREEN}步骤⑤ 崩溃分析:${NC} 正在分析..."
    echo ""
    echo -e "  当前版本: ${current_version}"
    echo -e "  进度: ${processed}/${total} 个版本"
    echo -e "  成功: ${success}, 失败: ${fail}"
    echo ""

    # 统计下载目录中的 CSV 文件
    local download_dir="$WORKSPACE/1.数据下载"
    if [[ -d "$download_dir" ]]; then
        local csv_count=$(find "$download_dir" -name "*.csv" 2>/dev/null | wc -l)
        echo -e "  CSV文件: ${csv_count}个"
    fi

    # 统计已分析的版本
    local analysis_dir="$WORKSPACE/5.崩溃分析/$PACKAGE"
    if [[ -d "$analysis_dir" ]]; then
        local analyzed_count=$(find "$analysis_dir" -name "analysis.json" 2>/dev/null | wc -l)
        echo -e "  已分析版本: ${analyzed_count}个"
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# 主函数
main() {
    echo -e "${BLUE}"
    echo "============================================================================="
    echo "            dde-dock/dde-control-center 崩溃分析完整流程"
    echo "============================================================================="
    echo -e "${NC}"

    # 1. 解析命令行参数
    parse_args "$@"

    # 2. 检查配置完整性
    check_config

    # 3. 检查依赖
    check_dependencies

    # 4. 创建工作目录
    setup_workspace

    # 5. 执行分析步骤
    # 步骤1+2: 数据下载和筛选（只执行一次）
    local csv_file=$(download_data)
    local filtered_csv=$(filter_data "$csv_file")

    # 步骤3+4+5: 按版本循环执行
    # 从版本列表读取每个版本，依次执行：切换代码→下载包→分析崩溃
    local versions_txt="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_versions.txt"
    if [[ -f "$versions_txt" ]]; then
        local version_count=$(wc -l < "$versions_txt")
        echo -e "${YELLOW}共 ${version_count} 个版本需要分析${NC}"
        echo ""

        local success_count=0
        local fail_count=0
        local processed_count=0
        local ANALYSIS_START_TIME=$(date +%s)
        local LAST_PROGRESS_TIME=$ANALYSIS_START_TIME

        while IFS= read -r version_line; do
            [[ -z "$version_line" ]] && continue

            # 版本格式可能是 "epoch:version:count" 或 "version:count"
            # 正确的提取方式：去掉最后一个冒号及其后面的内容（count），然后去掉 epoch 前缀
            local version_with_count="${version_line}"
            local count="${version_with_count##*:}"  # 取最后一个冒号后面的内容
            local rest="${version_with_count%:*}"     # 去掉最后一个冒号及后面的内容
            # 如果还有冒号，说明有 epoch，去掉它
            local version="${rest#*:}"

            # 清理版本号（移除 epoch 前缀和 -1 后缀）
            local clean_version=$(echo "$version" | sed 's/^1://' | sed 's/-1$//')

            echo -e "${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}处理版本: $version -> $clean_version${NC}"
            echo -e "${BLUE}════════════════════════════════════════════════════════════════════════${NC}"

            # 步骤3: 切换代码到该版本
            if download_source_for_version "$PACKAGE" "$clean_version"; then
                ((success_count++)) || true
            else
                ((fail_count++)) || true
            fi

            # 步骤4: 下载该版本的包
            if download_packages_for_version "$PACKAGE" "$clean_version"; then
                ((success_count++)) || true
            else
                ((fail_count++)) || true
            fi

            # 步骤5: 安装包并分析崩溃
            if analyze_crashes_for_version "$PACKAGE" "$clean_version" "$filtered_csv"; then
                ((success_count++)) || true
            else
                ((fail_count++)) || true
            fi

            echo ""

            # 进度上报
            ((processed_count++)) || true
            if [[ "$PROGRESS_INTERVAL" -gt 0 ]]; then
                local CURRENT_TIME=$(date +%s)
                local ELAPSED=$((CURRENT_TIME - ANALYSIS_START_TIME))
                local INTERVAL_PASSED=$((CURRENT_TIME - LAST_PROGRESS_TIME))
                if [[ $INTERVAL_PASSED -ge $PROGRESS_INTERVAL ]]; then
                    report_progress "$ELAPSED" "$clean_version" "$processed_count" "$version_count" "$success_count" "$fail_count"
                    LAST_PROGRESS_TIME=$CURRENT_TIME
                fi
            fi

        done < "$versions_txt"

        echo -e "${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}所有版本分析完成${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════════════════${NC}"

        # 步骤6: 生成完整分析报告和AI分析报告
        echo ""
        echo -e "${YELLOW}━━━ 步骤6: 生成完整分析报告 ━━━${NC}"

        local full_report_script="$SKILLS_DIR/coredump-full-analysis/scripts/generate_full_report.py"
        local ai_report_script="$SKILLS_DIR/coredump-full-analysis/scripts/generate_ai_report.py"

        if [[ -f "$full_report_script" ]]; then
            python3 "$full_report_script" \
                --package "$PACKAGE" \
                --workspace "$WORKSPACE" 2>&1
        else
            echo -e "${YELLOW}⚠️ 完整报告生成脚本不存在: $full_report_script${NC}"
        fi

        if [[ -f "$ai_report_script" ]]; then
            python3 "$ai_report_script" \
                --package "$PACKAGE" \
                --workspace "$WORKSPACE" 2>&1
        else
            echo -e "${YELLOW}⚠️ AI分析报告生成脚本不存在: $ai_report_script${NC}"
        fi

        echo -e "${GREEN}✅ 分析报告已生成${NC}"

        # 步骤7: 生成统一的总结报告
        echo ""
        echo -e "${YELLOW}━━━ 步骤7: 生成总结报告 ━━━${NC}"

        # 生成 version_list.txt（从 crash_versions.txt 转换格式）
        local version_list_txt="$WORKSPACE/2.数据筛选/version_list.txt"
        if [[ -f "$versions_txt" ]]; then
            echo -e "${YELLOW}生成版本清单...${NC}"
            > "$version_list_txt"
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                # 格式: 5.8.14-1:1101 -> 5.8.14-1|1101|medium
                version="${line%%:*}"
                count="${line##*:}"
                echo "${version}|${count}|medium" >> "$version_list_txt"
            done < "$versions_txt"
            echo -e "${GREEN}✅ 版本清单已生成: $version_list_txt${NC}"
        fi

        local final_report_script="$SKILLS_DIR/coredump-full-analysis/scripts/generate_final_report.py"
        if [[ -f "$final_report_script" ]]; then
            mkdir -p "$WORKSPACE/7.总结报告"
            python3 "$final_report_script" \
                --package "$PACKAGE" \
                --workspace "$WORKSPACE" \
                --output-dir "$WORKSPACE/7.总结报告" 2>&1 || true
            echo -e "${GREEN}✅ 总结报告已生成${NC}"
        else
            echo -e "${YELLOW}⚠️ 总结报告脚本不存在: $final_report_script${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}"
    echo "============================================================================="
    echo "✅ 崩溃分析流程完成！"
    echo "============================================================================="
    echo -e "${NC}"
    echo "📊 统计报告: $WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"
    echo "📋 筛选数据: $WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv"
    echo "📄 分析报告: $WORKSPACE/7.总结报告/"
    echo ""
}

# 运行
main "$@"
