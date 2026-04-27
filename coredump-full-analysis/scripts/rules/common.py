#!/usr/bin/env python3
"""通用规则与默认文案。"""

from typing import Dict, List


def get_common_patterns() -> List[Dict]:
    return [
        {
            "name": "qt_event_loop_unknown_symbol",
            "match": ["g_main_context_iteration", "libqt5core.so.5:n/a"],
            "fixable": True,
            "reason": "Qt 事件循环链路崩溃，但顶层符号缺失",
            "fix_type": "结合线程/事件退出时序检查对象生命周期",
            "fix_code": "QObject::disconnect(...); thread->quit(); thread->wait();",
            "confidence": "low",
        },
    ]


def get_common_ai_explanations() -> Dict[str, Dict[str, str]]:
    return {
        "app_frame_detected": {
            "analysis": "已命中应用层关键帧。",
            "cause": "堆栈已经落到应用自身代码，当前更适合结合源码、版本和对应符号进一步下钻。",
            "suggestion": "优先检查关键帧附近的对象生命周期、空值保护和跨线程访问。",
            "category": "应用层代码问题",
        },
        "opaque_no_symbols": {
            "analysis": "当前堆栈符号不足，无法直接定位。",
            "cause": "原始 coredump 中可用帧过少，或当前环境缺少对应版本的完整调试符号。",
            "suggestion": "补充原始 coredump、完整 dbgsym 或 build-id 对应的符号文件后再做二次定位。",
            "category": "符号缺失/环境问题",
        },
        "qt_event_loop_unknown_symbol": {
            "analysis": "Qt 事件循环相关崩溃，但顶层符号缺失。",
            "cause": "线程退出或事件循环清理期间访问了已失效对象。",
            "suggestion": "重点检查线程退出、事件循环收尾和 QObject 析构时序。",
            "category": "Qt事件循环",
        },
    }
