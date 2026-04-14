"""
通用崩溃分析模块
提供通用数据模型、分类器、Gerrit客户端等
"""
from .models import (
    CrashRecord,
    FixMapping,
    VersionSignalDist,
    VersionStackFrames,
    VersionAnalysis,
    CrashStatistics,
    CrashAnalysisReport,
    PackageConfig,
)
from .base_config import (
    SYSTEM_LIBRARIES,
    PLUGIN_LIBRARIES,
    GERRIT_BASE_URL,
    GERRIT_API_URL,
    DEFAULT_WORKSPACE,
    is_system_library,
    is_plugin_library,
)
from .gerrit_client import GerritClient, GerritConfig
from .crash_classifier import CrashClassifier, ClassifierConfig
from .fix_mapper import FixMapper, FixMapping, KnownFix
from .report_generator import ReportGenerator

__all__ = [
    # models
    "CrashRecord",
    "FixMapping",
    "VersionSignalDist",
    "VersionStackFrames",
    "VersionAnalysis",
    "CrashStatistics",
    "CrashAnalysisReport",
    "PackageConfig",
    # base_config
    "SYSTEM_LIBRARIES",
    "PLUGIN_LIBRARIES",
    "GERRIT_BASE_URL",
    "GERRIT_API_URL",
    "DEFAULT_WORKSPACE",
    "is_system_library",
    "is_plugin_library",
    # gerrit_client
    "GerritClient",
    "GerritConfig",
    # crash_classifier
    "CrashClassifier",
    "ClassifierConfig",
    # fix_mapper
    "FixMapper",
    "KnownFix",
    # report_generator
    "ReportGenerator",
]
