#!/bin/bash
# 步骤2: 数据筛选/去重 - 保留完整信息
# 对应 Skill: coredump-data-filter

set -e

WORKSPACE="${WORKSPACE:-/home/wubw/Desktop/test}"
PACKAGE="${1:-dde-session-ui}"

echo "=========================================="
echo "步骤2: 数据筛选/去重 - 保留完整堆栈信息"
echo "=========================================="

cd "$WORKSPACE/2.数据筛选"

# 使用Python进行完整去重，保留所有字段
python3 << EOF
import csv
import json
import re
from collections import defaultdict

csv_file = "../1.数据下载/download_20260408-1416/dde-session-ui_X86_crash_20260408-1416.csv"

print(f"读取文件: {csv_file}")

records = []
with open(csv_file, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        records.append(row)

print(f"总记录数: {len(records)}")

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
output_csv = "filtered_${PACKAGE}_crash_data.csv"
with open(output_csv, 'w', encoding='utf-8', newline='') as f:
    fieldnames = list(records[0].keys())
    writer = csv.DictWriter(f, fieldnames=fieldnames)
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
for i, (key, group) in enumerate(sorted_groups[:10], 1):
    r = group[0]
    stats["top_crashes"].append({
        "rank": i,
        "count": len(group),
        "signal": r.get('Sig', ''),
        "version": r.get('Version', ''),
        "exe": r.get('Exe', '')
    })

stats_file = f"{PACKAGE}_crash_statistics.json"
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
EOF

echo ""
echo "✅ 步骤2完成"
ls -la filtered_*_crash_data.csv *_statistics.json
