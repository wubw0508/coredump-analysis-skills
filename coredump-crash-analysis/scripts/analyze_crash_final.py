#!/usr/bin/env python3
"""
崩溃数据分析 - 集成 centralized 模块
支持按版本过滤分析，自动分类崩溃类型，生成报告
"""
import csv
import re
import argparse
import os
import glob
import json
import sys
from datetime import datetime

# 添加 centralized 模块路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CENTRALIZED_DIR = os.path.join(SCRIPT_DIR, '..', 'centralized')
sys.path.insert(0, CENTRALIZED_DIR)

from crash_classifier import CrashClassifier, ClassifierConfig
from report_generator import ReportGenerator
from base_config import get_version_tag_map, lookup_version_tag, SYSTEM_LIBRARIES

DEFAULT_WORKSPACE = "/home/wubw/workspace"


def parse_frames(stack_info):
    """解析堆栈帧"""
    if not stack_info:
        return []

    frames = []
    lines = stack_info.strip().split('\n')

    for line in lines:
        # 匹配: #0 0x000055c65fa3409b n/a (dde-control-center)
        match = re.match(r'\s*#\s*(\d+)\s+0x[0-9a-f]+\s+(\S+|n/a)\s+\(([^)]+)\)', line)
        if match:
            frames.append({
                'num': int(match.group(1)),
                'symbol': match.group(2),
                'library': match.group(3)
            })
    return frames


def get_field(row, field_name):
    """从行中获取字段，支持大小写"""
    if field_name in row:
        return row[field_name]
    for k, v in row.items():
        if k.lower() == field_name.lower():
            return v
    return ''


def analyze_row(row, idx, package, classifier):
    """分析单条记录"""
    result = {
        'index': idx,
        'id': get_field(row, 'ID')[:60],
        'date': get_field(row, 'Dt'),
        'package': get_field(row, 'Package') or package,
        'version': get_field(row, 'Version'),
        'signal': get_field(row, 'Sig'),
        'system_c': get_field(row, 'Sys C'),
        'system_v': get_field(row, 'Sys V'),
        'buildid': get_field(row, 'Buildid'),
        'count': int(get_field(row, 'Count') or 1),
        'stack_info': get_field(row, 'StackInfo'),
        'app_layer_library': get_field(row, 'App_Layer_Library'),
        'app_layer_symbol': get_field(row, 'App_Layer_Symbol'),
    }

    # 崩溃类型分析
    signal = result['signal']
    if signal == 'SIGSEGV':
        result['signal_desc'] = '段错误 - 非法内存访问'
    elif signal == 'SIGABRT':
        result['signal_desc'] = '主动终止 - 检测到严重错误'
    elif signal == 'SIGBUS':
        result['signal_desc'] = '总线错误 - 内存对齐问题'
    else:
        result['signal_desc'] = f'未知信号: {signal}'

    # 解析堆栈
    result['frames'] = parse_frames(result['stack_info'])

    # 分类崩溃
    classification = classifier.classify(result)
    result['crash_type'] = classification  # app_layer, plugin, system

    # 查找应用层崩溃帧
    app_keywords = [package.lower(), 'dde-', 'deepin']
    for i, frame in enumerate(result['frames']):
        lib = frame['library'].lower()
        if any(kw in lib for kw in app_keywords):
            result['key_frame'] = i
            result['key_frame_info'] = frame
            break

    return result


def print_analysis(result, package):
    """打印单条分析结果"""
    crash_type_emoji = {
        'app_layer': '🔧',
        'plugin': '🔌',
        'system': '⚙️'
    }
    emoji = crash_type_emoji.get(result['crash_type'], '❓')

    print("=" * 80)
    print(f"[记录 {result['index']}] {emoji} {result['crash_type'].upper()} 崩溃分析")
    print("=" * 80)
    print(f"  ID:       {result['id'][:50]}...")
    print(f"  时间:     {result['date']}")
    print(f"  包:       {result['package']}")
    print(f"  版本:     {result['version']}")
    print(f"  信号:     {result['signal']} ({result['signal_desc']})")
    print(f"  系统:     {result['system_c']} {result['system_v']}")
    print(f"  崩溃类型: {result['crash_type']}")
    print(f"  崩溃次数: {result['count']}")
    print()

    # 关键帧分析
    print("[崩溃定位分析]")
    print("-" * 80)

    if result['crash_type'] == 'app_layer':
        print(f"✓ 已定位到应用层崩溃帧")
        if 'key_frame' in result:
            kf = result['key_frame_info']
            print(f"  帧编号:   #{kf['num']}")
            print(f"  库文件:   {kf['library']}")
            print(f"  符号:     {kf['symbol']}")
            print()
            print("下一步操作:")
            print("------------------------------------------------------------")
            print("  1. 安装调试符号包")
            print(f"     sudo apt-get install {result['package']}-dbgsym")
            print()
            print("  2. 使用 GDB 分析 coredump")
            print(f"     gdb /usr/bin/{result['package']} -c <coredump>")
            print(f"     (gdb) bt full")
            print()
            print("  3. 使用 addr2line 定位源代码行号")
            if result['buildid']:
                print(f"     addr2line -e /usr/lib/debug/.build-id/{result['buildid'][:2]}/{result['buildid'][2:]} <地址>")
            print()
            print("修复建议:")
            print("  - 添加空指针检查: if (obj) { obj->method(); }")
            print("  - 使用智能指针避免野指针")
            print("  - 数组访问前检查边界")

    elif result['crash_type'] == 'plugin':
        print(f"⚠ 插件崩溃 - 不需要修复主应用")
        print("  分析: 崩溃发生在插件中")
        print("  建议: 检查插件更新或禁用问题插件")

    else:
        print(f"⚙ 系统库崩溃 - 无法直接修复")
        print("  分析: 崩溃发生在系统共享库中 (如 Qt/Dtk 等)")
        print()
        print("可能原因:")
        print("  1. 应用传递了无效的参数给库函数")
        print("  2. 对象生命周期管理不当 (野指针)")
        print("  3. 多线程竞态条件")
        print()
        print("建议:")
        print("  - 使用 GDB 查看调用者的上下文")
        print("  - 在应用代码中添加参数验证")
        print("  - 添加日志追踪关键函数调用")

    # 堆栈跟踪
    print()
    print("堆栈跟踪 (前8帧):")
    print("-" * 80)
    for i, frame in enumerate(result['frames'][:8]):
        is_key = 'key_frame' in result and i == result['key_frame']
        prefix = ">" if is_key else " "

        if frame['symbol'] == 'n/a' or len(frame['symbol']) < 3:
            print(f"  {prefix} #{frame['num']:2d} [{frame['library']}]")
        else:
            symbol = frame['symbol']
            if len(symbol) > 45:
                symbol = symbol[:42] + "..."
            print(f"  {prefix} #{frame['num']:2d} {symbol}")
            print(f"       库: {frame['library']}")

    print()


def generate_summary_report(all_results, package):
    """生成汇总报告"""
    stats = {
        'total': len(all_results),
        'app_layer': 0,
        'plugin': 0,
        'system': 0,
        'by_signal': {},
        'by_version': {},
        'top_crashes': []
    }

    for r in all_results:
        # 分类统计
        crash_type = r.get('crash_type', 'system')
        stats[crash_type] += 1

        # 信号统计
        sig = r.get('signal', 'UNKNOWN')
        stats['by_signal'][sig] = stats['by_signal'].get(sig, 0) + 1

        # 版本统计
        ver = r.get('version', 'unknown')
        if ver not in stats['by_version']:
            stats['by_version'][ver] = 0
        stats['by_version'][ver] += 1

    return stats


def main():
    parser = argparse.ArgumentParser(description='崩溃数据分析工具 (集成 centralized 模块)')
    parser.add_argument('--csv', help='CSV文件路径')
    parser.add_argument('--package', default='dde-launcher', help='包名')
    parser.add_argument('--version', help='指定分析特定版本')
    parser.add_argument('--workspace', default=DEFAULT_WORKSPACE, help='工作目录')
    parser.add_argument('--limit', type=int, default=0, help='分析记录数（0=分析所有）')
    parser.add_argument('--output', help='输出报告文件路径')
    parser.add_argument('--classify-only', action='store_true', help='仅分类，不打印详细分析')
    parser.add_argument('--show-app-only', action='store_true', help='仅显示应用层崩溃')

    args = parser.parse_args()

    # 确定 CSV 路径
    if args.csv:
        csv_path = args.csv
    else:
        filter_dir = f"{args.workspace}/2.数据筛选"
        patterns = [
            f"{filter_dir}/filtered_{args.package}_crash_data.csv",
            f"{filter_dir}/filtered_*_crash_data.csv",
        ]
        csv_path = None
        for pattern in patterns:
            files = glob.glob(pattern)
            if files:
                csv_path = sorted(files)[-1]
                break
        if not csv_path:
            download_dir = f"{args.workspace}/1.数据下载"
            download_files = glob.glob(f"{download_dir}/**/{args.package}*crash*.csv", recursive=True)
            if download_files:
                csv_path = sorted(download_files)[-1]

    if not csv_path or not os.path.exists(csv_path):
        print(f"错误: 无法找到 CSV 文件")
        print(f"工作目录: {args.workspace}")
        print(f"包名: {args.package}")
        print(f"尝试的路径: {csv_path}")
        return

    print(f"使用 CSV 文件: {csv_path}")

    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
    except Exception as e:
        print(f"错误: 无法读取 CSV 文件 - {e}")
        return

    # 创建分类器
    classifier = CrashClassifier.for_package(args.package)

    # 按版本过滤
    if args.version:
        filtered_rows = [r for r in rows if args.version in get_field(r, 'Version')]
        print(f"\n版本过滤: {args.version}")
        print(f"匹配记录数: {len(filtered_rows)}/{len(rows)}")
    else:
        filtered_rows = rows

    print()
    print("=" * 80)
    print("崩溃数据分析报告")
    print("=" * 80)
    if args.version:
        print(f"版本: {args.version}")
    print(f"包名: {args.package}")
    print()

    # 分析
    all_results = []
    valid_records = 0
    analyzed_count = 0

    limit = args.limit if args.limit > 0 else len(filtered_rows)

    for i, row in enumerate(filtered_rows, 1):
        if analyzed_count >= limit:
            break
        try:
            result = analyze_row(row, i, args.package, classifier)
            if result['frames']:
                # 根据参数过滤
                if args.show_app_only and result['crash_type'] != 'app_layer':
                    continue

                if not args.classify_only:
                    print_analysis(result, args.package)

                valid_records += 1
                analyzed_count += 1
                all_results.append(result)

        except Exception as e:
            print(f"记录 {i} 解析出错: {e}")

    # 生成汇总
    print()
    print("=" * 80)
    print("统计摘要")
    print("=" * 80)

    stats = generate_summary_report(all_results, args.package)

    print(f"\n有效记录数: {valid_records}/{len(filtered_rows)}")

    print(f"\n崩溃类型分布:")
    print(f"  🔧 应用层崩溃 (需要修复): {stats['app_layer']}")
    print(f"  🔌 插件崩溃 (检查插件): {stats['plugin']}")
    print(f"  ⚙️ 系统库崩溃 (无法直接修复): {stats['system']}")

    print("\n崩溃信号分布:")
    for sig, count in sorted(stats['by_signal'].items(), key=lambda x: -x[1]):
        print(f"  {sig}: {count} 次")

    if not args.version:
        print("\n版本分布 (Top 10):")
        for ver, count in sorted(stats['by_version'].items(), key=lambda x: -x[1])[:10]:
            print(f"  {ver}: {count} 次")

    # 输出报告
    if args.output:
        print(f"\n生成报告到: {args.output}")
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(f"# {args.package} 崩溃分析报告\n")
            f.write(f"\n**分析时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"**版本过滤**: {args.version or '全部'}\n")
            f.write("\n## 统计摘要\n")
            f.write(f"\n- 有效记录数: {valid_records}\n")
            f.write(f"- 🔧 应用层崩溃: {stats['app_layer']}\n")
            f.write(f"- 🔌 插件崩溃: {stats['plugin']}\n")
            f.write(f"- ⚙️ 系统库崩溃: {stats['system']}\n")
            f.write("\n## 崩溃信号分布\n")
            for sig, count in sorted(stats['by_signal'].items(), key=lambda x: -x[1]):
                f.write(f"- {sig}: {count} 次\n")

    print()
    print("=" * 80)
    print("分析完成")
    print("=" * 80)


if __name__ == '__main__':
    main()
