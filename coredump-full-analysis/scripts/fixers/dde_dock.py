#!/usr/bin/env python3
"""dde-dock 自动修复元数据。"""

from typing import Dict


APPITEM_CTOR_SYMBOL = "_ZN7AppItemC2EPK10QGSettingsS2_S2_RK15QDBusObjectPathP7QWidget"
APPITEM_CTOR_FRAME = "dde-dock + 0xb504e"
DBUS_INTERNAL_PROP_GET = "_ZN29DBusExtendedAbstractInterface15internalPropGetEPKcPv"
ENTRY_NAME_SYMBOL = "_ZN7__Entry4nameEv"
PLUGIN_LIST_VIEW_DTOR_SYMBOL = "_ZN14PluginListViewD1Ev"
EYE_COMFORT_PLUGIN_LIB = "libeye-comfort-mode.so"
PLUGIN_LIST_VIEW_FIX_COMMIT = "9fa423061fd85bf1c78b2824aa79ff2a36420c0a"
DBUS_CONNECT_SYMBOL = "_ZN15QDBusConnection7connectERK7QStringS2_S2_S2_P7QObjectPKc"
ENTRY_CTOR_SYMBOL = "_ZN7__EntryC1ERK7QStringS2_RK15QDBusConnectionP7QObject"
APPITEM_PATH_GUARD_FIX_COMMIT = "65867e95bdca7c4a17caa8078daea5c2e62e5772"


def get_fix_specs() -> Dict[str, Dict]:
    return {
        "app_frame_detected": {
            "symbol_rules": [
                {
                    "symbol_contains_all": [APPITEM_CTOR_SYMBOL, DBUS_INTERNAL_PROP_GET],
                    "auto_fixer": "apply_appitem_dbus_guard",
                    "target_file": "frame/item/appitem.cpp",
                    "description": "AppItem 构造阶段同步读取 Dock Entry D-Bus 属性崩溃，自动改为直接读取 Properties.Get 并延后窗口/图标初始化",
                    "commit_message_overrides": {
                        "crash_desc": "AppItem 构造阶段读取 Dock Entry 属性崩溃",
                        "root_cause": "AppItem 在构造阶段同步调用 DBusExtendedAbstractInterface::internalPropGet / __Entry::name() 读取 Dock Entry 属性，当 D-Bus 对象或属性回调链路尚未稳定时会触发非法内存访问。",
                        "fix_desc": "改为通过 org.freedesktop.DBus.Properties.Get 读取 Id/IsActive/CurrentWindow 等基础属性，并将 Name、windowInfos 和图标初始化延后到事件循环后执行，规避构造阶段访问未稳定 D-Bus 属性链路。",
                        "log": "基于崩溃分析结果修复 AppItem 构造阶段读取 Dock Entry 属性崩溃",
                        "influence": "请重点验证 dde-dock 应用图标创建、窗口信息刷新、图标刷新以及 Dock Entry D-Bus 属性读取相关路径。",
                    },
                },
                {
                    "symbol_contains_all": [APPITEM_CTOR_SYMBOL, ENTRY_NAME_SYMBOL],
                    "auto_fixer": "apply_appitem_dbus_guard",
                    "target_file": "frame/item/appitem.cpp",
                    "description": "AppItem 构造阶段同步读取 Dock Entry 名称属性崩溃，自动改为直接读取 Properties.Get 并延后窗口/图标初始化",
                    "commit_message_overrides": {
                        "crash_desc": "AppItem 构造阶段读取 Dock Entry 属性崩溃",
                        "root_cause": "AppItem 在构造阶段同步调用 DBusExtendedAbstractInterface::internalPropGet / __Entry::name() 读取 Dock Entry 属性，当 D-Bus 对象或属性回调链路尚未稳定时会触发非法内存访问。",
                        "fix_desc": "改为通过 org.freedesktop.DBus.Properties.Get 读取 Id/IsActive/CurrentWindow 等基础属性，并将 Name、windowInfos 和图标初始化延后到事件循环后执行，规避构造阶段访问未稳定 D-Bus 属性链路。",
                        "log": "基于崩溃分析结果修复 AppItem 构造阶段读取 Dock Entry 属性崩溃",
                        "influence": "请重点验证 dde-dock 应用图标创建、窗口信息刷新、图标刷新以及 Dock Entry D-Bus 属性读取相关路径。",
                    },
                },
                {
                    "symbol_contains_all": [APPITEM_CTOR_FRAME, DBUS_INTERNAL_PROP_GET, ENTRY_NAME_SYMBOL],
                    "auto_fixer": "apply_appitem_dbus_guard",
                    "target_file": "frame/item/appitem.cpp",
                    "description": "AppItem 构造阶段同步读取 Dock Entry 属性崩溃，关键帧未解符号但命中同一 DBus 属性调用链，自动改为直接读取 Properties.Get 并延后窗口/图标初始化",
                    "commit_message_overrides": {
                        "crash_desc": "AppItem 构造阶段读取 Dock Entry 属性崩溃",
                        "root_cause": "AppItem 在构造阶段同步调用 DBusExtendedAbstractInterface::internalPropGet / __Entry::name() 读取 Dock Entry 属性，当 D-Bus 对象或属性回调链路尚未稳定时会触发非法内存访问。",
                        "fix_desc": "改为通过 org.freedesktop.DBus.Properties.Get 读取 Id/IsActive/CurrentWindow 等基础属性，并将 Name、windowInfos 和图标初始化延后到事件循环后执行，规避构造阶段访问未稳定 D-Bus 属性链路。",
                        "log": "基于崩溃分析结果修复 AppItem 构造阶段读取 Dock Entry 属性崩溃",
                        "influence": "请重点验证 dde-dock 应用图标创建、窗口信息刷新、图标刷新以及 Dock Entry D-Bus 属性读取相关路径。",
                    },
                },
                {
                    "symbol_contains_all": [PLUGIN_LIST_VIEW_DTOR_SYMBOL, EYE_COMFORT_PLUGIN_LIB],
                    "fixed_commits": [PLUGIN_LIST_VIEW_FIX_COMMIT],
                    "description": "EyeComfortMode 插件退出阶段 PluginListView 析构崩溃，目标分支已包含 QScroller 清理修复",
                },
                {
                    "symbol_contains_all": [DBUS_CONNECT_SYMBOL, ENTRY_CTOR_SYMBOL],
                    "fixed_commits": [APPITEM_PATH_GUARD_FIX_COMMIT],
                    "description": "AppItem 构造阶段创建 DockEntryInter 命中异常 DBus 路径/接口初始化崩溃，目标分支已包含路径校验与空指针防护修复",
                },
            ],
        },
    }
