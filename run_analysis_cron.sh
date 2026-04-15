#!/bin/bash
#=============================================================================
# 崩溃分析定时任务脚本
# 每2小时执行一次 dde-session-ui 全量分析
# 将最终结论报告保存到 ~/Desktop
#=============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$HOME/coredump-workspace"
DESKTOP_DIR="$HOME/Desktop"
REPORT_DIR="$WORKSPACE/7.总结报告"

# 日志文件
LOG_FILE="$WORKSPACE/cron_analysis_$(date +%Y%m%d_%H%M%S).log"

# 执行时间
EXEC_TIME=$(date "+%Y-%m-%d %H:%M:%S")

echo "========================================" | tee -a "$LOG_FILE"
echo "崩溃分析定时任务开始: $EXEC_TIME" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# 1. 清理旧的工作空间数据（保留代码目录）
echo "[1/5] 清理工作空间..." | tee -a "$LOG_FILE"
if [[ -d "$WORKSPACE" ]]; then
    # 删除崩溃数据、下载包、旧的分析结果
    rm -rf "$WORKSPACE/1.数据下载" 2>/dev/null || true
    rm -rf "$WORKSPACE/2.数据筛选" 2>/dev/null || true
    rm -rf "$WORKSPACE/4.包管理/downloads" 2>/dev/null || true
    rm -rf "$WORKSPACE/5.崩溃分析" 2>/dev/null || true
    rm -rf "$WORKSPACE/7.总结报告" 2>/dev/null || true
fi

# 2. 创建工作目录
mkdir -p "$WORKSPACE"

# 3. 执行全量分析
echo "[2/5] 执行崩溃分析..." | tee -a "$LOG_FILE"
cd "$SCRIPT_DIR"

# 计算日期范围（过去7天）
END_DATE=$(date +%Y-%m-%d)
START_DATE=$(date +%Y-%m-%d -d "7 days ago")

bash run_analysis_agent.sh \
    --package dde-session-ui \
    --start-date "$START_DATE" \
    --end-date "$END_DATE" \
    --sys-version 1070-1075 \
    --arch x86 \
    --workspace "$WORKSPACE" 2>&1 | tee -a "$LOG_FILE" || true

# 4. 复制报告到桌面
echo "[3/5] 复制报告到桌面..." | tee -a "$LOG_FILE"
if [[ -d "$REPORT_DIR" ]]; then
    # 查找最新的报告文件
    FINAL_REPORT=$(find "$REPORT_DIR" -name "*.md" -o -name "*.json" 2>/dev/null | head -5)

    if [[ -n "$FINAL_REPORT" ]]; then
        # 创建带时间戳的报告目录
        TIMESTAMP_DIR="$DESKTOP_DIR/dde-session-ui-analysis-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$TIMESTAMP_DIR"

        # 复制所有报告文件
        cp -r "$REPORT_DIR"/* "$TIMESTAMP_DIR/" 2>/dev/null || true

        # 复制日志
        cp "$LOG_FILE" "$TIMESTAMP_DIR/"

        echo "✅ 报告已保存到: $TIMESTAMP_DIR" | tee -a "$LOG_FILE"
    else
        echo "⚠️ 未找到报告文件" | tee -a "$LOG_FILE"
    fi
else
    echo "⚠️ 报告目录不存在: $REPORT_DIR" | tee -a "$LOG_FILE"
fi

# 5. 完成
END_TIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "[4/5] 完成时间: $END_TIME" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "定时任务执行完成" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
