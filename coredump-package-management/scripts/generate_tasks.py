#!/usr/bin/env python3
"""
从崩溃数据生成下载任务
"""

import csv
import json
import argparse
import os
from pathlib import Path
from datetime import datetime

def generate_workspace_with_timestamp():
    """生成带时间戳的workspace路径"""
    for env_name in ("COREDUMP_WORKSPACE", "WORKSPACE"):
        workspace = os.environ.get(env_name)
        if workspace:
            return os.path.expanduser(workspace)
    return os.path.expanduser(f"~/coredump-workspace-{datetime.now().strftime('%Y%m%d-%H%M%S')}")

DEFAULT_WORKSPACE = generate_workspace_with_timestamp()

def generate_tasks(crash_data_path, output_dir):
    """从崩溃数据生成下载任务"""
    task_map = {}

    print(f"读取崩溃数据: {crash_data_path}")

    with open(crash_data_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            package = row.get('Package', '').strip()
            if not package or package == 'n/a':
                continue

            version = row.get('Version', '').strip()
            exe = row.get('Exe', '').strip()
            stack_info = row.get('StackInfo', '').strip()
            count = int(row.get('Count', 1))

            # 清理版本号
            if ':' in version:
                version = version.split(':')[-1]
            if version.endswith('-1'):
                version = version[:-2]

            # 推断架构
            arch = 'amd64'
            if exe and 'x86_64-linux-gnu' in exe:
                arch = 'amd64'
            elif stack_info and 'x86_64-linux-gnu' in stack_info:
                arch = 'amd64'
            elif exe and 'x86' in exe.lower():
                arch = 'i386'
            elif stack_info and 'x86' in stack_info.lower():
                arch = 'i386'

            key = (package, version, arch)
            if key in task_map:
                task_map[key]['count'] += count
            else:
                task_map[key] = {
                    'package': package,
                    'version': version,
                    'arch': arch,
                    'count': count
                }

    # 排序：按崩溃次数从高到低
    tasks = sorted(task_map.values(), key=lambda x: x['count'], reverse=True)

    # 为每个任务添加额外信息
    for task in tasks:
        # 设置优先级
        if task['count'] >= 45:
            task['priority'] = 'high'
        elif task['count'] >= 20:
            task['priority'] = 'medium'
        else:
            task['priority'] = 'low'

        # 初始化状态
        task['status'] = 'pending'
        task['downloaded_at'] = None
        task['error'] = None
        task['downloaded_files'] = []
        task['retry_count'] = 0

    # 保存到文件
    tasks_file = os.path.join(output_dir, 'download_tasks.json')
    tasks_data = {
        'generated_at': datetime.now().isoformat(),
        'total_tasks': len(tasks),
        'total_files': len(tasks) * 2,  # 每个包有主包和调试包
        'tasks': tasks
    }

    with open(tasks_file, 'w', encoding='utf-8') as f:
        json.dump(tasks_data, f, indent=2, ensure_ascii=False)

    print(f"\n任务生成完成！")
    print(f"   总计: {len(tasks)} 个包版本")
    print(f"   文件数: {len(tasks) * 2}（主包 + 调试包）")

    # 显示统计信息
    high_priority = sum(1 for t in tasks if t['priority'] == 'high')
    medium_priority = sum(1 for t in tasks if t['priority'] == 'medium')
    low_priority = sum(1 for t in tasks if t['priority'] == 'low')

    print(f"\n优先级分布:")
    print(f"   高优先级（>=45次崩溃）: {high_priority}")
    print(f"   中优先级（20-44次崩溃）: {medium_priority}")
    print(f"   低优先级（<20次崩溃）: {low_priority}")

    # 显示前10个任务
    print(f"\n前10个任务:")
    for i, task in enumerate(tasks[:10], 1):
        priority_icon = "高" if task['priority'] == 'high' else "中" if task['priority'] == 'medium' else "低"
        print(f"   {i:2d}. {task['package']:25s} v{task['version']:15s} - {task['count']:3d} 次 [{priority_icon}]")

    print(f"\n文件已保存到: {tasks_file}")

    return tasks_data

def main():
    parser = argparse.ArgumentParser(description='从崩溃数据生成下载任务')
    parser.add_argument('--crash-data', help='崩溃数据CSV文件路径')
    parser.add_argument('--package', help='包名（从对应筛选数据中查找）')
    parser.add_argument('--workspace', default=DEFAULT_WORKSPACE, help='工作目录')

    args = parser.parse_args()

    # 确定崩溃数据路径
    if args.crash_data:
        crash_data_path = args.crash_data
    elif args.package:
        crash_data_path = f"{args.workspace}/2.数据筛选/filtered_{args.package}_crash_data.csv"
    else:
        print("错误: 请指定 --crash-data 或 --package 参数")
        return

    output_dir = f"{args.workspace}/4.包管理/下载包"
    os.makedirs(output_dir, exist_ok=True)

    generate_tasks(crash_data_path, output_dir)

if __name__ == "__main__":
    main()
