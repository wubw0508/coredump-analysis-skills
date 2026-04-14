"""
通用数据模型定义 - 崩溃分析通用数据结构
"""
from dataclasses import dataclass, field
from typing import List, Dict, Optional
from datetime import datetime


@dataclass
class CrashRecord:
    """单条崩溃记录"""
    version: str
    package: str
    count: int
    signal: str
    stack_info: str
    stack_signature: str
    stack_info_size: int
    stack_frames_count: int
    app_layer_library: str
    app_layer_symbol: str
    first_seen: str
    baseline: str = ""
    sys_v_number: str = ""

    @property
    def is_app_layer(self) -> bool:
        """判断是否为应用层崩溃 - 子类可覆盖"""
        raise NotImplementedError("子类需要实现 is_app_layer 属性")

    @property
    def is_plugin(self) -> bool:
        """判断是否为插件崩溃 - 子类可覆盖"""
        raise NotImplementedError("子类需要实现 is_plugin 属性")

    def to_dict(self) -> Dict:
        """转换为字典"""
        return {
            "version": self.version,
            "package": self.package,
            "count": self.count,
            "signal": self.signal,
            "app_layer_library": self.app_layer_library,
            "app_layer_symbol": self.app_layer_symbol,
            "first_seen": self.first_seen,
            "baseline": self.baseline,
        }


@dataclass
class FixMapping:
    """崩溃→修复映射"""
    commit_hash: str
    description: str
    files: List[str]
    functions: List[str]
    gerrit_change_id: str = ""
    gerrit_change_url: str = ""
    gerrit_change_number: Optional[int] = None
    commit_date: str = ""
    project: str = ""  # 新增：所属项目

    def get_gerrit_url(self, base_url: str = "https://gerrit.uniontech.com") -> str:
        """获取Gerrit变更URL"""
        if self.gerrit_change_url:
            return self.gerrit_change_url
        if self.gerrit_change_number:
            return f"{base_url}/c/{self.project}/+/{self.gerrit_change_number}"
        if self.commit_hash and self.project:
            # 通过 commit hash 查询需要 change number，这里返回空
            return ""
        return ""

    def get_short_commit(self) -> str:
        """获取短commit hash"""
        return self.commit_hash[:7] if len(self.commit_hash) >= 7 else self.commit_hash


@dataclass
class VersionSignalDist:
    """版本崩溃信号分布"""
    sigsegv: int = 0
    sigabrt: int = 0
    sigbus: int = 0
    sigill: int = 0

    def to_dict(self) -> Dict[str, int]:
        return {
            "SIGSEGV": self.sigsegv,
            "SIGABRT": self.sigabrt,
            "SIGBUS": self.sigbus,
            "SIGILL": self.sigill
        }

    @property
    def total(self) -> int:
        return self.sigsegv + self.sigabrt + self.sigbus + self.sigill


@dataclass
class VersionStackFrames:
    """版本堆栈帧分布"""
    library: str
    count: int


@dataclass
class VersionAnalysis:
    """单个版本的崩溃分析结果"""
    version: str
    total_crashes: int
    unique_crashes: int
    signal_dist: VersionSignalDist = field(default_factory=VersionSignalDist)
    app_layer_crashes: List[CrashRecord] = field(default_factory=list)
    system_crashes: List[CrashRecord] = field(default_factory=list)
    plugin_crashes: List[CrashRecord] = field(default_factory=list)
    stack_frames: List[VersionStackFrames] = field(default_factory=list)
    fix_mappings: List[FixMapping] = field(default_factory=list)
    is_analyzed: bool = False
    analysis_notes: str = ""

    @property
    def app_layer_count(self) -> int:
        return len(self.app_layer_crashes)

    @property
    def system_count(self) -> int:
        return len(self.system_crashes)

    @property
    def plugin_count(self) -> int:
        return len(self.plugin_crashes)


@dataclass
class CrashStatistics:
    """崩溃统计数据"""
    total_records: int = 0
    valid_records: int = 0
    unique_crashes: int = 0
    duplicate_crashes: int = 0
    versions_count: int = 0
    analysis_time: str = ""
    by_version: Dict[str, Dict[str, int]] = field(default_factory=dict)
    by_signal: Dict[str, int] = field(default_factory=dict)
    by_baseline: Dict[str, int] = field(default_factory=dict)
    app_layer_libs: Dict[str, int] = field(default_factory=dict)
    top_crashes: List[Dict] = field(default_factory=list)


@dataclass
class CrashAnalysisReport:
    """完整崩溃分析报告"""
    analysis_time: str
    package_name: str
    statistics: CrashStatistics
    version_analyses: List[VersionAnalysis] = field(default_factory=list)
    all_fix_mappings: List[FixMapping] = field(default_factory=list)

    @property
    def analyzed_versions_count(self) -> int:
        return len([v for v in self.version_analyses if v.is_analyzed])

    @property
    def total_versions(self) -> int:
        return len(self.version_analyses)

    @property
    def total_app_layer_crashes(self) -> int:
        return sum(v.app_layer_count for v in self.version_analyses)

    @property
    def total_system_crashes(self) -> int:
        return sum(v.system_count for v in self.version_analyses)


@dataclass
class PackageConfig:
    """包配置 - 用于通用化分析"""
    name: str  # 包名，如 "dde-dock", "dde-session-shell"
    display_name: str  # 显示名称，如 "dde-dock"
    gerrit_project: str  # Gerrit项目名，如 "dde-dock", "dde-session-shell"
    app_layer_patterns: List[str]  # 应用层代码模式
    plugin_libs: List[str]  # 插件库列表
    system_libs: List[str]  # 系统库列表（可选，用于补充）
    app_name_in_stack: str = ""  # 堆栈中出现的应用名，如 "dde-dock"

    def __post_init__(self):
        if not self.app_name_in_stack:
            self.app_name_in_stack = self.name
