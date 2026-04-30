#!/usr/bin/env python3
"""Deterministic root-cause clustering for coredump analysis output."""

import re
from collections import OrderedDict
from typing import Dict, Iterable, List, Tuple

from auto_fix_types import CrashCluster


KNOWN_CLUSTER_RULES: List[Tuple[str, str, str, str, List[str]]] = [
    (
        "appitem-dbus-property-read",
        "AppItem 构造阶段读取 Dock Entry D-Bus 属性崩溃",
        "D-Bus连接/回调生命周期",
        "high",
        ["_ZN7AppItemC2", "DBusExtendedAbstractInterface15internalPropGet"],
    ),
    (
        "pluginlistview-qscroller-dtor",
        "PluginListView 析构阶段 QScroller 资源崩溃",
        "Qt对象生命周期/事件循环",
        "high",
        ["_ZN14PluginListViewD1Ev"],
    ),
    (
        "dock-context-menu-qwindow-dtor",
        "DockContextMenuHelper 析构阶段窗口资源崩溃",
        "Qt对象生命周期/事件循环",
        "medium",
        ["_ZN21DockContextMenuHelperD1Ev"],
    ),
    (
        "dxcb-notitlebar-window-event",
        "dxcb 无标题窗口事件处理崩溃",
        "X11/XCB连接",
        "medium",
        ["DNoTitlebarWindowHelper11windowEvent"],
    ),
    (
        "xrecord-x11-io-error",
        "XRecord 监听线程遇到 X11 IO 异常退出",
        "X11/XCB连接",
        "medium",
        ["XRecordEnableContext"],
    ),
    (
        "dock-application-notify-cast",
        "DockApplication::notify 事件类型转换崩溃",
        "Qt对象生命周期/事件循环",
        "low",
        ["_ZN15DockApplication6notifyEP7QObjectP6QEvent"],
    ),
    (
        "speed-plugin-update-tip",
        "SpeedPlugin 更新提示文本崩溃",
        "Qt对象生命周期/事件循环",
        "low",
        ["_ZN11SpeedPlugin11onUpdateTipEv"],
    ),
    (
        "updater-dbus-watchers-dtor",
        "Updater 析构阶段 D-Bus watcher 映射崩溃",
        "D-Bus连接/回调生命周期",
        "high",
        ["UpdaterD1Ev", "QDBusPendingCallWatcher"],
    ),
    (
        "wallpaper-provider-dtor",
        "WallpaperProvider 析构阶段崩溃",
        "Qt对象生命周期/插件卸载",
        "medium",
        ["WallpaperProviderD0Ev"],
    ),
]


def crash_haystack(crash: Dict) -> str:
    parts = [
        crash.get("pattern_name") or "",
        crash.get("app_layer_symbol") or "",
        crash.get("app_layer_library") or "",
        crash.get("stack_info") or "",
    ]
    key_frame = crash.get("key_frame") or {}
    parts.extend([key_frame.get("symbol") or "", key_frame.get("library") or ""])
    for frame in crash.get("frames") or []:
        parts.extend([frame.get("symbol") or "", frame.get("library") or ""])
    return "\n".join(parts)


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value).strip("-").lower()
    return slug[:80] or "unknown"


def classify_crash(crash: Dict) -> Tuple[str, str, str, str]:
    haystack = crash_haystack(crash)
    haystack_lower = haystack.lower()
    for key, title, category, confidence, tokens in KNOWN_CLUSTER_RULES:
        if all(token.lower() in haystack_lower for token in tokens):
            return key, title, category, confidence

    signal = str(crash.get("signal") or "unknown")
    symbol = crash.get("app_layer_symbol") or crash.get("pattern_name") or "unknown"
    key = f"{signal.lower()}-{slugify(symbol)}"
    title = f"{signal} {symbol} 崩溃"
    category = "未分类保守防护"
    confidence = "low"
    return key, title, category, confidence


def cluster_crashes(package: str, crashes: Iterable[Dict]) -> List[CrashCluster]:
    grouped: "OrderedDict[str, CrashCluster]" = OrderedDict()
    for crash in crashes:
        crash = dict(crash)
        crash.setdefault("count", 1)
        crash.setdefault("version", "unknown")
        key, title, category, confidence = classify_crash(crash)
        cluster_id = f"{package}-{key}"
        if cluster_id not in grouped:
            grouped[cluster_id] = CrashCluster(
                cluster_id=cluster_id,
                package=package,
                key=key,
                title=title,
                category=category,
                confidence=confidence,
                representative_crash=crash,
                crashes=[],
            )
        grouped[cluster_id].crashes.append(crash)

    return sorted(
        grouped.values(),
        key=lambda cluster: (-cluster.total_count, cluster.cluster_id),
    )
