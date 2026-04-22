#!/bin/bash
# 步骤5: 崩溃分析 - GDB堆栈分析
# 对应 Skill: coredump-crash-analysis

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/../../coredump-crash-analysis/scripts"

# 默认值
PACKAGE="${PACKAGE:-}"
if [[ -z "$WORKSPACE" ]]; then WORKSPACE="$HOME/coredump-workspace-$(date +%Y%m%d-%H%M%S)"; fi

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --package) PACKAGE="$2"; shift 2 ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "$PACKAGE" ]]; then
    echo "错误: 必须指定 --package 参数"
    exit 1
fi

# 创建目录
mkdir -p "$WORKSPACE/5.崩溃分析"

echo "=========================================="
echo "步骤5: 崩溃分析 - GDB堆栈分析"
echo "=========================================="
echo "包名: $PACKAGE"
echo ""

cd "$WORKSPACE/5.崩溃分析"

# 复制分析脚本
if [[ -f "$SKILLS_DIR/analyze_crash_final.py" ]]; then
    cp "$SKILLS_DIR/analyze_crash_final.py" .
else
    echo "⚠️ 找不到分析脚本: $SKILLS_DIR/analyze_crash_final.py"
fi

if [[ -f "$SKILLS_DIR/analyze_blackwidget_crashes.py" ]]; then
    cp "$SKILLS_DIR/analyze_blackwidget_crashes.py" .
else
    echo "⚠️ 找不到 dde-blackwidget 专项分析脚本: $SKILLS_DIR/analyze_blackwidget_crashes.py"
fi

# 读取统计数据
STATS_FILE="../2.数据筛选/${PACKAGE}_crash_statistics.json"
STATS_CONTENT=""
if [[ -f "$STATS_FILE" ]]; then
    STATS_CONTENT=$(cat "$STATS_FILE")
fi

# 读取过滤后的崩溃数据
FILTERED_CSV="../2.数据筛选/filtered_${PACKAGE}_crash_data.csv"

# 生成分析报告
cat > "${PACKAGE}_crash_analysis_report.md" << EOF
# $PACKAGE 崩溃分析报告

**生成时间**: $(date '+%Y-%m-%d %H:%M:%S')
**包名**: $PACKAGE

## 统计摘要

EOF

if [[ -n "$STATS_CONTENT" ]]; then
    echo "$STATS_CONTENT" >> "${PACKAGE}_crash_analysis_report.md"
else
    echo '{ "error": "未找到统计数据" }' >> "${PACKAGE}_crash_analysis_report.md"
fi

cat >> "${PACKAGE}_crash_analysis_report.md" << 'EOF'

## 崩溃分析详情

EOF

# 提取Top崩溃详情
if [[ -f "$FILTERED_CSV" ]]; then
    python3 - "$FILTERED_CSV" "$PACKAGE" << 'PYEOF'
import csv
import sys

csv_file = sys.argv[1]
package = sys.argv[2]

try:
    crashes = []
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            if i >= 20:
                break
            crashes.append(row)
    
    if crashes:
        md = "### Top 20 崩溃记录\n\n"
        md += "| 排名 | 次数 | 信号 | 版本 | 可执行文件 |\n"
        md += "|------|------|------|------|------------|\n"
        for i, r in enumerate(crashes, 1):
            count = r.get('Count', 1)
            sig = r.get('Sig', 'N/A')[:30]
            version = r.get('Version', 'N/A')[:20]
            exe = r.get('Exe', 'N/A')[:30]
            md += f"| {i} | {count} | {sig} | {version} | {exe} |\n"
        
        # 堆栈信息
        md += "\n### 堆栈信息示例\n\n"
        md += "```\n"
        for i, r in enumerate(crashes[:5], 1):
            stack = r.get('StackInfo', '无堆栈信息')[:500]
            md += f"\n--- 崩溃 #{i} (Count: {r.get('Count',1)}) ---\n"
            md += f"信号: {r.get('Sig','N/A')}\n"
            md += f"版本: {r.get('Version','N/A')}\n"
            md += f"堆栈:\n{stack}\n"
        md += "```\n"
        
        print(md)
except Exception as e:
    print(f"\n\n*无法解析崩溃数据: {e}*\n")
PYEOF
fi >> "${PACKAGE}_crash_analysis_report.md"

cat >> "${PACKAGE}_crash_analysis_report.md" << EOF

## 修复建议

基于以上分析，对 $PACKAGE 的修复建议：

### 高优先级（崩溃次数最多）
EOF

# 根据统计数据生成具体建议
python3 - "$PACKAGE" "$STATS_FILE" "$FILTERED_CSV" 2>/dev/null << 'PYEOF'
import json
import sys
import csv

package = sys.argv[1]
stats_file = sys.argv[2]
filtered_csv = sys.argv[3] if len(sys.argv) > 3 else None

recommendations = []

try:
    with open(stats_file) as f:
        stats = json.load(f)
    
    top_signals = list(stats.get('by_signal', {}).items())[:3]
    top_versions = list(stats.get('by_version', {}).items())[:3]
    
    recommendations.append(f"### 1. 信号类型分析")
    for sig, count in top_signals:
        if 'SEGV' in sig:
            recommendations.append(f"   - **{sig}** ({count}次): 段错误，可能因空指针解引用、内存越界访问、释放后使用等导致。需检查相关指针和数组边界。")
        elif 'ABRT' in sig:
            recommendations.append(f"   - **{sig}** ({count}次): 程序异常终止，通常由assert失败、double-free或严重逻辑错误触发。")
        elif 'BUS' in sig:
            recommendations.append(f"   - **{sig}** ({count}次): 总线错误，通常由未对齐内存访问或访问不存在内存页面导致。")
        else:
            recommendations.append(f"   - **{sig}** ({count}次): 需进一步分析。")
    
    recommendations.append(f"\n### 2. 版本分布")
    for ver, count in top_versions:
        recommendations.append(f"   - 版本 {ver}: {count}次崩溃")
    
    recommendations.append(f"\n### 3. 通用修复方向")
    recommendations.append("   - 使用 GDB/addr2line 定位具体崩溃文件和行号")
    recommendations.append("   - 检查空指针解引用（特别是信号处理函数中）")
    recommendations.append("   - 检查内存分配/释放配对是否正确")
    recommendations.append("   - 检查多线程竞态条件（如果有）")
    recommendations.append("   - 检查数组/容器边界访问")

except Exception as e:
    recommendations.append(f"\n*无法生成建议: {e}*")

print('\n'.join(recommendations))
PYEOF

cat >> "${PACKAGE}_crash_analysis_report.md" << 'EOF'

### 下一步

1. 使用 addr2line 定位崩溃的具体文件和行号
2. 在源码中查找相关代码
3. 分析崩溃原因并编写修复代码
4. 提交到 develop/eagle 分支

---
*报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')*
EOF

echo "✅ 分析报告已生成"
echo ""
echo "📄 报告文件: $WORKSPACE/5.崩溃分析/${PACKAGE}_crash_analysis_report.md"

if [[ "$PACKAGE" == "dde-session-ui" ]] && [[ -f "analyze_blackwidget_crashes.py" ]]; then
    echo ""
    echo "=========================================="
    echo "附加分析: dde-blackwidget 专项分析"
    echo "=========================================="

    BLACKWIDGET_OUTPUT_DIR="$WORKSPACE/5.崩溃分析/dde-blackwidget专项分析"
    mkdir -p "$BLACKWIDGET_OUTPUT_DIR"

    SOURCE_CSV=""
    RAW_CSV_COUNT=$(find "$WORKSPACE/1.数据下载" -name "${PACKAGE}_*crash_*.csv" -type f 2>/dev/null | wc -l)
    if [[ "$RAW_CSV_COUNT" -gt 0 ]]; then
        SOURCE_CSV="$WORKSPACE/1.数据下载"
    elif [[ -f "$FILTERED_CSV" ]]; then
        SOURCE_CSV="$FILTERED_CSV"
    fi

    if [[ -n "$SOURCE_CSV" ]] && [[ -e "$SOURCE_CSV" ]]; then
        echo "使用数据源: $SOURCE_CSV"
        python3 ./analyze_blackwidget_crashes.py \
            --csv "$SOURCE_CSV" \
            --output-dir "$BLACKWIDGET_OUTPUT_DIR"
        echo ""
        echo "📄 dde-blackwidget 专项分析目录: $BLACKWIDGET_OUTPUT_DIR"
    else
        echo "⚠️ 未找到可用的 dde-session-ui 崩溃 CSV，跳过 dde-blackwidget 专项分析"
    fi
fi
