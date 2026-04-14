"""
崩溃分类器 - 通用崩溃分类逻辑
识别应用层崩溃 vs 系统库崩溃 vs 插件崩溃
"""
from typing import List, Tuple, Set, Optional
from dataclasses import dataclass, field
from base_config import SYSTEM_LIBRARIES, PLUGIN_LIBRARIES, is_system_library, is_plugin_library


@dataclass
class ClassifierConfig:
    """分类器配置"""
    # 应用层代码模式 (在堆栈中匹配这些模式表示是应用层崩溃)
    app_layer_patterns: List[str] = field(default_factory=list)
    # 应用在堆栈中的标识
    app_name_in_stack: str = ""
    # 额外的系统库（针对特定包）
    extra_system_libs: Set[str] = field(default_factory=set)
    # 额外的插件库
    extra_plugin_libs: Set[str] = field(default_factory=set)


class CrashClassifier:
    """崩溃分类器 - 通用版本"""

    def __init__(self, config: Optional[ClassifierConfig] = None):
        self.config = config or ClassifierConfig()
        self._system_libs = SYSTEM_LIBRARIES | self.config.extra_system_libs
        self._plugin_libs = PLUGIN_LIBRARIES | self.config.extra_plugin_libs

    def classify(self, record) -> str:
        """
        分类崩溃类型

        参数:
            record: CrashRecord 对象或字典

        返回:
            - "app_layer": 应用层崩溃，需要修复
            - "plugin": 插件崩溃，记录但不需要修复主应用
            - "system": 系统库崩溃，不需要修复
        """
        # 支持字典和对象两种方式访问属性
        if isinstance(record, dict):
            library = record.get('App_Layer_Library', '')
            symbol = record.get('App_Layer_Symbol', '')
            stack_info = record.get('StackInfo', '')
        else:
            library = getattr(record, 'app_layer_library', '')
            symbol = getattr(record, 'app_layer_symbol', '')
            stack_info = getattr(record, 'stack_info', '')

        # 1. 检查是否是应用自身 (library == app_name)
        if self._is_app_library(library):
            return "app_layer"

        # 2. 检查StackInfo中是否包含应用相关文件
        if self._is_app_in_stack(record):
            return "app_layer"

        # 3. 检查是否匹配app层模式
        if self._matches_app_pattern(library, symbol):
            return "app_layer"

        # 4. 检查是否是插件
        if self._is_plugin(library):
            return "plugin"

        # 5. 检查是否是系统库
        if self._is_system_library(library):
            return "system"

        # 6. 默认归类为系统库
        return "system"

    def _is_app_library(self, library: str) -> bool:
        """检查是否是应用自身库"""
        if not library:
            return False
        app_name = self.config.app_name_in_stack
        if not app_name:
            return False
        return app_name == library or app_name in library

    def _is_app_in_stack(self, record) -> bool:
        """
        检查堆栈中是否有应用代码

        检查 StackInfo 中是否出现应用相关文件/函数
        """
        # 支持字典和对象两种方式访问属性
        if isinstance(record, dict):
            stack = record.get('StackInfo', '').lower()
        else:
            stack = getattr(record, 'stack_info', '').lower()
        app_name = self.config.app_name_in_stack.lower()

        if not app_name:
            return False

        # 堆栈中常见的格式
        patterns = [
            f"({app_name})",       # 堆栈中常见格式
            f"/{app_name})",       # 另一种格式
        ]

        # 添加应用层代码模式
        for pattern in self.config.app_layer_patterns:
            pattern_lower = pattern.lower()
            if pattern_lower in stack:
                return True
            # 去除命名空间后匹配
            pattern_simple = pattern_lower.replace("::", "").replace("()", "")
            if pattern_simple in stack:
                return True

        # 检查是否包含app名称在堆栈中
        if f"({app_name})" in stack:
            return True

        return False

    def _matches_app_pattern(self, library: str, symbol: str) -> bool:
        """检查是否匹配应用层模式"""
        for pattern in self.config.app_layer_patterns:
            pattern_lower = pattern.lower()
            # 检查库名
            if pattern_lower in library.lower():
                return True
            # 检查符号名
            if pattern_lower in symbol.lower():
                return True
            # 检查去命名空间后的符号
            symbol_simple = symbol.lower().replace("::", "").replace("()", "")
            if pattern_lower in symbol_simple:
                return True
        return False

    def _is_plugin(self, library: str) -> bool:
        """检查是否是插件库"""
        if not library:
            return False
        for plugin in self._plugin_libs:
            if plugin in library:
                return True
        return is_plugin_library(library)

    def _is_system_library(self, library: str) -> bool:
        """检查是否是系统库"""
        if not library:
            return False
        for sys_lib in self._system_libs:
            if sys_lib in library:
                return True
        return is_system_library(library)

    def is_app_layer_crash(self, record) -> bool:
        """判断是否是应用层崩溃"""
        return self.classify(record) == "app_layer"

    def is_system_crash(self, record) -> bool:
        """判断是否是系统库崩溃"""
        return self.classify(record) == "system"

    def is_plugin_crash(self, record) -> bool:
        """判断是否是插件崩溃"""
        return self.classify(record) == "plugin"

    def filter_app_layer_crashes(self, records: List) -> List:
        """过滤出应用层崩溃"""
        return [r for r in records if self.is_app_layer_crash(r)]

    def filter_system_crashes(self, records: List) -> List:
        """过滤出系统库崩溃"""
        return [r for r in records if self.is_system_crash(r)]

    def filter_plugin_crashes(self, records: List) -> List:
        """过滤出插件崩溃"""
        return [r for r in records if self.is_plugin_crash(r)]

    def classify_batch(self, records: List) -> Tuple[List, List, List]:
        """
        批量分类

        返回:
            (app_layer_crashes, system_crashes, plugin_crashes)
        """
        app_layer = []
        system = []
        plugin = []

        for record in records:
            classification = self.classify(record)
            if classification == "app_layer":
                app_layer.append(record)
            elif classification == "system":
                system.append(record)
            else:
                plugin.append(record)

        return app_layer, system, plugin

    @classmethod
    def for_dde_dock(cls) -> "CrashClassifier":
        """创建 dde-dock 专用分类器"""
        return cls(ClassifierConfig(
            app_layer_patterns=[
                "dde-dock", "AppDragWidget", "AppItem", "AppSnapshot",
                "DockPopupWindow", "MultiScreenWorker", "DockApplication",
                "DockItemManager", "PluginsController", "XEmbedTrayHelper"
            ],
            app_name_in_stack="dde-dock"
        ))

    @classmethod
    def for_dde_session_shell(cls) -> "CrashClassifier":
        """创建 dde-session-shell 专用分类器"""
        return cls(ClassifierConfig(
            app_layer_patterns=[
                "dde-session-shell", "SessionWidget", "LoginWidget",
                "SessionManager", "AuthWidget", "UserAvatar"
            ],
            app_name_in_stack="dde-session-shell"
        ))

    @classmethod
    def for_package(cls, package_name: str) -> "CrashClassifier":
        """根据包名创建分类器"""
        if "dde-dock" in package_name:
            return cls.for_dde_dock()
        elif "dde-session-shell" in package_name:
            return cls.for_dde_session_shell()
        else:
            # 通用分类器
            return cls(ClassifierConfig(
                app_layer_patterns=[package_name],
                app_name_in_stack=package_name
            ))
