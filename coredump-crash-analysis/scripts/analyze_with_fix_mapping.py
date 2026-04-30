#!/usr/bin/env python3
"""
崩溃分析 - 集成修复映射和Gerrit提交功能
支持自动检查develop/eagle分支是否已修复，未修复则尝试提交
"""
import csv
import re
import argparse
import os
import glob
import json
import sys
import subprocess
from datetime import datetime
from typing import List, Dict, Optional, Tuple

# 添加 centralized 模块路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CENTRALIZED_DIR = os.path.join(SCRIPT_DIR, '..', 'centralized')
sys.path.insert(0, CENTRALIZED_DIR)

from crash_classifier import CrashClassifier, ClassifierConfig
from report_generator import ReportGenerator
from base_config import get_version_tag_map, lookup_version_tag, SYSTEM_LIBRARIES
from fix_mapper import FixMapper, KnownFix, FixMapping
from gerrit_client import GerritClient, GerritConfig


class CrashAnalyzerWithFixMapping:
    """集成修复映射的崩溃分析器"""

    def __init__(self, package: str, workspace: str, target_branch: str = "origin/develop/eagle"):
        self.package = package
        self.workspace = workspace
        self.target_branch = target_branch
        self.classifier = CrashClassifier(ClassifierConfig())
        self.gerrit_client = GerritClient()
        self.fix_mapper = self._create_fix_mapper()
        self.results = []
        self.fix_statistics = {
            "total_crashes": 0,
            "mapped_fixes": 0,
            "already_fixed": 0,
            "needs_fix": 0,
            "submitted": 0,
            "failed": 0
        }

    def _create_fix_mapper(self) -> FixMapper:
        """根据包名创建对应的修复映射器"""
        # 这里可以根据不同包名加载不同的已知修复配置
        # 目前只支持dde-dock，其他包需要扩展
        if self.package == "dde-dock":
            return FixMapper.create_for_dde_dock()
        else:
            # 返回空的映射器
            return FixMapper(known_fixes={}, project=self.package)

    def parse_frames(self, stack_info: str) -> List[Dict]:
        """解析堆栈帧"""
        if not stack_info:
            return []

        frames = []
        lines = stack_info.strip().split('\n')

        for line in lines:
            match = re.match(r'\s*#\s*(\d+)\s+0x[0-9a-f]+\s+(\S+|n/a)\s+\(([^)]+)\)', line)
            if match:
                frames.append({
                    'num': int(match.group(1)),
                    'symbol': match.group(2),
                    'library': match.group(3)
                })
        return frames

    def analyze_crash_record(self, row: Dict, idx: int) -> Dict:
        """分析单条崩溃记录"""
        result = {
            'index': idx,
            'id': row.get('ID', '')[:60],
            'date': row.get('Dt', ''),
            'package': row.get('Package', self.package),
            'version': row.get('Version', ''),
            'signal': row.get('Sig', ''),
            'system_c': row.get('Sys C', ''),
            'system_v': row.get('Sys V', ''),
            'buildid': row.get('Buildid', ''),
            'count': int(row.get('Count', 1)),
            'stack_info': row.get('StackInfo', ''),
            'app_layer_library': row.get('App_Layer_Library', ''),
            'app_layer_symbol': row.get('App_Layer_Symbol', ''),
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
        result['frames'] = self.parse_frames(result['stack_info'])

        # 分类崩溃
        classification = self.classifier.classify(result)
        result['crash_type'] = classification

        # 查找应用层崩溃帧
        app_keywords = [self.package.lower(), 'dde-', 'deepin']
        for i, frame in enumerate(result['frames']):
            lib = frame['library'].lower()
            if any(kw in lib for kw in app_keywords):
                result['key_frame'] = i
                result['key_frame_info'] = frame
                break

        # 尝试映射到已知修复
        result['mapped_fixes'] = self._map_to_fixes(result)

        return result

    def _map_to_fixes(self, result: Dict) -> List[Dict]:
        """将崩溃映射到已知修复"""
        if not self.fix_mapper:
            return []

        # 创建一个简单的对象来传递属性
        class CrashRecord:
            def __init__(self, data):
                self.app_layer_symbol = data.get('app_layer_symbol', '')
                self.app_layer_library = data.get('app_layer_library', '')
                self.stack_info = data.get('stack_info', '')

        record = CrashRecord(result)
        fixes = self.fix_mapper.map_crash_to_fixes(record)

        return [
            {
                'commit_hash': fix.commit_hash,
                'description': fix.description,
                'files': fix.files,
                'functions': fix.functions,
                'gerrit_change_id': fix.gerrit_change_id,
                'gerrit_change_number': fix.gerrit_change_number,
                'project': fix.project
            }
            for fix in fixes
        ]

    def check_fix_in_branch(self, fix: Dict) -> bool:
        """检查修复是否已在目标分支中"""
        commit_hash = fix.get('commit_hash', '')
        project = fix.get('project', self.package)

        if not commit_hash:
            return False

        # 使用Gerrit客户端检查commit是否已合并
        try:
            is_merged = self.gerrit_client.is_commit_merged(commit_hash, project)
            return is_merged
        except Exception as e:
            print(f"  [!] 检查Gerrit提交失败: {e}")
            return False

    def generate_fix_code(self, result: Dict, fix: Dict) -> Optional[str]:
        """生成修复代码（示例实现）"""
        # 这里可以根据不同的崩溃类型生成修复代码
        # 目前返回示例代码
        crash_type = result.get('crash_type', 'system')
        key_frame = result.get('key_frame_info', {})

        if crash_type == 'app_layer':
            symbol = key_frame.get('symbol', '')
            library = key_frame.get('library', '')

            # 生成空指针检查修复
            if 'SIGSEGV' in result.get('signal', ''):
                return f"""// 修复 {symbol} 中的空指针崩溃
// 文件: {library}
// 建议: 添加空指针检查

if (obj == nullptr) {{
    qWarning() << "Null pointer detected in {symbol}";
    return;
}}
// 原有代码继续...
"""
        return None

    def submit_to_gerrit(self, fix_code: str, fix: Dict, result: Dict) -> bool:
        """提交修复到Gerrit"""
        # 这里实现实际的Gerrit提交逻辑
        # 目前只是模拟提交
        print(f"  [模拟提交] 提交修复到 {self.target_branch}")
        print(f"  Commit: {fix.get('commit_hash', 'N/A')}")
        print(f"  Description: {fix.get('description', 'N/A')}")

        # 实际实现需要:
        # 1. 创建fix分支
        # 2. 应用修复代码
        # 3. 提交到Gerrit
        # 4. 添加reviewer

        return True

    def analyze_and_fix(self, filtered_csv: str, output_dir: str) -> Dict:
        """分析崩溃并尝试修复"""
        print(f"\n{'='*80}")
        print(f"崩溃分析 - {self.package}")
        print(f"目标分支: {self.target_branch}")
        print(f"{'='*80}\n")

        # 读取筛选后的CSV文件
        if not os.path.exists(filtered_csv):
            print(f"[!] 筛选文件不存在: {filtered_csv}")
            return self.fix_statistics

        with open(filtered_csv, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        print(f"读取到 {len(rows)} 条崩溃记录\n")

        # 分析每条记录
        for i, row in enumerate(rows, 1):
            result = self.analyze_crash_record(row, i)
            self.results.append(result)
            self.fix_statistics['total_crashes'] += result.get('count', 1)

            # 检查是否有映射的修复
            if result['mapped_fixes']:
                self.fix_statistics['mapped_fixes'] += 1
                print(f"[记录 {i}] 发现 {len(result['mapped_fixes'])} 个可能的修复")

                for fix in result['mapped_fixes']:
                    # 检查是否已在目标分支中
                    if self.check_fix_in_branch(fix):
                        self.fix_statistics['already_fixed'] += 1
                        print(f"  ✓ 已修复: {fix['description']}")
                    else:
                        self.fix_statistics['needs_fix'] += 1
                        print(f"  ✗ 需要修复: {fix['description']}")

                        # 生成修复代码
                        fix_code = self.generate_fix_code(result, fix)
                        if fix_code:
                            # 提交到Gerrit
                            if self.submit_to_gerrit(fix_code, fix, result):
                                self.fix_statistics['submitted'] += 1
                            else:
                                self.fix_statistics['failed'] += 1

        # 生成报告
        self._generate_report(output_dir)

        return self.fix_statistics

    def _generate_report(self, output_dir: str):
        """生成分析报告"""
        os.makedirs(output_dir, exist_ok=True)

        # 生成统计报告
        stats_file = os.path.join(output_dir, f"{self.package}_fix_statistics.json")
        with open(stats_file, 'w', encoding='utf-8') as f:
            json.dump(self.fix_statistics, f, indent=2, ensure_ascii=False)

        # 生成详细报告
        report_file = os.path.join(output_dir, f"{self.package}_fix_report.md")
        with open(report_file, 'w', encoding='utf-8') as f:
            f.write(f"# {self.package} 崩溃修复报告\n\n")
            f.write(f"**生成时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"**目标分支**: {self.target_branch}\n\n")

            f.write("## 统计摘要\n\n")
            f.write(f"- 总崩溃次数: {self.fix_statistics['total_crashes']}\n")
            f.write(f"- 映射到修复的崩溃: {self.fix_statistics['mapped_fixes']}\n")
            f.write(f"- 已在目标分支修复: {self.fix_statistics['already_fixed']}\n")
            f.write(f"- 需要修复: {self.fix_statistics['needs_fix']}\n")
            f.write(f"- 已提交: {self.fix_statistics['submitted']}\n")
            f.write(f"- 提交失败: {self.fix_statistics['failed']}\n\n")

            f.write("## 详细分析\n\n")
            for result in self.results:
                if result['mapped_fixes']:
                    f.write(f"### 记录 {result['index']}\n\n")
                    f.write(f"- **信号**: {result['signal']} ({result['signal_desc']})\n")
                    f.write(f"- **版本**: {result['version']}\n")
                    f.write(f"- **崩溃次数**: {result['count']}\n\n")

                    if 'key_frame_info' in result:
                        kf = result['key_frame_info']
                        f.write(f"**关键帧**:\n")
                        f.write(f"- 库: {kf['library']}\n")
                        f.write(f"- 符号: {kf['symbol']}\n\n")

                    f.write("**映射的修复**:\n\n")
                    for fix in result['mapped_fixes']:
                        f.write(f"- {fix['description']}\n")
                        f.write(f"  - Commit: {fix['commit_hash']}\n")
                        if fix.get('gerrit_change_number'):
                            f.write(f"  - Gerrit: {fix['gerrit_change_number']}\n")
                        f.write("\n")

        print(f"\n报告已生成:")
        print(f"  统计: {stats_file}")
        print(f"  详细: {report_file}")


def main():
    parser = argparse.ArgumentParser(description='崩溃分析 - 集成修复映射和Gerrit提交')
    parser.add_argument('--package', required=True, help='包名')
    parser.add_argument('--workspace', required=True, help='工作目录')
    parser.add_argument('--target-branch', default='origin/develop/eagle', help='目标分支')
    parser.add_argument('--filtered-csv', help='筛选后的CSV文件路径')
    parser.add_argument('--output-dir', help='输出目录')

    args = parser.parse_args()

    # 设置默认路径
    if not args.filtered_csv:
        args.filtered_csv = os.path.join(args.workspace, '2.数据筛选', f'filtered_{args.package}_crash_data.csv')
    if not args.output_dir:
        args.output_dir = os.path.join(args.workspace, '5.崩溃分析', args.package)

    # 创建分析器并执行分析
    analyzer = CrashAnalyzerWithFixMapping(
        package=args.package,
        workspace=args.workspace,
        target_branch=args.target_branch
    )

    stats = analyzer.analyze_and_fix(args.filtered_csv, args.output_dir)

    print(f"\n{'='*80}")
    print("分析完成")
    print(f"{'='*80}")
    print(f"总崩溃次数: {stats['total_crashes']}")
    print(f"映射到修复: {stats['mapped_fixes']}")
    print(f"已修复: {stats['already_fixed']}")
    print(f"需要修复: {stats['needs_fix']}")
    print(f"已提交: {stats['submitted']}")
    print(f"失败: {stats['failed']}")


if __name__ == '__main__':
    main()
