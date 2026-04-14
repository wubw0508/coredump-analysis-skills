#!/bin/bash
#=============================================================================
# dde-launcher 崩溃分析完整自动化脚本
#=============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

WORKSPACE="/home/wubw/workspace"
PKG_DIR="$WORKSPACE/4.包管理/下载包/downloads/dde-launcher"
CODE_DIR="$WORKSPACE/3.代码管理/dde-launcher"
FILTERED_CSV="$WORKSPACE/2.数据筛选/filtered_dde-launcher_crash_data.csv"
STATS_JSON="$WORKSPACE/2.数据筛选/dde-launcher_crash_statistics.json"
REPORT_FILE="$WORKSPACE/5.崩溃分析/dde-launcher_crash_analysis_report.md"
SUDO_PASSWORD="${SUDO_PASSWORD:-1}"

echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}       dde-launcher 崩溃分析完整自动化流程${NC}"
echo -e "${BLUE}=============================================================================${NC}"

# 步骤1: 检查代码仓库
echo -e "${CYAN}[步骤1] 检查代码仓库${NC}"
if [[ ! -d "$CODE_DIR/.git" ]]; then
    echo "克隆代码..."
    git clone -b origin/develop/eagle ssh://wubw@gerrit.uniontech.com:29418/dde-launcher "$CODE_DIR"
else
    cd "$CODE_DIR" && git fetch --tags origin 2>/dev/null || true
    echo "代码仓库就绪"
fi

# 步骤2: 读取版本列表
echo -e "${CYAN}[步骤2] 读取版本列表${NC}"
python3 -c "
import json
with open('${STATS_JSON}', 'r') as f:
    stats = json.load(f)
for ver, data in sorted(stats.get('by_version', {}).items(), key=lambda x: -x[1]['total_crashes']):
    print(f'{ver}:{data[\"total_crashes\"]}:{data[\"unique_crashes\"]}')
" > /tmp/versions.txt

cat /tmp/versions.txt | head -5
echo "..."

# 步骤3: 下载缺失的包
echo -e "${CYAN}[步骤3] 下载缺失的包${NC}"
cd "$PKG_DIR"

python3 -c "
import json
with open('${STATS_JSON}', 'r') as f:
    stats = json.load(f)
versions_needed = set(stats.get('by_version', {}).keys())
print('\n'.join(sorted(versions_needed)))
" > /tmp/need_versions.txt

for version in $(cat /tmp/need_versions.txt); do
    if [[ -f "dde-launcher_${version}_amd64.deb" ]] && [[ -s "dde-launcher_${version}_amd64.deb" ]]; then
        continue
    fi
    echo -n "下载 dde-launcher=$version ... "
    if apt download dde-launcher=$version 2>/dev/null; then
        echo "成功"
        apt download dde-launcher-dbgsym=$version 2>/dev/null && echo "  +dbgsym成功" || echo "  +dbgsym失败"
    else
        echo "失败(apt无此版本)"
    fi
done

# 步骤4: 生成报告
echo -e "${CYAN}[步骤4] 生成崩溃分析报告${NC}"

cat > "$REPORT_FILE" << HEADER
# dde-launcher 崩溃分析报告

**分析时间**: $(date '+%Y-%m-%d %H:%M:%S')
**包名**: dde-launcher

## 统计摘要

HEADER

python3 -c "
import json
with open('${STATS_JSON}', 'r') as f:
    stats = json.load(f)
s = stats.get('summary', {})
print(f'- 原始记录数: {s.get(\"total_records\", 0)}')
print(f'- 唯一崩溃数: {s.get(\"unique_crashes\", 0)}')
print(f'- 版本数: {s.get(\"versions_count\", 0)}')
" >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "## 版本崩溃详情" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

total_app=0
total_sys=0
analyzed=0

# 步骤5: 遍历版本进行分析
while IFS=: read -r VERSION CRASH_COUNT UNIQUE; do
    echo ""
    echo -e "${GREEN}分析版本: $VERSION ($CRASH_COUNT 次崩溃)${NC}"

    # 5.1 切换代码分支
    echo -e "${CYAN}  [5.1] 切换代码${NC}"
    cd "$CODE_DIR"
    VERSION_CLEAN=$(echo "$VERSION" | sed 's/-1$//' | sed 's/+.*$//')
    CHECKOUT_TAG=""
    if git tag | grep -q "^${VERSION_CLEAN}$"; then
        CHECKOUT_TAG="$VERSION_CLEAN"
    else
        CHECKOUT_TAG=$(git tag | grep "^${VERSION_CLEAN}" | head -1 || true)
    fi
    if [[ -n "$CHECKOUT_TAG" ]]; then
        git checkout "$CHECKOUT_TAG" 2>/dev/null || true
    fi
    CURRENT_BRANCH=$(git branch 2>/dev/null | grep '^\*' | cut -d' ' -f2 || echo "N/A")
    echo "  分支: $CURRENT_BRANCH"

    # 5.2 安装包
    echo -e "${CYAN}  [5.2] 安装包${NC}"
    cd "$PKG_DIR"
    if [[ -f "dde-launcher_${VERSION}_amd64.deb" ]]; then
        echo "$SUDO_PASSWORD" | sudo -S dpkg -i "dde-launcher_${VERSION}_amd64.deb" 2>/dev/null || true
        if [[ -f "dde-launcher-dbgsym_${VERSION}_amd64.deb" ]]; then
            echo "$SUDO_PASSWORD" | sudo -S dpkg -i "dde-launcher-dbgsym_${VERSION}_amd64.deb" 2>/dev/null || true
        fi
    fi

    # 5.3 分析崩溃
    echo -e "${CYAN}  [5.3] 分析崩溃${NC}"
    ANALYSIS=$(python3 -c "
import csv
SYSTEM_LIBS = ['libc.so.6', 'libpthread.so.0', 'libstdc++.so.6', 'ld-linux',
               'libm.so.6', 'libQt5Core.so.5', 'libQt5Gui.so.5', 'libQt5Widgets.so.5',
               'libQt5XdgIconLoader.so.3', 'libdtkiconproxy.so', 'libdsvgicon.so',
               'libfontconfig.so.1', 'libpixman-1.so.0', 'libdl.so.2',
               'libdbus-1.so.3', 'libwayland-client.so.0', 'libQt5DBus.so.5']
crashes = []
with open('${FILTERED_CSV}', 'r') as f:
    for row in csv.DictReader(f):
        if row['Version'] == '${VERSION}':
            crashes.append(row)
app = [c for c in crashes if not any(sl in c.get('App_Layer_Library', '') for sl in SYSTEM_LIBS)]
sys = [c for c in crashes if any(sl in c.get('App_Layer_Library', '') for sl in SYSTEM_LIBS)]
print(f'APP:{len(app)}')
print(f'SYS:{len(sys)}')
for c in app[:5]:
    print(f\"CRASH|{c.get('Sig','')}|{c.get('App_Layer_Symbol','')[:60]}|{c.get('App_Layer_Library','')}|{c.get('Count',1)}\")
")

    APP_COUNT=$(echo "$ANALYSIS" | grep "^APP:" | cut -d: -f2)
    SYS_COUNT=$(echo "$ANALYSIS" | grep "^SYS:" | cut -d: -f2)
    [[ -z "$APP_COUNT" ]] && APP_COUNT=0
    [[ -z "$SYS_COUNT" ]] && SYS_COUNT=0
    total_app=$((total_app + APP_COUNT))
    total_sys=$((total_sys + SYS_COUNT))
    analyzed=$((analyzed + 1))

    echo "  应用层:$APP_COUNT 系统库:$SYS_COUNT"

    # 5.4 写入报告
    echo "" >> "$REPORT_FILE"
    echo "### 版本: $VERSION ($CRASH_COUNT 次崩溃)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "- Git分支: $CURRENT_BRANCH" >> "$REPORT_FILE"
    echo "- 应用层崩溃: $APP_COUNT" >> "$REPORT_FILE"
    echo "- 系统库崩溃: $SYS_COUNT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    if [[ "$APP_COUNT" -gt 0 ]]; then
        echo "| 信号 | 符号 | 库 | 次数 |" >> "$REPORT_FILE"
        echo "|------|-----|-----|------|" >> "$REPORT_FILE"
        echo "$ANALYSIS" | grep "^CRASH|" | while IFS='|' read -r sig symbol lib count; do
            if [[ -n "$symbol" && ! "$symbol" =~ ^APP && ! "$symbol" =~ ^SYS ]]; then
                echo "| $sig | \`$symbol\` | $lib | $count |" >> "$REPORT_FILE"
            fi
        done
        echo "" >> "$REPORT_FILE"
    fi

done < /tmp/versions.txt

# 完成报告
echo "" >> "$REPORT_FILE"
echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "## 汇总" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "- 分析版本数: $analyzed" >> "$REPORT_FILE"
echo "- 应用层崩溃总数: $total_app" >> "$REPORT_FILE"
echo "- 系统库崩溃总数: $total_sys" >> "$REPORT_FILE"

echo ""
echo -e "${GREEN}=============================================================================${NC}"
echo -e "${GREEN}分析完成！${NC}"
echo "报告: $REPORT_FILE"
echo "分析版本: $analyzed"
echo "应用层崩溃: $total_app"
echo "系统库崩溃: $total_sys"