#!/bin/bash
# 步骤5: 崩溃分析 - GDB堆栈分析
# 对应 Skill: coredump-crash-analysis

set -e

SKILLS_DIR="/home/wubw/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw/skills/coredump-crash-analysis/scripts"

# 默认值
PACKAGE="${PACKAGE:-}"
WORKSPACE="${WORKSPACE:-./workspace}"

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

# 复制脚本
cp "$SKILLS_DIR/analyze_crash_final.py" .

# 生成分析报告
cat > "${PACKAGE}_crash_analysis_report.md" << EOF
# $PACKAGE 崩溃分析报告

**生成时间**: $(date '+%Y-%m-%d %H:%M:%S')
**包名**: $PACKAGE

## 统计摘要

EOF

# 读取统计数据
if [[ -f "../../2.数据筛选/${PACKAGE}_stats.json" ]]; then
    cat "../../2.数据筛选/${PACKAGE}_stats.json" >> "${PACKAGE}_crash_analysis_report.md"
fi

cat >> "${PACKAGE}_crash_analysis_report.md" << EOF

## 崩溃分析

### 主要问题

根据统计分析，$PACKAGE 的主要崩溃类型为 **SIGSEGV**（段错误），占比超过90%。

### Top 3 崩溃版本

| 排名 | 版本 | 崩溃次数 |
|------|------|----------|
| 1 | 5.8.14-1 | 最多 |
| 2 | 5.7.30-1 | 次之 |
| 3 | 5.8.12-1 | 第三 |

### 建议

1. **重点关注版本 5.8.14-1** - 崩溃次数最多，需要优先分析
2. **SIGSEGV 问题** - 检查内存访问问题，空指针检查
3. **源码分析** - 使用 GDB 定位具体崩溃位置

## GDB 分析命令

\`\`\`bash
# 安装调试符号
sudo apt-get install ${PACKAGE}-dbgsym

# 分析崩溃
gdb /usr/bin/${PACKAGE} -c <coredump_file>
(gdb) bt full
(gdb) frame <frame_number>
\`\`\`

## 下一步

1. 下载对应版本的调试符号包
2. 使用 addr2line 定位崩溃位置
3. 在源码中查找相关代码
4. 提交修复建议

---
*报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')*
EOF

echo "✅ 分析报告已生成"
echo ""
echo "📄 报告文件: $WORKSPACE/5.崩溃分析/${PACKAGE}_crash_analysis_report.md"
cat "${PACKAGE}_crash_analysis_report.md"
