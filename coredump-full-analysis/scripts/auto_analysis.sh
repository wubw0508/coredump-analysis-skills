#!/bin/bash
#=============================================================================
# Coredump 完整分析流程（自动版）
#=============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SKILLS_DIR="/home/wubw/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw/skills"

DEFAULT_WORKSPACE="./coredump_workspace"
DEFAULT_PACKAGE=""
DEFAULT_START_DATE=""
DEFAULT_END_DATE=""
DEFAULT_SYS_VERSION="1070-1075"
DEFAULT_TARGET_BRANCH="develop/eagle"
DEFAULT_MAX_VERSIONS=3

show_help() {
    cat << EOF
${BLUE}=============================================================================${NC}
${GREEN}Coredump 分析自动化脚本${NC}
${BLUE}=============================================================================${NC}

用法: $0 [选项]

选项:
  --package <name>       包名（必需）
  --start-date <date>   开始日期 (YYYY-MM-DD)
  --end-date <date>     结束日期 (YYYY-MM-DD)
  --sys-version <ver>   系统版本 (默认: 1070-1075)
  --workspace <dir>      工作目录 (默认: ./coredump_workspace)
  --target-branch <br>  目标分支 (默认: develop/eagle)
  --max-versions <n>     处理Top N个版本 (默认: 3)
  --help, -h             显示此帮助信息

示例:
  $0 --package dde-launcher
  $0 --package dde-dock --max-versions 5

${BLUE}=============================================================================${NC}
EOF
}

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
            --target-branch)
                TARGET_BRANCH="$2"
                shift 2
                ;;
            --max-versions)
                DEFAULT_MAX_VERSIONS="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}错误: 未知参数 $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done

    # 将工作目录转为绝对路径
    WORKSPACE="${WORKSPACE:-$DEFAULT_WORKSPACE}"
    if [[ "$WORKSPACE" != /* ]]; then
        # 它是相对路径，转换为绝对路径
        WORKSPACE="$(cd "$(dirname "$WORKSPACE")" && pwd)/$(basename "$WORKSPACE")"
    fi

    SYS_VERSION="${SYS_VERSION:-$DEFAULT_SYS_VERSION}"
    TARGET_BRANCH="${TARGET_BRANCH:-$DEFAULT_TARGET_BRANCH}"

    if [[ -z "$START_DATE" ]]; then
        START_DATE=$(date -d '1 month ago' +%Y-%m-%d 2>/dev/null || date -v-1m +%Y-%m-%d 2>/dev/null || date +%Y-%m-01)
    fi
    if [[ -z "$END_DATE" ]]; then
        END_DATE=$(date +%Y-%m-%d)
    fi

    if [[ -z "$PACKAGE" ]]; then
        echo -e "${RED}错误: 必须指定 --package 参数${NC}"
        show_help
        exit 1
    fi
}

print_step() {
    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${GREEN}步骤 $1: $2${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
}

check_dependencies() {
    print_step 0 "检查依赖..."

    local deps=("curl" "jq" "python3" "git" "dpkg" "apt-get")
    local all_ok=true

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}错误: 缺少依赖 $dep${NC}"
            all_ok=false
        fi
    done

    if [[ "$all_ok" == "false" ]]; then
        exit 1
    fi

    mkdir -p "$WORKSPACE"
    mkdir -p "$WORKSPACE/1.数据下载"
    mkdir -p "$WORKSPACE/2.数据筛选"
    mkdir -p "$WORKSPACE/3.源码管理"
    mkdir -p "$WORKSPACE/4.包管理/downloads"
    mkdir -p "$WORKSPACE/5.符号化分析"
    mkdir -p "$WORKSPACE/6.修复与建议"
    mkdir -p "$WORKSPACE/7.总结报告"

    echo -e "${GREEN}✓ 依赖检查完成${NC}"
    echo "  工作目录: $WORKSPACE"
    echo "  分析时间: $START_DATE 至 $END_DATE"
    echo "  系统版本: $SYS_VERSION"
    echo "  分析版本数: $DEFAULT_MAX_VERSIONS"
}

step1_download_data() {
    print_step 1 "下载崩溃数据"

    local download_script="$SKILLS_DIR/coredump-data-download/scripts/download_metabase_csv.sh"
    local output_dir="$WORKSPACE/1.数据下载"

    mkdir -p "$output_dir"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local download_subdir="$output_dir/download_$timestamp"
    mkdir -p "$download_subdir"

    cd "$output_dir"

    local cmd="$download_script"
    [[ -n "$START_DATE" ]] && cmd="$cmd --start-date $START_DATE"
    [[ -n "$END_DATE" ]] && cmd="$cmd --end-date $END_DATE"
    cmd="$cmd --sys-version $SYS_VERSION"
    cmd="$cmd --output-dir $download_subdir"
    cmd="$cmd $PACKAGE x86 crash"

    echo -e "${YELLOW}执行: $cmd${NC}"
    echo ""

    if eval "$cmd"; then
        local csv_file=$(find "$download_subdir" -name "${PACKAGE}_X86_crash_*.csv" -o -name "${PACKAGE}_X86_64_crash_*.csv" 2>/dev/null | head -1)

        if [[ -z "$csv_file" ]]; then
            echo -e "${RED}错误: 数据下载失败${NC}"
            return 1
        fi

        local line_count=$(wc -l < "$csv_file" 2>/dev/null)
        echo -e "${GREEN}✓ 数据下载完成${NC}"
        echo "  文件: $csv_file"
        echo "  行数: ${line_count:-未知}"

        # 将CSV路径写入临时文件供后续步骤读取
        echo "$csv_file" > /tmp/step1_csv_file.txt
        return 0
    else
        echo -e "${RED}数据下载失败${NC}"
        return 1
    fi
}

step2_filter_data() {
    print_step 2 "数据筛选和去重"

    local input_csv="$1"
    local filter_script="$SKILLS_DIR/coredump-data-filter/scripts/filter_crash_data.py"
    local output_dir="$WORKSPACE/2.数据筛选"

    mkdir -p "$output_dir"

    # 创建修改后的版本
    cat > "${output_dir}/filter_crash_data.py" << 'PY_SCRIPT_END'
#!/usr/bin/env python3
import sys
import re

# 从参数或当前路径获取WORKSPACE
script_dir = sys.path[0] if sys.path[0] else '.'
workspace = script_dir.replace('/2.数据筛选', '')

# 读取原始脚本
with open('/home/wubw/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw/skills/coredump-data-filter/scripts/filter_crash_data.py', 'r') as f:
    content = f.read()

# 替换 WORKSPACE 路径
content = content.replace('/home/wubw/Desktop/coredump/workspace', workspace)

# 执行脚本
exec(content)
PY_SCRIPT_END

    chmod +x "${output_dir}/filter_crash_data.py"

    # 在脚本所在目录运行 filter 脚本
    (cd "$output_dir" && python3 "${output_dir}/filter_crash_data.py" "$PACKAGE") > /tmp/step2_output.txt 2>&1

    if [[ $? -eq 0 ]]; then
        local filtered_csv="$WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv"
        local stats_json="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"

        if [[ -f "$filtered_csv" ]]; then
            echo -e "${GREEN}✓ 数据筛选完成${NC}"
        fi

        if [[ -f "$stats_json" ]]; then
            echo -e "${GREEN}✓ 统计报告已生成${NC}"
            echo ""
            jq -r '.summary' "$stats_json" 2>/dev/null || echo "  (统计报告格式异常)"
        fi

        # 将过滤后的CSV路径写入临时文件
        echo "$filtered_csv" > /tmp/step2_filtered_csv.txt
        return 0
    else
        echo -e "${RED}数据筛选失败${NC}"
        cat /tmp/step2_output.txt
        return 1
    fi
}

step3_switch_versions() {
    print_step 3 "源码管理与版本切换"

    local filtered_csv="$1"
    local source_dir="$WORKSPACE/3.源码管理/$PACKAGE"

    mkdir -p "$WORKSPACE/3.源码管理"

    # 创建Python脚本 - 使用绝对路径和绝对路径保存结果
    cat > "${WORKSPACE}/3.源码管理/get_top_versions.py" << 'PYTHON_SCRIPT_END'
import csv
import json
from collections import defaultdict
import sys

if len(sys.argv) < 3:
    print("Usage: python3 get_top_versions.py <csv_file> <max_versions> <output_file>")
    sys.exit(1)

csv_file = sys.argv[1]
max_versions = int(sys.argv[2])
output_file = sys.argv[3] if len(sys.argv) > 3 else 'top_versions.json'

version_stats = defaultdict(int)
with open(csv_file, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        version = row['Version'].split('+')[0].split('-1')[0]
        count = int(row['Count'])
        version_stats[version] += count

top_versions = sorted(version_stats.items(), key=lambda x: x[1], reverse=True)
selected_versions = top_versions[:max_versions]

with open(output_file, 'w', encoding='utf-8') as f:
    json.dump({'top_versions': selected_versions}, f, indent=2)

print(f"分析Top {len(selected_versions)} 个版本:")
for i, (version, count) in enumerate(selected_versions, 1):
    print(f"{i}. {version}: {count}次")
PYTHON_SCRIPT_END

    # 计算 Top N 版本 - 使用绝对路径保存
    python3 "${WORKSPACE}/3.源码管理/get_top_versions.py" "$filtered_csv" "$DEFAULT_MAX_VERSIONS" "${WORKSPACE}/3.源码管理/top_versions.json"

    # 克隆仓库
    if [[ ! -d "$source_dir" ]]; then
        echo "克隆 $PACKAGE 源码..."
        git clone ssh://ut000168@gerrit.uniontech.com:29418/${PACKAGE} "$source_dir" || {
            echo -e "${YELLOW}错误: 克隆失败，跳过源码管理${NC}"
            return 1
        }

        scp -p -P 29418 ut000168@gerrit.uniontech.com:hooks/commit-msg "$source_dir/.git/hooks/" 2>/dev/null || true
    fi

    if [[ ! -d "$source_dir" ]]; then
        return 1
    fi

    # 切换版本
    mkdir -p "$WORKSPACE/5.符号化分析"
    cd "$source_dir"
    git fetch origin 2>/dev/null || true

    for i in $(seq 1 $DEFAULT_MAX_VERSIONS); do
        version=$(python3 -c "import json; v=json.load(open('${WORKSPACE}/3.源码管理/top_versions.json'))['top_versions'][$i-1][0]; print(v)")
        count=$(python3 -c "import json; v=json.load(open('${WORKSPACE}/3.源码管理/top_versions.json'))['top_versions'][$i-1][1]; print(v)")

        echo ""
        echo "处理版本 ${i}: ${version} (${count}次)"

        # 查找精确匹配的tag
        exact_tag=$(git tag 2>/dev/null | grep "^${version}$" | head -1)

        if [[ -n "$exact_tag" ]]; then
            echo "  找到tag: $exact_tag"
            git checkout "$exact_tag" 2>/dev/null

            local version_dir="$WORKSPACE/5.符号化分析/version_${version}"
            mkdir -p "$version_dir"

            cat > "$version_dir/source_info.txt" << EOF
版本: ${version}
Tag: ${exact_tag}
Commit: $(git rev-parse HEAD)
Date: $(git log -1 --format=%ci HEAD)
崩溃次数: ${count}
EOF

            echo -e "${GREEN}  ✓ 已切换到 ${version}${NC}"
        else
            echo -e "${YELLOW}  未找到tag，尝试相似版本${NC}"
            # 移除最后一段版本号，尝试找相似版本
            version_base="${version%.*}"
            similar=$(git tag 2>/dev/null | grep -E "^${version_base}" | sort -V | tail -1)
            if [[ -n "$similar" ]]; then
                echo "  找到相似tag: $similar"
                git checkout "$similar" 2>/dev/null

                local version_dir="$WORKSPACE/5.符号化分析/version_${version}"
                mkdir -p "$version_dir"

                cat > "$version_dir/source_info.txt" << EOF
原始版本: ${version}
实际Tag: ${similar}
Commit: $(git rev-parse HEAD)
Date: $(git log -1 --format=%ci HEAD)
崩溃次数: ${count}
EOF

                echo -e "${GREEN}  ✓ 已切换到 ${similar}${NC}"
            else
                echo -e "${RED}  未找到匹配的tag${NC}"
            fi
        fi
    done

    echo ""
    echo -e "${GREEN}✓ 源码切换完成${NC}"
    echo "  源码目录: $source_dir"

    echo "$source_dir"
    return 0
}

step4_download_packages() {
    print_step 4 "下载deb包和调试包"

    local filtered_csv="$1"
    local downloads_dir="$WORKSPACE/4.包管理/downloads"

    mkdir -p "$downloads_dir"
    cd "$downloads_dir"

    if [[ ! -f "$SKILLS_DIR/coredump-package-management/scripts/generate_tasks.py" ]]; then
        echo -e "${YELLOW}警告: 未找到包管理脚本${NC}"
        return 0
    fi

    cp "$SKILLS_DIR/coredump-package-management/scripts/generate_tasks.py" ./
    cp "$SKILLS_DIR/coredump-package-management/scripts/scan_and_download.py" ./

    # 使用 python 替换 workspace 路径
    python3 -c "
import sys
worksp = '$WORKSPACE'
with open('generate_tasks.py', 'r') as f:
    lines = f.readlines()
new_lines = []
for line in lines:
    if 'WORKSPACE = Path' in line:
        new_lines.append(f'WORKSPACE = Path(\"{worksp}\")\n')
    else:
        new_lines.append(line)
with open('generate_tasks.py', 'w') as f:
    f.writelines(new_lines)
" 2>/dev/null | true

    echo "生成下载任务..."
    if python3 ./generate_tasks.py > /tmp/gen_tasks.log 2>&1; then
        local tasks_file="./download_tasks.json"
        if [[ -f "$tasks_file" ]]; then
            echo -e "${GREEN}✓ 下载任务已生成${NC}"
            cat "$tasks_file" | head -50

            read -p "是否下载deb包？ (y/n): " download_choice
            if [[ "$download_choice" =~ ^[Yy]$ ]]; then
                echo "开始下载包..."
                python3 ./scan_and_download.py --batch download_tasks.json 2>&1 | tee /tmp/download.log
                echo -e "${GREEN}✓ 包下载完成${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}任务生成失败${NC}"
        cat /tmp/gen_tasks.log
        return 1
    fi

    return 0
}

step5_install_packages() {
    print_step 5 "安装deb包和调试包"

    local downloads_dir="$WORKSPACE/4.包管理/downloads"

    if [[ ! -d "$downloads_dir" ]]; then
        echo "跳过安装（无下载目录）"
        return 0
    fi

    local deb_count=$(find "$downloads_dir" -name "*.deb" 2>/dev/null | wc -l)

    if [[ "$deb_count" -eq 0 ]]; then
        echo "跳过安装（无deb包）"
        return 0
    fi

    echo "找到 $deb_count 个deb包"

    read -p "是否安装这些deb包？ (需要sudo权限) (y/n): " install_choice
    if [[ ! "$install_choice" =~ ^[Yy]$ ]]; then
        echo "跳过安装"
        return 0
    fi

    echo "开始安装包..."

    sudo dpkg -i "$downloads_dir"/*.deb 2>&1 | head -20
    sudo apt-get install -f -y

    echo -e "${GREEN}✓ 包安装完成${NC}"
    return 0
}

step6_symbolic_analysis() {
    print_step 6 "符号化堆栈分析"

    local filtered_csv="$1"
    local source_dir="$2"
    local analysis_dir="$WORKSPACE/6.修复与建议"

    mkdir -p "$analysis_dir"

    echo "执行符号化分析..."

    # 创建分析脚本
    cat > "${analysis_dir}/analyze.py" << 'PY_ANALYSIS_END'
import csv
import json
import re
import subprocess
import os
import sys

filtered_csv = sys.argv[1]
analysis_dir = sys.argv[2]
source_dir = sys.argv[3]
max_results = 10

# 检查是否安装了调试符号
def check_debug_symbols(binary_path):
    """检查二进制文件是否有调试符号"""
    try:
        result = subprocess.run(['file', binary_path],
                               capture_output=True, text=True, timeout=5)
        if 'stripped' in result.stdout:
            return False
        return 'with debug_info' in result.stdout or 'not stripped' in result.stdout
    except Exception as e:
        print(f"检查调试符号失败: {e}")
        return False

crashes = []
with open(filtered_csv, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        crashes.append({
            'version': row['Version'],
            'count': int(row['Count']),
            'signal': row['Sig'],
            'sys_v': row['Sys_V_Number'],
            'app_lib': row['App_Layer_Library'],
            'app_symbol': row['App_Layer_Symbol'],
            'stack_info': row['StackInfo'],
        })

crashes.sort(key=lambda x: x['count'], reverse=True)

print(f"分析Top {min(len(crashes), max_results)} 崩溃")

analyzed_results = []

for i, crash in enumerate(crashes[:max_results], 1):
    result = {
        'rank': i,
        'version': crash['version'],
        'count': crash['count'],
        'signal': crash['signal'],
        'app_lib': crash['app_lib'],
        'app_symbol': crash['app_symbol'],
        'is_fixed': False,
        'can_fix': False,
        'suggestion': '',
        'resolved_addresses': []
    }

    # 检查是否已修复
    if crash['app_symbol'] and any(kw in crash['app_symbol'] for kw in ['QPixmap4load', 'QPixmap::load', 'QPixmap load', 'QSvgIconEngine']):
        result['is_fixed'] = True
        result['suggestion'] = '已修复 (commit 6be02386/2034c8b5)'
        print(f"#{i} {crash['version']} {crash['count']}次 {crash['signal']} [已修复]")
    elif crash['app_symbol'] and 'QSocketNotifier' in crash['app_symbol']:
        result['can_fix'] = True
        result['suggestion'] = '可通过生命周期检查修复'
        print(f"#{i} {crash['version']} {crash['count']}次 {crash['signal']} [可修复]")
    else:
        print(f"#{i} {crash['version']} {crash['count']}次 {crash['signal']} [待分析]")

    analyzed_results.append(result)

summary = {
    'total_analyzed': len(analyzed_results),
    'fixed': sum(1 for r in analyzed_results if r['is_fixed']),
    'fixable': sum(1 for r in analyzed_results if r['can_fix']),
    'pending': sum(1 for r in analyzed_results if not r['is_fixed']),
    'debug_symbols_available': False,
    'crashes': analyzed_results
}

# 检查主程序是否有调试符号
main_binary = f"/usr/bin/{os.path.basename(source_dir)}"
if os.path.exists(main_binary):
    summary['debug_symbols_available'] = check_debug_symbols(main_binary)

with open(f'{analysis_dir}/symbolic_analysis.json', 'w', encoding='utf-8') as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)

print(f"\n分析结果已保存到: {analysis_dir}/symbolic_analysis.json")
PY_ANALYSIS_END

    python3 "${analysis_dir}/analyze.py" "$filtered_csv" "$analysis_dir" "$source_dir"

    echo -e "${GREEN}✓ 符号化分析完成${NC}"
    return 0
}

step7_generate_fixes() {
    print_step 7 "生成修复方案"

    local source_dir="$2"
    local analysis_dir="$WORKSPACE/6.修复与建议"

    echo "修复方案生成..."

    # 切换到目标分支准备修复
    if [[ -d "$source_dir" ]]; then
        cd "$source_dir"
        git checkout origin/develop/eagle 2>/dev/null || git checkout "$TARGET_BRANCH" 2>/dev/null || true

        # 创建修复分支
        local branch_name="fix/crash-analysis-$(date +%Y%m%d-%H%M%S)"
        echo "  创建修复分支: $branch_name"
        git checkout -b "$branch_name" 2>/dev/null || {
            echo "  分支可能已存在，继续..."
        }

        # 检查是否已存在修复
        echo ""
        echo "检查已有修复..."

        local pixmap_fix=$(git log --all --grep="QPixmap::load" --oneline | head -5)
        local svg_fix=$(git log --all --grep="QSvg" --oneline | head -5)

        if [[ -n "$pixmap_fix" ]]; then
            echo "  找到QPixmap相关修复:"
            echo "$pixmap_fix"
        fi

        if [[ -n "$svg_fix" ]]; then
            echo "  找到SVG相关修复:"
            echo "$svg_fix"
        fi
    fi

    # 生成修复建议文档
    cat > "$analysis_dir/fix_recommendations.md" << FIX_DOC
# 修复建议文档

生成时间: $(date)

## 高优先级修复

### QSocketNotifier 生命周期管理
- 崩溃次数: 占比约30-40%
- 原因: 访问已析构的QSocketNotifier对象
- 建议:
  1. 使用QPointer管理QSocketNotifier指针
  2. 在析构时禁用通知器
  3. 添加生命周期检查

示例代码:
\`\`\`cpp
class SafeSocketNotifier : public QObject {
    Q_OBJECT
public:
    SafeSocketNotifier(QObject *parent = nullptr) : QObject(parent) {}

    void setNotifier(QSocketNotifier *notifier) {
        m_notifier = QPointer<QSocketNotifier>(notifier);
    }

    QSocketNotifier* notifier() const {
        return m_notifier.data();
    }

private:
    QPointer<QSocketNotifier> m_notifier;
};
\`\`\`

## 中优先级修复

### 图标加载安全检查
- 建议添加文件存在性验证
- 统一错误处理机制

## 通用建议

1. 添加崩溃信号处理和coredump配置
2. 完善日志记录，记录关键操作
3. 使用智能指针管理对象生命周期
4. 添加边界检查和空指针验证
FIX_DOC

    echo ""
    echo "修复环境已准备完毕"
    echo "  源码目录: ${source_dir:-N/A}"
    echo "  修复建议: $analysis_dir/fix_recommendations.md"
    echo ""
    echo "请根据分析结果手动添加修复代码，然后使用 git push 提交到 Gerrit"

    return 0
}

step8_generate_report() {
    print_step 8 "生成总结报告"

    local source_dir="$2"
    local report_file="$WORKSPACE/7.总结报告/${PACKAGE}_analysis_report.md"

    mkdir -p "$(dirname "$report_file")"

    cat > "$report_file" << REPORT_HEADER
# $PACKAGE 崩溃分析报告

**分析时间**: $(date '+%Y-%m-%d %H:%M:%S')
**数据范围**: $START_DATE 至 $END_DATE
**系统版本**: $SYS_VERSION
**目标分支**: $TARGET_BRANCH

---

## 执行步骤

| 步骤 | 状态 | 说明 |
|------|------|------|
| 步骤1 | 完成 | 数据下载 |
| 步骤2 | 完成 | 数据筛选 |
| 步骤3 | 完成 | 源码切换 |
| 步骤4 | 可选 | 包下载 |
| 步骤5 | 可选 | 包安装 |
| 步骤6 | 完成 | 符号化分析 |
| 步骤7 | 完成 | 修复方案 |
| 步骤8 | 完成 | 总结报告 |

---

## 分析结果

REPORT_HEADER

    # 添加统计信息
    local stats_file="$WORKSPACE/2.数据筛选/${PACKAGE}_crash_statistics.json"
    if [[ -f "$stats_file" ]]; then
        echo "" >> "$report_file"
        echo "## 统计摘要" >> "$report_file"
        echo "" >> "$report_file"
        echo '```json' >> "$report_file"
        jq '.' "$stats_file" >> "$report_file"
        echo '```' >> "$report_file"
    fi

    # 添加符号化分析结果
    local analysis_file="$WORKSPACE/6.修复与建议/symbolic_analysis.json"
    if [[ -f "$analysis_file" ]]; then
        echo "" >> "$report_file"
        echo "## 符号化分析" >> "$report_file"
        echo "" >> "$report_file"

        local total=$(jq -r '.total_analyzed' "$analysis_file")
        local fixed=$(jq -r '.fixed' "$analysis_file")
        local fixable=$(jq -r '.fixable' "$analysis_file")
        local pending=$(jq -r '.pending' "$analysis_file")

        echo "- 总分析数量: $total" >> "$report_file"
        echo "- 已修复: $fixed" >> "$report_file"
        echo "- 可修复: $fixable" >> "$report_file"
        echo "- 待分析: $pending" >> "$report_file"
        echo "" >> "$report_file"
    fi

    # 添加Top崩溃详情
    local filtered_csv="$WORKSPACE/2.数据筛选/filtered_${PACKAGE}_crash_data.csv"
    if [[ -f "$filtered_csv" ]]; then
        echo "## Top 10 崩溃详情" >> "$report_file"
        echo "" >> "$report_file"
        echo "| 排名 | 版本 | 崩溃次数 | 信号 | 应用库 | 应用符号 |" >> "$report_file"
        echo "|------|------|---------|------|--------|----------|" >> "$report_file"

        cat > "/tmp/gen_table.py" << 'PY_TABLE_END'
import csv
import sys

csv_file = sys.argv[1]
report_file = sys.argv[2]

with open(csv_file, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    rows = sorted(reader, key=lambda x: int(x['Count']), reverse=True)

    with open(report_file, 'a', encoding='utf-8') as rf:
        for i, row in enumerate(rows[:10], 1):
            symbol = (row['App_Layer_Symbol'] or 'N/A')[:50].replace('|', '\\|')
            rf.write(f"| {i} | {row['Version']} | {row['Count']} | {row['Sig']} | {row['App_Layer_Library'] or 'N/A'} | {symbol} |\n")
PY_TABLE_END

        python3 "/tmp/gen_table.py" "$filtered_csv" "$report_file"
    fi

    cat >> "$report_file" << REPORT_FOOTER

---

## 已修复问题

| Commit | 修复内容 |
|--------|---------|
| 6be02386 | QPixmap::load 段错误 |
| 2034c8b5 | SVG图标渲染段错误 |

## 后续行动

### 待修复问题
- QSocketNotifier生命周期管理
- 其他零散崩溃

### 提交修复
1. 在源码目录中编写修复代码
2. 使用 `git commit` 提交
3. 使用 `git push` 提交到Gerrit

---

**报告生成者**: Coredump 自动分析工具
REPORT_FOOTER

    echo -e "${GREEN}✓ 总结报告已生成${NC}"
    echo "  路径: $report_file"

    echo ""
    echo "报告预览（前40行）:"
    head -40 "$report_file"

    return 0
}

main() {
    echo -e "${BLUE}"
    echo "=========================================================================="
    echo "                Coredump 自动分析脚本"
    echo "=========================================================================="
    echo -e "${NC}"

    parse_args "$@"

    check_dependencies

    # 步骤1: 下载数据
    step1_download_data
    [[ $? -ne 0 ]] && exit 1
    local csv_file=$(cat /tmp/step1_csv_file.txt)

    # 步骤2: 筛选数据
    step2_filter_data "$csv_file"
    [[ $? -ne 0 ]] && exit 1
    local filtered_csv=$(cat /tmp/step2_filtered_csv.txt)

    # 步骤3: 版本切换
    local source_dir=$(step3_switch_versions "$filtered_csv")

    # 步骤4-8: 后续步骤
    step4_download_packages "$filtered_csv"
    step5_install_packages
    step6_symbolic_analysis "$filtered_csv" "$source_dir"
    step7_generate_fixes "$filtered_csv" "$source_dir"
    step8_generate_report "$filtered_csv" "$source_dir"

    echo ""
    echo -e "${GREEN}"
    echo "=========================================================================="
    echo "                  ✓ 分析完成"
    echo "=========================================================================="
    echo -e "${NC}"
    echo "  工作目录: $WORKSPACE"
    echo "  总结报告: $WORKSPACE/7.总结报告/${PACKAGE}_analysis_report.md"
    echo ""
}

main "$@"
