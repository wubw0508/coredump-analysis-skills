#!/usr/bin/env python3
"""dde-launcher 自动修复元数据。

这里只描述“如何判定 target branch 是否已修复”以及未来可扩展的 auto_fixer 名称。
没有稳定机械修复方案的模式，不声明 auto_fixer。
"""

from typing import Dict


def get_fix_specs() -> Dict[str, Dict]:
    return {
        "app_frame_detected": {
            "symbol_rules": [
                {
                    "symbol_contains": "DDciIconEngine",
                    "fixed_commits": ["b63c6f83", "6be02386"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "b63c6f83",
                    "description": "Dci 图标引擎相关崩溃在 develop/eagle 已有图标加载空值保护修复",
                },
                {
                    "symbol_contains": "QDeepinTheme16createIconEngine",
                    "fixed_commits": ["b63c6f83", "6be02386"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "b63c6f83",
                    "description": "QDeepinTheme 图标引擎创建链路崩溃在 develop/eagle 已有修复",
                },
                {
                    "symbol_contains": "DBuiltinIconEngine8loadIcon",
                    "fixed_commits": ["b63c6f83", "6be02386"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "b63c6f83",
                    "description": "内置图标引擎加载崩溃在 develop/eagle 已有修复",
                },
                {
                    "symbol_contains": "QSvgIOHandlerPrivate4load",
                    "fixed_commits": ["2034c8b5", "d1ee4819"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "2034c8b5",
                    "description": "SVG 读取链路崩溃在 develop/eagle 已有修复",
                },
                {
                    "symbol_contains": "XdgIconProxyEngine13pixmapByEntry",
                    "fixed_commits": ["2034c8b5"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "2034c8b5",
                    "description": "XDG 图标代理渲染链路崩溃在 develop/eagle 已有修复",
                },
                {
                    "symbol_contains": "QPixmap4load",
                    "fixed_commits": ["6be02386", "b63c6f83"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "6be02386",
                    "description": "QPixmap::load 图标加载崩溃在 develop/eagle 已有修复",
                },
                {
                    "symbol_contains": "QPixmapCache4find",
                    "fixed_commits": ["6be02386", "2034c8b5"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "6be02386",
                    "description": "QPixmapCache/XDG 图标缓存链路崩溃在 develop/eagle 已有修复",
                },
                {
                    "symbol_contains": "QTimerInfoList14activateTimers",
                    "fixed_commits": ["15a0f827", "091918c2", "83c2f5cb"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "15a0f827",
                    "description": "全屏定时刷新触发的 DBusDock 元对象访问崩溃在 develop/eagle 已有修复",
                },
                {
                    "symbol_contains_all": [
                        "QMetaObject8activateEP7QObjectiiPPv",
                        "sendPostedEventsEP7QObjectiP11QThreadData",
                    ],
                    "fixed_commits": ["6b9c61fb"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "6b9c61fb",
                    "description": "析构后信号槽悬空导致的 posted events 激活崩溃在 develop/eagle 已有修复",
                },
                {
                    "symbol_contains_all": [
                        "QMetaObject8activateEP7QObjectiiPPv",
                        "sendMouseEventEP7QWidgetP11QMouseEvent",
                    ],
                    "fixed_commits": ["6b9c61fb"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "6b9c61fb",
                    "description": "析构后信号槽悬空导致的鼠标事件激活崩溃在 develop/eagle 已有修复",
                },
                {
                    "symbol_contains": "DNativeSettings14createProperty",
                    "fixed_commits": ["93e0fc36", "71662deb"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "93e0fc36",
                    "description": "平台插件 createProperty 跨线程元对象更新崩溃可映射到 XdgIconLoader 主线程预初始化修复",
                },
                {
                    "symbol_contains": "png_read_row",
                    "fixed_commits": ["d1ee4819"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "d1ee4819",
                    "description": "图像读取健壮性问题在 develop/eagle 已有修复",
                },
            ],
        },
        "qsocketnotifier_event_loop": {
            "fixed_commits": ["e5689752"],
            "auto_fixer": "cherry_pick_known_fix",
            "preferred_commit": "e5689752",
            "description": "QSocketNotifier 生命周期崩溃在 develop/eagle 已有修复提交",
        },
        "qt_event_loop_unknown_symbol": {
            "fixed_commits": ["e5689752"],
            "auto_fixer": "cherry_pick_known_fix",
            "preferred_commit": "e5689752",
            "description": "Qt 事件循环/Notifier 类问题在 develop/eagle 已有对应修复",
        },
        "icon_pixmap_loading": {
            "fixed_commits": ["6be02386", "b63c6f83", "7072174f", "b53a7e69"],
            "auto_fixer": "cherry_pick_known_fix",
            "preferred_commit": "6be02386",
            "description": "图标/位图加载链路在 develop/eagle 已有多次修复",
        },
        "svg_icon_render": {
            "fixed_commits": ["2034c8b5"],
            "auto_fixer": "cherry_pick_known_fix",
            "preferred_commit": "2034c8b5",
            "description": "SVG 图标渲染崩溃在 develop/eagle 已有修复提交",
        },
        "rsvg_icon_render": {
            "fixed_commits": ["2034c8b5"],
            "auto_fixer": "cherry_pick_known_fix",
            "preferred_commit": "2034c8b5",
            "description": "SVG/rsvg 图标渲染崩溃在 develop/eagle 已有修复提交",
        },
        "dbus_warn_abort": {
            "symbol_rules": [
                {
                    "symbol_contains": "_dbus_warn_check_failed",
                    "fixed_commits": ["be28e0f0", "b2a0128e", "dfa8c8da"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "be28e0f0",
                    "description": "冷启动 D-Bus 元对象访问崩溃可映射到 DBusDock 属性缓存修复",
                },
            ],
        },
        "dbus_dispatch_path": {
            "symbol_rules": [
                {
                    "symbol_contains": "dbus_message_get_path_decomposed",
                    "fixed_commits": ["be28e0f0", "b2a0128e", "dfa8c8da"],
                    "auto_fixer": "cherry_pick_known_fix",
                    "preferred_commit": "be28e0f0",
                    "description": "D-Bus 分发/路径解析链路崩溃可映射到 DBusDock 属性缓存修复",
                },
            ],
        },
    }
