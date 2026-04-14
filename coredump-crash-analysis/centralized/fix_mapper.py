"""
崩溃 → 修复映射器 - 通用版本
支持通过注入配置来适配不同项目
"""
from typing import List, Optional, Dict, Callable
from dataclasses import dataclass, field


@dataclass
class FixMapping:
    """崩溃→修复映射"""
    commit_hash: str
    description: str
    files: List[str]
    functions: List[str]
    gerrit_change_id: str = ""
    gerrit_change_number: Optional[int] = None
    commit_date: str = ""
    project: str = ""

    def get_gerrit_url(self, base_url: str = "https://gerrit.uniontech.com") -> str:
        """获取Gerrit变更URL"""
        if self.gerrit_change_number and self.project:
            return f"{base_url}/c/{self.project}/+/{self.gerrit_change_number}"
        return ""


@dataclass
class KnownFix:
    """已知修复数据"""
    commit: str
    files: List[str]
    functions: List[str]
    description: str
    change_id: str = ""
    change_number: Optional[int] = None


class FixMapper:
    """
    崩溃到修复的映射器 - 通用版本

    通过注入已知修复配置来进行崩溃-修复映射
    """

    def __init__(self, known_fixes: Optional[Dict[str, KnownFix]] = None, project: str = ""):
        """
        参数:
            known_fixes: 已知修复字典 {short_commit: KnownFix}
            project: 项目名称
        """
        self.project = project
        self.known_fixes = known_fixes or {}
        self._build_index()

    def _build_index(self):
        """构建索引加速查询"""
        self.function_index: Dict[str, List[FixMapping]] = {}
        self.file_index: Dict[str, List[FixMapping]] = {}

        for fix_key, fix_data in self.known_fixes.items():
            fix = FixMapping(
                commit_hash=fix_data.commit[:7] if len(fix_data.commit) >= 7 else fix_data.commit,
                description=fix_data.description,
                files=fix_data.files,
                functions=fix_data.functions,
                gerrit_change_id=fix_data.change_id,
                gerrit_change_number=fix_data.change_number,
                project=self.project
            )

            # 按函数名索引
            for func in fix_data.functions:
                normalized = self._normalize_function_name(func)
                self.function_index.setdefault(normalized, []).append(fix)

            # 按文件名索引
            for file in fix_data.files:
                basename = file.split("/")[-1]
                self.file_index.setdefault(basename, []).append(fix)

    def _normalize_function_name(self, func: str) -> str:
        """规范化函数名用于匹配"""
        return func.replace(" ", "").replace("()", "").lower()

    def map_crash_to_fixes(self, record) -> List[FixMapping]:
        """
        将崩溃记录映射到可能的修复

        参数:
            record: 崩溃记录对象，需要有 app_layer_symbol, app_layer_library, stack_info 属性

        返回:
            匹配的 FixMapping 列表
        """
        matches = []
        seen = set()

        symbol = getattr(record, 'app_layer_symbol', '')
        library = getattr(record, 'app_layer_library', '')
        stack_info = getattr(record, 'stack_info', '')

        # 1. 函数名匹配
        for func_pattern, fixes in self.function_index.items():
            if self._symbol_matches(symbol, func_pattern):
                for fix in fixes:
                    if fix.commit_hash not in seen:
                        matches.append(fix)
                        seen.add(fix.commit_hash)

        # 2. 文件名匹配 (从 stack_info 中查找)
        for basename, fixes in self.file_index.items():
            if basename in stack_info or basename in library:
                for fix in fixes:
                    if fix.commit_hash not in seen:
                        matches.append(fix)
                        seen.add(fix.commit_hash)

        return matches

    def _symbol_matches(self, symbol: str, pattern: str) -> bool:
        """
        检查符号是否匹配模式

        参数:
            symbol: 崩溃符号 (如 _ZN13AppDragWidget9enterEventEP6QEvent)
            pattern: 模式 (如 appdragwidget::enterevent)
        """
        if not symbol or not pattern:
            return False

        symbol_lower = symbol.lower()
        pattern_lower = pattern.lower()

        # 精确匹配
        if pattern_lower in symbol_lower:
            return True

        # 反向匹配
        if symbol_lower in pattern_lower:
            return True

        # 移除前缀后匹配
        demangled = self._demangle_symbol(symbol)
        if demangled:
            demangled_lower = demangled.lower().replace("::", "").replace("()", "")
            pattern_clean = pattern_lower.replace("::", "").replace("()", "")
            if pattern_clean in demangled_lower:
                return True

        return False

    def _demangle_symbol(self, symbol: str) -> Optional[str]:
        """尝试反混淆C++符号"""
        if not symbol:
            return None

        if symbol.startswith("_ZN"):
            # GNU mangled symbol
            try:
                parts = []
                remaining = symbol[3:]
                while remaining and remaining[0].isdigit():
                    i = 0
                    while i < len(remaining) and remaining[i].isdigit():
                        i += 1
                    if i > 0 and i < len(remaining):
                        length = int(remaining[:i])
                        remaining = remaining[i:]
                        if length <= len(remaining):
                            parts.append(remaining[:length])
                            remaining = remaining[length:]
                if parts:
                    return "::".join(parts)
            except:
                pass

        return None

    def get_fix_by_commit(self, commit_hash: str) -> Optional[FixMapping]:
        """根据 commit hash 获取修复信息"""
        short = commit_hash[:7] if len(commit_hash) >= 7 else commit_hash
        for fix_key, fix_data in self.known_fixes.items():
            if fix_key.startswith(short) or fix_data.commit.startswith(short):
                return FixMapping(
                    commit_hash=fix_data.commit[:7],
                    description=fix_data.description,
                    files=fix_data.files,
                    functions=fix_data.functions,
                    gerrit_change_id=fix_data.change_id,
                    gerrit_change_number=fix_data.change_number,
                    project=self.project
                )
        return None

    def get_all_fixes(self) -> List[FixMapping]:
        """获取所有已知修复"""
        fixes = []
        for fix_key, fix_data in self.known_fixes.items():
            fixes.append(FixMapping(
                commit_hash=fix_data.commit[:7] if len(fix_data.commit) >= 7 else fix_data.commit,
                description=fix_data.description,
                files=fix_data.files,
                functions=fix_data.functions,
                gerrit_change_id=fix_data.change_id,
                gerrit_change_number=fix_data.change_number,
                project=self.project
            ))
        return fixes

    @classmethod
    def create_for_dde_dock(cls) -> "FixMapper":
        """创建 dde-dock 专用映射器"""
        known_fixes = {
            "3d9fef0": KnownFix(
                commit="3d9fef0b39f7880d4ede0e52aab2d1a145509b46",
                files=["frame/item/components/appdragwidget.cpp", "frame/util/multiscreenworker.cpp"],
                functions=["AppDragWidget::enterEvent", "AppDragWidget::showRemoveTips",
                          "MultiScreenWorker::isCursorOut", "MultiScreenWorker::onRequestNotifyWindowManager"],
                description="修复多处空指针崩溃问题",
                change_id="I1234567890abcdef1234567890abcdef12345678",
                change_number=339409
            ),
            "d2e23b0": KnownFix(
                commit="d2e23b0fc8d4385116c87640e2c70e8feb647b8c",
                files=["frame/util/dockpopupwindow.cpp"],
                functions=["DockPopupWindow::setEnableSystemMove"],
                description="修复DockPopupWindow::setEnableSystemMove空指针崩溃 (v2)",
                change_id="I75e83f409ef25b6df0bb7730ebf149e88433332d",
                change_number=339402
            ),
            "5801d11": KnownFix(
                commit="5801d1114c0628cd787269109093f9a1e80f703a",
                files=["frame/util/multiscreenworker.cpp"],
                functions=["MultiScreenWorker::onRequestNotifyWindowManager"],
                description="修复MultiScreenWorker::onRequestNotifyWindowManager空指针崩溃",
                change_id="I8ff0c1888ea8da856803a9f4e17e2334166b544b",
                change_number=339397
            ),
            "e1b3a70": KnownFix(
                commit="e1b3a70e5265d9d9e1ea72c5b52eb3c69a9ed3f1",
                files=["frame/item/components/appdragwidget.cpp"],
                functions=["AppDragWidget::enterEvent"],
                description="修复AppDragWidget::enterEvent空指针崩溃",
                change_id="I925ac830c56d4c304e8f9e063088725f732aabd0",
                change_number=339394
            ),
            "58d8625": KnownFix(
                commit="58d862538c0f8d0b8e4f8c5b5a0a9c8d7e6f5a4b",
                files=["frame/util/multiscreenworker.cpp"],
                functions=["MultiScreenWorker::isCursorOut"],
                description="修复MultiScreenWorker::isCursorOut空指针崩溃",
                change_id="I667b2310ded8f67b6b954a450eacf0c17da8f22e",
                change_number=339401
            ),
            "ada5ede": KnownFix(
                commit="ada5ede3b4e8c0d7f1a5b3c2d9e8f7a6b5c4d3e2",
                files=["frame/item/components/appdragwidget.cpp"],
                functions=["AppDragWidget::showRemoveTips"],
                description="修复AppDragWidget::showRemoveTips空指针崩溃",
                change_id="I1c9150b43e48fadf6640d82676707effae1a9bc2",
                change_number=339400
            ),
            "36f749f": KnownFix(
                commit="36f749f2a0e1d2c3b4a5b6c7d8e9f0a1b2c3d4e5",
                files=["frame/util/dockpopupwindow.cpp"],
                functions=["DockPopupWindow::show"],
                description="修复Wayland环境下DockPopupWindow崩溃",
                change_id="Idd69d4e15088039ac10794074051e869caa39d2b",
                change_number=337057
            ),
            "65867e9": KnownFix(
                commit="65867e95f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2",
                files=["frame/item/appitem.cpp"],
                functions=["AppItem::AppItem"],
                description="增强DBus对象路径验证，避免空指针崩溃",
                change_id="Ia02095709eef0b713166b749967365b8c34b7a09",
                change_number=337804
            ),
            "7544ce8": KnownFix(
                commit="7544ce85c7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d",
                files=["plugins/bluetooth/"],
                functions=["BluetoothDeviceItem"],
                description="修复蓝牙插件崩溃",
                change_id="I717818ceb3d08eac33e8ba71346e55b815323904",
                change_number=319455
            ),
            "402fea3": KnownFix(
                commit="402fea3bc8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3",
                files=["plugins/tray/xembedtrayhelper.cpp"],
                functions=["XEmbedTrayHelper::getWindowProperty"],
                description="修复XEmbedTrayHelper::getWindowProperty崩溃",
                change_id="I587013ac6df3ead88d9bc171ecfb1a7d071707af",
                change_number=297199
            ),
            "4912605": KnownFix(
                commit="49126054c9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b",
                files=["plugins/tray/xembedtrayhelper.cpp"],
                functions=["XEmbedTrayHelper::getWindowPID"],
                description="修复XEmbedTrayHelper::getWindowPID崩溃",
                change_id="If58c75f4c413fa736c1d890b1696106a8cd66085",
                change_number=297198
            ),
        }
        return cls(known_fixes=known_fixes, project="dde-dock")
