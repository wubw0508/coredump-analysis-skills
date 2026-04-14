"""
报告生成器 - 通用 Markdown 崩溃分析报告生成
"""
from typing import List, Dict, Optional, Any
from datetime import datetime


class ReportGenerator:
    """Markdown 报告生成器 - 通用版本"""

    def __init__(self, package_name: str = "unknown"):
        self.package_name = package_name

    def generate_report(self,
                       version_analyses: List,
                       statistics: Any,
                       all_fix_mappings: List,
                       gerrit_client=None) -> str:
        """
        生成完整的崩溃分析报告

        参数:
            version_analyses: 各版本分析结果列表
            statistics: 崩溃统计数据对象
            all_fix_mappings: 所有修复映射列表
            gerrit_client: Gerrit 客户端

        返回:
            Markdown 格式的报告字符串
        """
        lines = []
        lines.append(f"# {self.package_name} 崩溃分析报告")
        lines.append("")
        lines.append(f"**分析时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append(f"**包名**: {self.package_name}")
        lines.append("")
        lines.append("---")
        lines.append("")

        # 统计摘要
        lines.extend(self._generate_summary_section(statistics))

        # 按版本生成分析
        lines.append("---")
        lines.append("")
        lines.append("## 各版本崩溃详情")
        lines.append("")

        for analysis in version_analyses:
            lines.extend(self._generate_version_section(analysis, gerrit_client))

        # 汇总表
        lines.append("---")
        lines.append("")
        lines.append("## 版本汇总")
        lines.append("")
        lines.append(self._generate_summary_table(version_analyses))
        lines.append("")

        # 已提交修复汇总
        if all_fix_mappings:
            lines.append("---")
            lines.append("")
            lines.append("## 已提交修复汇总")
            lines.append("")
            lines.append(self._generate_fix_registry(all_fix_mappings, gerrit_client))
            lines.append("")

        lines.append(f"*报告生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*")

        return "\n".join(lines)

    def _generate_summary_section(self, statistics: Any) -> List[str]:
        """生成统计摘要章节"""
        lines = []
        lines.append("## 统计摘要")
        lines.append("")

        if hasattr(statistics, 'total_records'):
            lines.append(f"- 原始记录数: {statistics.total_records}")
        if hasattr(statistics, 'valid_records'):
            lines.append(f"- 有效记录数: {statistics.valid_records}")
        if hasattr(statistics, 'unique_crashes'):
            lines.append(f"- 唯一崩溃数: {statistics.unique_crashes}")
        if hasattr(statistics, 'versions_count'):
            lines.append(f"- 版本数: {statistics.versions_count}")
        if hasattr(statistics, 'duplicate_crashes'):
            lines.append(f"- 重复崩溃: {statistics.duplicate_crashes}")

        lines.append("")
        return lines

    def _generate_version_section(self, analysis, gerrit_client=None) -> List[str]:
        """生成单个版本的报告章节"""
        lines = []

        lines.append(f"### 版本: {analysis.version} ({analysis.total_crashes}次崩溃)")
        lines.append("")
        lines.append("#### 崩溃信号分布")
        lines.append(f"- SIGSEGV: {analysis.signal_dist.sigsegv}次")
        lines.append(f"- SIGABRT: {analysis.signal_dist.sigabrt}次")
        lines.append(f"- SIGBUS: {analysis.signal_dist.sigbus}次")
        lines.append(f"- SIGILL: {analysis.signal_dist.sigill}次")
        lines.append("")

        # 应用层崩溃
        if analysis.app_layer_crashes:
            lines.append("#### 应用层崩溃详情")
            lines.append("")
            lines.append(f"**应用层崩溃数: {analysis.app_layer_count}**")
            lines.append("")

            crash_groups = self._group_crashes_by_symbol(analysis.app_layer_crashes)
            for symbol, crashes in crash_groups.items():
                lines.append(f"**{symbol}**")
                lines.append(f"- 崩溃次数: {len(crashes)}")
                if hasattr(crashes[0], 'first_seen'):
                    lines.append(f"- 首次出现: {crashes[0].first_seen}")
                if hasattr(crashes[0], 'app_layer_library'):
                    lines.append(f"- 所属库: {crashes[0].app_layer_library}")
                lines.append("")

                # 关联修复
                fixes = self._find_fixes_for_crashes(crashes)
                if fixes:
                    lines.append("**关联修复:**")
                    for fix in fixes:
                        url = ""
                        if gerrit_client and hasattr(gerrit_client, 'get_change_url'):
                            url = gerrit_client.get_change_url(fix.commit_hash, fix.project)
                        if url:
                            lines.append(f"- [{fix.commit_hash[:7]}] {fix.description} - [Gerrit]({url})")
                        else:
                            lines.append(f"- [{fix.commit_hash[:7]}] {fix.description}")
                    lines.append("")

            lines.append("")

        # 系统库崩溃
        if analysis.system_crashes:
            lines.append("#### 系统库崩溃 (无需修复)")
            lines.append(f"- 系统库崩溃数: {analysis.system_count}")
            lines.append("")

        # 插件崩溃
        if analysis.plugin_crashes:
            lines.append("#### 插件崩溃 (无需修复主应用)")
            lines.append(f"- 插件崩溃数: {analysis.plugin_count}")
            lines.append("")

        return lines

    def _group_crashes_by_symbol(self, crashes: List) -> Dict[str, List]:
        """按崩溃符号分组"""
        groups = {}
        for crash in crashes:
            symbol = getattr(crash, 'app_layer_symbol', '') or getattr(crash, 'symbol', '')
            if not symbol or symbol == "n/a":
                symbol = "未知符号"
            if symbol not in groups:
                groups[symbol] = []
            groups[symbol].append(crash)
        return groups

    def _find_fixes_for_crashes(self, crashes: List) -> List:
        """查找与崩溃关联的修复"""
        from fix_mapper import FixMapper
        mapper = FixMapper.create_for_dde_dock() if "dde-dock" in self.package_name else FixMapper()
        all_fixes = []

        for crash in crashes:
            fixes = mapper.map_crash_to_fixes(crash)
            all_fixes.extend(fixes)

        # 去重
        seen = set()
        unique = []
        for fix in all_fixes:
            if hasattr(fix, 'commit_hash') and fix.commit_hash not in seen:
                unique.append(fix)
                seen.add(fix.commit_hash)

        return unique

    def _generate_summary_table(self, analyses: List) -> str:
        """生成汇总表"""
        lines = []

        lines.append("| 版本 | 总崩溃 | 应用层崩溃 | 系统库崩溃 | 插件崩溃 |")
        lines.append("|-----|-------|-----------|-----------|---------|")

        total_crashes = 0
        total_app = 0
        total_sys = 0
        total_plugin = 0

        for a in analyses:
            total_crashes += a.total_crashes
            total_app += a.app_layer_count
            total_sys += a.system_count
            total_plugin += a.plugin_count
            lines.append(f"| {a.version} | {a.total_crashes} | {a.app_layer_count} | {a.system_count} | {a.plugin_count} |")

        lines.append(f"| **合计** | **{total_crashes}** | **{total_app}** | **{total_sys}** | **{total_plugin}** |")
        lines.append("")

        return "\n".join(lines)

    def _generate_fix_registry(self, fix_mappings: List, gerrit_client) -> str:
        """生成修复登记表格"""
        lines = []

        lines.append("| Commit | 功能 | 文件 | Gerrit 链接 |")
        lines.append("|--------|------|------|-------------|")

        for fix in fix_mappings:
            url = ""
            if gerrit_client and hasattr(gerrit_client, 'get_change_url'):
                url = gerrit_client.get_change_url(fix.commit_hash, fix.project)

            files_str = ", ".join([f.split("/")[-1] for f in fix.files[:2]]) if fix.files else ""
            funcs_str = ", ".join(fix.functions[:2]) if fix.functions else ""

            if url:
                lines.append(f"| {fix.commit_hash[:7]} | {fix.description} | {files_str} | [Link]({url}) |")
            else:
                lines.append(f"| {fix.commit_hash[:7]} | {fix.description} | {files_str} | - |")

        return "\n".join(lines)

    def generate_crash_fix_mapping_report(self,
                                          crashes: List,
                                          fix_mappings: List,
                                          gerrit_client=None) -> str:
        """
        生成崩溃与修复完整对应关系报告

        参数:
            crashes: 崩溃列表
            fix_mappings: 修复映射列表
            gerrit_client: Gerrit客户端

        返回:
            Markdown格式报告
        """
        lines = []
        lines.append(f"# {self.package_name} 崩溃与修复完整对应关系")
        lines.append("")
        lines.append(f"**生成时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append("")
        lines.append("---")
        lines.append("")

        # 按崩溃次数排序
        sorted_crashes = sorted(crashes, key=lambda x: x.count if hasattr(x, 'count') else 0, reverse=True)

        for crash in sorted_crashes[:20]:  # 只显示前20个
            lines.extend(self._generate_crash_section(crash, gerrit_client))

        # 修复汇总表
        lines.append("---")
        lines.append("")
        lines.append("## Gerrit修复汇总表")
        lines.append("")
        lines.append(self._generate_fix_registry(fix_mappings, gerrit_client))
        lines.append("")

        return "\n".join(lines)

    def _generate_crash_section(self, crash, gerrit_client=None) -> List[str]:
        """生成单个崩溃的章节"""
        lines = []

        symbol = getattr(crash, 'symbol', getattr(crash, 'app_layer_symbol', ''))
        count = getattr(crash, 'count', 0)
        library = getattr(crash, 'library', getattr(crash, 'app_layer_library', ''))
        signal = getattr(crash, 'signal', '')
        versions = getattr(crash, 'versions', [])

        lines.append(f"### {symbol}")
        lines.append("")
        lines.append(f"| 项目 | 内容 |")
        lines.append(f"|------|------|")
        lines.append(f"| **崩溃次数** | {count} |")
        lines.append(f"| **所属库** | {library} |")
        lines.append(f"| **信号** | {signal} |")
        lines.append(f"| **影响版本** | {', '.join(versions[:5])}{'...' if len(versions) > 5 else ''} |")
        lines.append("")

        # 完整堆栈
        if hasattr(crash, 'all_records') and crash.all_records:
            lines.append("### 完整堆栈")
            lines.append("```")
            # 取第一条记录的完整堆栈
            first_record = crash.all_records[0]
            if isinstance(first_record, str) and 'Stack trace' in first_record:
                # 提取 stack_info
                start = first_record.find("Stack trace")
                if start >= 0:
                    lines.append(first_record[start:])
            lines.append("```")
            lines.append("")

        # 关联修复
        fixes = self._find_fixes_for_crashes([crash])
        if fixes:
            lines.append("### 可能相关的Gerrit修复")
            lines.append("")
            for fix in fixes:
                url = ""
                if gerrit_client and hasattr(gerrit_client, 'get_change_url'):
                    url = gerrit_client.get_change_url(fix.commit_hash, fix.project)
                lines.append(f"- [{fix.commit_hash[:7]}] {fix.description}")
                if fix.files:
                    lines.append(f"  - 修复文件: {', '.join(fix.files)}")
                if url:
                    lines.append(f"  - Gerrit: {url}")
            lines.append("")

        lines.append("---")
        lines.append("")

        return lines
