#!/bin/bash
# 步骤2: 数据筛选/去重 - 保留完整信息
# 对应 Skill: coredump-data-filter

set -e

# 默认值
PACKAGE=""
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

echo "=========================================="
echo "步骤2: 数据筛选/去重 - 保留完整堆栈信息"
echo "=========================================="
echo "包名: $PACKAGE"
echo "工作目录: $WORKSPACE"

# 创建目录
mkdir -p "$WORKSPACE/2.数据筛选"

# 查找最新的CSV文件（搜索所有下载目录）
DOWNLOAD_BASE="$WORKSPACE/1.数据下载"
CSV_FILE=$(find "$DOWNLOAD_BASE" -name "${PACKAGE}_*_crash_*.csv" -type f 2>/dev/null | sort -r | head -1)

if [[ -z "$CSV_FILE" || ! -f "$CSV_FILE" ]]; then
    echo "错误: 未找到CSV文件 for $PACKAGE"
    echo "搜索路径: $DOWNLOAD_BASE/"
    ls "$DOWNLOAD_BASE/" | head -10
    exit 1
fi

echo "使用CSV文件: $CSV_FILE"

cd "$WORKSPACE/2.数据筛选"

# 使用Python进行完整去重，保留所有字段
python3 << PYEOF
import csv
import json
import re
import os
from collections import defaultdict

csv_file = "$CSV_FILE"
package = "$PACKAGE"

print(f"读取文件: {csv_file}")

records = []
with open(csv_file, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        records.append(row)

print(f"总记录数: {len(records)}")

if len(records) == 0:
    print("警告: CSV文件为空，跳过分析")
    with open(f"filtered_{package}_crash_data.csv", 'w') as f:
        pass
    stats = {
        "summary": {"total_records": 0, "unique_crashes": 0, "duplicate_count": 0, "versions_count": 0},
        "by_version": {}, "by_signal": {}, "top_crashes": []
    }
    with open(f"{package}_crash_statistics.json", 'w') as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)
else:
    # 提取堆栈签名（用于去重）
    def extract_stack_signature(stack_info):
        if not stack_info:
            return ""
        frames = []
        lines = stack_info.strip().split('\n')
        for line in lines[:10]:  # 取前10帧
            match = re.match(r'\s*#\d+\s+0x[0-9a-f]+\s+(\S+|n/a)\s+\(([^)]+)\)', line)
            if match:
                symbol = match.group(1)
                library = match.group(2)
                frames.append(f"{library}:{symbol}")
        return '|'.join(frames)

    # 去重分组
    crash_groups = defaultdict(list)

    for r in records:
        sig = r.get('Sig', '')
        exe = r.get('Exe', '')
        version = r.get('Version', '')
        stack_sig = extract_stack_signature(r.get('StackInfo', ''))
        
        # 用 Exe+Sig+Version+StackSignature 作为去重key
        key = f"{exe}|{sig}|{version}|{stack_sig}"
        crash_groups[key].append(r)

    print(f"去重后唯一崩溃数: {len(crash_groups)}")

    # 保存去重后的CSV（保留完整信息）
    output_csv = f"filtered_{package}_crash_data.csv"
    # 包含原始字段 + Count + UniqueKey
    extra_fields = ['Count', 'UniqueKey']
    all_fields = list(records[0].keys()) + [f for f in extra_fields if f not in records[0].keys()]
    with open(output_csv, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=all_fields, extrasaction='ignore')
        writer.writeheader()
        
        # 按崩溃次数排序
        sorted_groups = sorted(crash_groups.items(), key=lambda x: -len(x[1]))
        
        for key, group in sorted_groups:
            # 取第一条记录，添加Count字段
            record = group[0].copy()
            record['Count'] = len(group)
            record['UniqueKey'] = key
            writer.writerow(record)

    print(f"已保存去重数据: {output_csv}")

    # 统计
    versions = defaultdict(int)
    signals = defaultdict(int)
    total_count = len(records)
    unique_count = len(crash_groups)

    for r in records:
        versions[r.get('Version', 'unknown')] += 1
        signals[r.get('Sig', 'unknown')] += 1

    # 保存统计报告
    stats = {
        "summary": {
            "total_records": total_count,
            "unique_crashes": unique_count,
            "duplicate_count": total_count - unique_count,
            "versions_count": len(versions)
        },
        "by_version": dict(sorted(versions.items(), key=lambda x: -x[1])),
        "by_signal": dict(sorted(signals.items(), key=lambda x: -x[1])),
        "top_crashes": []
    }

    # Top 10崩溃
    sorted_groups = sorted(crash_groups.items(), key=lambda x: -len(x[1]))
    for i, (key, group) in enumerate(sorted_groups[:10], 1):
        r = group[0]
        stats["top_crashes"].append({
            "rank": i,
            "count": len(group),
            "signal": r.get('Sig', ''),
            "version": r.get('Version', ''),
            "exe": r.get('Exe', '')
        })

    stats_file = f"{package}_crash_statistics.json"
    with open(stats_file, 'w', encoding='utf-8') as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)

    print(f"已保存统计报告: {stats_file}")
    print(f"\n统计摘要:")
    print(f"  总记录数: {total_count}")
    print(f"  唯一崩溃数: {unique_count}")
    print(f"  重复记录数: {total_count - unique_count}")
    print(f"\n版本分布 Top 5:")
    for v, c in sorted(versions.items(), key=lambda x: -x[1])[:5]:
        print(f"  {v}: {c}次")
    print(f"\n信号分布:")
    for s, c in sorted(signals.items(), key=lambda x: -x[1]):
        print(f"  {s}: {c}次")

PYEOF

echo ""
echo "✅ 步骤2完成"
ls -la filtered_*_crash_data.csv *_statistics.json 2>/dev/null || true
