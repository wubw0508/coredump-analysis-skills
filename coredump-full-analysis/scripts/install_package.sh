#!/bin/bash
#=============================================================================
# 包安装脚本
# 功能：安装指定版本的deb包和dbgsym包
#=============================================================================

set -e

# 配色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOAD_ACCOUNTS_SCRIPT="$SCRIPT_DIR/load_accounts.sh"

# 帮助信息
show_help() {
    cat << EOF
${BLUE}=============================================================================
  包安装脚本 - 安装指定版本的deb包和dbgsym包
=============================================================================${NC}

${GREEN}用法:${NC}
    $0 [选项] --package <name> --version <version> --download-dir <dir>

${GREEN}选项:${NC}
    --package <name>       包名（必需）
    --version <version>    版本号（必需）
    --download-dir <dir>  下载目录（必需）
    --only-dbgsym         仅安装dbgsym包
    --no-dbgsym           不安装dbgsym包
    --force               强制安装，忽略已安装检查
    --help, -h            显示此帮助信息

${GREEN}示例:${NC}
    # 安装主包和dbgsym包
    $0 --package dde-session-ui --version 1:5.9.6-1 --download-dir ./downloads

    # 仅安装dbgsym包
    $0 --package dde-session-ui --version 5.8.32 --download-dir ./downloads --only-dbgsym

    # 强制重装
    $0 --package dde-session-ui --version 5.8.32 --download-dir ./downloads --force

${BLUE}=============================================================================
${NC}
EOF
}

# 解析参数
parse_args() {
    PACKAGE=""
    VERSION=""
    DOWNLOAD_DIR=""
    ONLY_DBGsym=false
    NO_DBGsym=false
    FORCE=false
    SUDO_PASSWORD=""
    CLI_SUDO_PASSWORD=""

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
            --download-dir)
                DOWNLOAD_DIR="$2"
                shift 2
                ;;
            --only-dbgsym)
                ONLY_DBGsym=true
                shift
                ;;
            --no-dbgsym)
                NO_DBGsym=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --sudo-password)
                CLI_SUDO_PASSWORD="$2"
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
    if [[ -z "$PACKAGE" ]] || [[ -z "$VERSION" ]] || [[ -z "$DOWNLOAD_DIR" ]]; then
        echo -e "${RED}错误: 必须指定 --package, --version 和 --download-dir${NC}"
        show_help
        exit 1
    fi

    # 检查下载目录存在
    if [[ ! -d "$DOWNLOAD_DIR" ]]; then
        echo -e "${RED}错误: 下载目录不存在: $DOWNLOAD_DIR${NC}"
        exit 1
    fi
}

load_system_account() {
    if [[ ! -f "$LOAD_ACCOUNTS_SCRIPT" ]]; then
        echo -e "${RED}错误: 账号加载脚本不存在: $LOAD_ACCOUNTS_SCRIPT${NC}"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$LOAD_ACCOUNTS_SCRIPT"
    load_accounts_or_die system
    SUDO_PASSWORD="$SUDO_PASSWORD"

    if [[ -n "$CLI_SUDO_PASSWORD" ]]; then
        echo -e "${YELLOW}警告: --sudo-password 已废弃，运行时统一从 accounts.json 读取 system.sudo_password${NC}"
    fi
}

# 获取deb文件路径
find_deb_file() {
    local package="$1"
    local version="$2"
    local download_dir="$3"
    local is_dbgsym="$4"

    # 尝试多种文件名格式
    local patterns=()

    if [[ "$is_dbgsym" = true ]]; then
        patterns=(
            "${package}-dbgsym_${version}_amd64.deb"
            "${package}-dbgsym_${version}-1_amd64.deb"
            "${package}-dbgsym_1:${version}_amd64.deb"
            "${package}-dbgsym_1:${version}-1_amd64.deb"
            "${package}-dbg_${version}_amd64.deb"
            "${package}-dbg_${version}-1_amd64.deb"
        )
    else
        patterns=(
            "${package}_${version}_amd64.deb"
            "${package}_${version}-1_amd64.deb"
            "${package}_1:${version}_amd64.deb"
            "${package}_1:${version}-1_amd64.deb"
        )
    fi

    for pattern in "${patterns[@]}"; do
        local file_path="$download_dir/$pattern"
        if [[ -f "$file_path" ]]; then
            echo "$file_path"
            return 0
        fi
    done

    return 1
}

# 检查包是否已安装
check_installed() {
    local package="$1"
    local version="$2"

    local current_version=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || echo "")

    if [[ -z "$current_version" ]]; then
        echo "not_installed"
        return 0
    fi

    # 精确匹配
    if [[ "$current_version" == "$version" ]]; then
        echo "exact_match"
        return 0
    fi

    # 匹配1:前缀的版本
    if [[ "$current_version" == "1:${version}" ]]; then
        echo "exact_match"
        return 0
    fi

    # 匹配-1后缀的版本
    if [[ "$current_version" == "${version}-1" ]]; then
        echo "exact_match"
        return 0
    fi

    # 匹配1:前缀和-1后缀的版本
    if [[ "$current_version" == "1:${version}-1" ]]; then
        echo "exact_match"
        return 0
    fi

    echo "different_version"
    return 0
}

# 安装deb包
install_deb() {
    local deb_file="$1"
    local package_name="$2"
    local is_dbgsym="$3"

    echo -e "${CYAN}  → 安装: $(basename "$deb_file")${NC}"

    # 设置sudo密码（如果提供）
    local sudo_cmd="sudo"
    if [[ -n "$SUDO_PASSWORD" ]]; then
        sudo_cmd="echo '$SUDO_PASSWORD' | sudo -S"
    fi

    # 执行安装
    if eval "$sudo_cmd dpkg -i '$deb_file'"; then
        echo -e "${GREEN}    ✅ 安装成功${NC}"
        return 0
    else
        # 尝试修复依赖
        echo -e "${YELLOW}    dpkg返回错误，尝试修复依赖...${NC}"
        if eval "$sudo_cmd apt-get install -f -y"; then
            # 重试安装
            if eval "$sudo_cmd dpkg -i '$deb_file'"; then
                echo -e "${GREEN}    ✅ 修复依赖后安装成功${NC}"
                return 0
            fi
        fi

        echo -e "${RED}    ❌ 安装失败${NC}"
        return 1
    fi
}

# 主函数
main() {
    parse_args "$@"
    load_system_account

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}包安装${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "包名: ${PACKAGE}"
    echo -e "版本: ${VERSION}"
    echo -e "下载目录: ${DOWNLOAD_DIR}"
    echo ""

    local success=true
    local install_count=0

    # 安装主包
    if [[ "$ONLY_DBGsym" = false ]]; then
        echo -e "${CYAN}[1/2] 主包安装${NC}"
        local deb_file=$(find_deb_file "$PACKAGE" "$VERSION" "$DOWNLOAD_DIR" false)

        if [[ -z "$deb_file" ]]; then
            echo -e "${YELLOW}  → 未找到主包${NC}"
            echo -e "  尝试的文件名:"
            echo "    - ${PACKAGE}_${VERSION}_amd64.deb"
            echo "    - ${PACKAGE}_${VERSION}-1_amd64.deb"
            echo "    - ${PACKAGE}_1:${VERSION}_amd64.deb"
            success=false
        else
            echo -e "  → 找到文件: $(basename "$deb_file")"

            # 检查是否已安装
            if [[ "$FORCE" = false ]]; then
                local installed_status=$(check_installed "$PACKAGE" "$VERSION")
                case "$installed_status" in
                    exact_match)
                        if dpkg -l | grep -q "^ii.*${PACKAGE} "; then
                            echo -e "${GREEN}  ✅ 包已安装相同版本，跳过${NC}"
                            install_count=1
                        else
                            # 包已安装但dpkg列表有问题，尝试安装
                            install_deb "$deb_file" "$PACKAGE" false && install_count=1 || success=false
                        fi
                        ;;
                    different_version)
                        echo -e "${YELLOW}  ⚠️  已安装不同版本${NC}"
                        echo -e "  当前版本: $(check_installed "$PACKAGE" "$VERSION" | head -1)"
                        echo -e "  目标版本: $VERSION"

                        # 尝试覆盖安装
                        if read -p "  是否覆盖安装？(y/n): " -n 1 -r; then
                            echo ""
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                install_deb "$deb_file" "$PACKAGE" false && install_count=1 || success=false
                            else
                                echo -e "  跳过安装"
                            fi
                        fi
                        ;;
                    not_installed)
                        # 包未安装，正常安装
                        install_deb "$deb_file" "$PACKAGE" false && install_count=1 || success=false
                        ;;
                esac
            else
                # 强制安装
                install_deb "$deb_file" "$PACKAGE" false && install_count=1 || success=false
            fi
        fi
        echo ""
    fi

    # 安装dbgsym包
    if [[ "$NO_DBGsym" = false ]]; then
        echo -e "${CYAN}[2/2] dbgsym包安装${NC}"
        local dbgsym_file=$(find_deb_file "$PACKAGE" "$VERSION" "$DOWNLOAD_DIR" true)

        if [[ -z "$dbgsym_file" ]]; then
            echo -e "${YELLOW}  → 未找到dbgsym包${NC}"
            echo -e "  尝试的文件名:"
            echo "    - ${PACKAGE}-dbgsym_${VERSION}_amd64.deb"
            echo "    - ${PACKAGE}-dbg_${VERSION}_amd64.deb"
            echo -e "  这不会影响基本分析，但可能限制某些调试功能"
        else
            echo -e "  → 找到文件: $(basename "$dbgsym_file")"

            # dbgsym通常强制安装
            if install_deb "$dbgsym_file" "${PACKAGE}-dbgsym" true; then
                install_count=$((install_count + 1))
            else
                echo -e "${YELLOW}  → dbgsym包安装失败，不影响主包功能${NC}"
            fi
        fi
        echo ""
    fi

    # 汇总
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "安装摘要:"
    echo -e "  成功安装: ${install_count}/2 个包"

    if [[ "$success" = true ]]; then
        echo -e "${GREEN}✅ 安装完成${NC}"
    else
        echo -e "${YELLOW}⚠️  安装完成（有警告）${NC}"
    fi
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [[ "$success" = false ]]; then
        exit 1
    fi
}

# 运行
main "$@"
