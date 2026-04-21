#!/bin/bash
#=============================================================================
# dde-launcher 崩溃分析自动化脚本
# 自动执行: 筛选数据 → 下载包 → 安装包 → 崩溃分析 → 生成报告
#=============================================================================

set -e

# 配色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 路径配置
WORKSPACE="/home/wubw/workspace"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.openclaw/skills/coredump-analysis-skills}"
PKG_DOWNLOAD_DIR="$WORKSPACE/4.包管理/下载包/downloads"
REPORT_FILE="$WORKSPACE/5.崩溃分析/dde-launcher_crash_analysis_report.md"
FILTERED_CSV="$WORKSPACE/2.数据筛选/filtered_dde-launcher_crash_data.csv"
STATS_JSON="$WORKSPACE/2.数据筛选/dde-launcher_crash_statistics.json"
PKG_DIR="$PKG_DOWNLOAD_DIR/dde-launcher"

SUDO_PASSWORD="${SUDO_PASSWORD:-1}"

echo ""
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}       dde-launcher 崩溃分析自动化流程${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo ""

#==============================================================================
# 步骤1: 数据筛选
#==============================================================================
echo -e "${CYAN}[步骤1] 数据筛选${NC}"

if [[ ! -f "$FILTERED_CSV" ]]; then
    echo "执行数据筛选..."
    python3 "$SKILLS_DIR/coredump-data-filter/scripts/filter_crash_data.py" \
        dde-launcher --workspace "$WORKSPACE"
else
    echo "筛选数据已存在，跳过"
fi

# 读取版本列表
echo "读取版本列表..."
VERSIONS=$(python3 -c "
import json
with open('${STATS_JSON}', 'r') as f:
    stats = json.load(f)
versions = []
for ver, data in stats.get('by_version', {}).items():
    versions.append((ver, data['total_crashes'], data['unique_crashes']))
versions.sort(key=lambda x: -x[1])
for v, c, u in versions:
    print(f'{v}:{c}:{u}')
")

echo "版本列表（按崩溃次数排序）:"
echo "$VERSIONS" | head -5
echo "..."
echo ""

#==============================================================================
# 步骤2: 下载并安装包
#==============================================================================
echo -e "${CYAN}[步骤2] 下载并安装包${NC}"

mkdir -p "$PKG_DIR"

# 尝试使用缓存的包
CACHED_VERSIONS=("5.6.15.1-1" "5.7.9.7-1" "5.7.16.1-1")
for cached_ver in "${CACHED_VERSIONS[@]}"; do
    cached_dir="$PKG_DOWNLOAD_DIR/${cached_ver}"
    if [[ -d "$cached_dir" ]]; then
        echo "复制缓存包 $cached_ver..."
        cp "$cached_dir"/*.deb "$PKG_DIR/" 2>/dev/null || true
    fi
done

# 显示可用包
echo ""
echo "可用包:"
ls -lh "$PKG_DIR"/*.deb 2>/dev/null || echo "无缓存包"
echo ""

#==============================================================================
# 步骤3: 分析每个版本
#==============================================================================
echo -e "${CYAN}[步骤3] 崩溃分析${NC}"

# 系统库列表
SYSTEM_LIBS_STR="libc.so.6|libpthread.so.0|libstdc++.so.6|ld-linux|libm.so.6|libQt5Core.so.5|libQt5Gui.so.5|libQt5Widgets.so.5|libQt5XdgIconLoader.so.3|libdtkiconproxy.so|libdsvgicon.so|libfontconfig.so.1|libpixman-1.so.0|libdl.so.2"

# 创建报告
cat > "$REPORT_FILE" << HEADER
# dde-launcher 崩溃分析报告

**分析时间**: $(date '+%Y-%m-%d %H:%M:%S')
**包名**: dde-launcher

## 统计摘要

HEADER

# 添加统计摘要
python3 -c "
import json
with open('${STATS_JSON}', 'r') as f:
    stats = json.load(f)
summary = stats.get('summary', {})
print(f\"- 原始记录数: {summary.get('total_records', 0)}\")
print(f\"- 唯一崩溃数: {summary.get('unique_crashes', 0)}\")
print(f\"- 版本数: {summary.get('versions_count', 0)}\")
" >> "$REPORT_FILE"

cat >> "$REPORT_FILE" << HEADER

## 版本崩溃详情

HEADER

total_app_layer=0
total_system=0
total_analyzed=0

# 分析每个版本
while IFS=: read -r VERSION CRASH_COUNT UNIQUE_CRASHES; do
    echo ""
    echo -e "${GREEN}分析版本: $VERSION ($CRASH_COUNT 次崩溃)${NC}"

    # 提取该版本的崩溃
    VERSION_ANALYSIS=$(python3 -c "
import csv
import sys

crashes = []
with open('${FILTERED_CSV}', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        if row['Version'] == '${VERSION}':
            crashes.append(row)

system_libs = ['libc.so.6', 'libpthread.so.0', 'libstdc++.so.6', 'ld-linux',
               'libm.so.6', 'libQt5Core.so.5', 'libQt5Gui.so.5', 'libQt5Widgets.so.5',
               'libQt5XdgIconLoader.so.3', 'libdtkiconproxy.so', 'libdsvgicon.so',
               'libfontconfig.so.1', 'libpixman-1.so.0', 'libdl.so.2']

app_layer = []
system = []
for c in crashes:
    lib = c.get('App_Layer_Library', '')
    is_sys = any(sl in lib for sl in system_libs)
    if is_sys:
        system.append(c)
    else:
        app_layer.append(c)

print(f'APP_COUNT:{len(app_layer)}')
print(f'SYS_COUNT:{len(system)}')

for c in app_layer[:10]:
    sig = c.get('Sig', '')
    symbol = c.get('App_Layer_Symbol', '')
    lib = c.get('App_Layer_Library', '')
    count = c.get('Count', '1')
    stack = c.get('StackInfo', '')[:300].replace('\n', ' ').replace('|', '/')
    print(f'CRASH|{sig}|{symbol}|{lib}|{count}|{stack}')
")

    APP_COUNT=$(echo "$VERSION_ANALYSIS" | grep "^APP_COUNT:" | cut -d: -f2)
    SYS_COUNT=$(echo "$VERSION_ANALYSIS" | grep "^SYS_COUNT:" | cut -d: -f2)

    if [[ -z "$APP_COUNT" ]]; then APP_COUNT=0; fi
    if [[ -z "$SYS_COUNT" ]]; then SYS_COUNT=0; fi

    total_app_layer=$((total_app_layer + APP_COUNT))
    total_system=$((total_system + SYS_COUNT))
    total_analyzed=$((total_analyzed + 1))

    echo "  应用层崩溃: $APP_COUNT"
    echo "  系统库崩溃: $SYS_COUNT"

    # 添加到报告
    echo "" >> "$REPORT_FILE"
    echo "### 版本: $VERSION ($CRASH_COUNT 次崩溃, $UNIQUE_CRASHES 唯一崩溃)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "- 应用层崩溃: $APP_COUNT" >> "$REPORT_FILE"
    echo "- 系统库崩溃: $SYS_COUNT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # 详细崩溃信息
    CRASH_DETAILS=$(echo "$VERSION_ANALYSIS" | grep "^CRASH|")
    if [[ -n "$CRASH_DETAILS" ]]; then
        echo "**应用层崩溃详情**:" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        while IFS='|' read -r sig symbol lib count stack; do
            if [[ -n "$symbol" && ! "$symbol" =~ ^APP_COUNT && ! "$symbol" =~ ^SYS_COUNT ]]; then
                # 简化符号名
                symbol_short=$(echo "$symbol" | cut -c1-80)
                echo "- **[$sig]** \`$symbol_short\`" >> "$REPORT_FILE"
                echo "  - 库: \`$lib\`" >> "$REPORT_FILE"
                echo "  - 次数: $count" >> "$REPORT_FILE"
            fi
        done <<< "$CRASH_DETAILS"
        echo "" >> "$REPORT_FILE"
    fi

done <<< "$VERSIONS"

#==============================================================================
# 完成报告
#==============================================================================
cat >> "$REPORT_FILE" << EOF

---

## 汇总

- 分析版本数: $total_analyzed
- 应用层崩溃总数: $total_app_layer
- 系统库崩溃总数: $total_system

EOF

echo ""
echo -e "${GREEN}=============================================================================${NC}"
echo -e "${GREEN}分析完成！${NC}"
echo -e "${GREEN}=============================================================================${NC}"
echo ""
echo "报告文件: $REPORT_FILE"
echo "分析版本: $total_analyzed"
echo "应用层崩溃: $total_app_layer"
echo "系统库崩溃: $total_system"
echo ""