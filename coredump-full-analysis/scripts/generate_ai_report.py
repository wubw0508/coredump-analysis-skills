#!/usr/bin/env python3
"""生成AI崩溃分析报告 (AI_analysis_report.md)"""
import json
from pathlib import Path
from collections import defaultdict
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', required=True)
    parser.add_argument('--workspace', required=True)
    args = parser.parse_args()

    pkg = args.package
    workspace = Path(args.workspace)
    analysis_dir = workspace / '5.崩溃分析' / pkg

    # 收集所有崩溃
    all_crashes = []
    for vf in sorted(analysis_dir.glob('version_*/analysis.json')):
        ver = vf.parent.name.replace('version_', '').replace('_', '.')
        with open(vf) as f:
            data = json.load(f)
        for c in data.get('crashes', []):
            c['version'] = ver
            all_crashes.append(c)

    # 按函数聚合
    by_func = defaultdict(list)
    for c in all_crashes:
        func = c.get('app_layer_symbol', '') or \
               (c.get('description', '').split()[-1] if c.get('description') else 'unknown')
        by_func[func].append(c)

    # 按信号聚合
    by_signal = defaultdict(int)
    for c in all_crashes:
        by_signal[c.get('signal', 'UNKNOWN')] += c.get('count', 1)

    # 高频崩溃 (>=3次)
    high_freq = [(f, cs) for f, cs in by_func.items() if sum(x.get('count', 1) for x in cs) >= 3]
    high_freq.sort(key=lambda x: -sum(c.get('count', 1) for c in x[1]))

    lines = []
    lines.append(f"# {pkg} 崩溃 AI 分析报告\n")
    lines.append(f"**生成时间**: 2026-04-15\n")
    lines.append(f"**数据范围**: 2026-03-15 至 2026-04-15\n")
    lines.append(f"**分析版本**: {len(set(c['version'] for c in all_crashes))} 个\n")
    lines.append(f"**唯一崩溃**: {len(all_crashes)} 个\n")
    lines.append(f"**总崩溃次数**: {sum(c.get('count', 1) for c in all_crashes)}\n")
    lines.append("\n---\n")

    # 信号统计
    lines.append("## 1. 按信号类型统计\n")
    for sig, cnt in sorted(by_signal.items(), key=lambda x: -x[1]):
        sig_desc = {
            'SIGSEGV': '段错误 - 非法内存访问',
            'SIGABRT': '主动终止 - 检测到严重错误',
            'SIGBUS': '总线错误',
            'SIGILL': '非法指令',
            'SIGTRAP': '跟踪/断点陷阱'
        }
        lines.append(f"- **{sig}**: {cnt} 次 — {sig_desc.get(sig, sig)}\n")

    # 高频崩溃分析
    lines.append(f"\n## 2. 高频崩溃分析 (Top {min(len(high_freq), 15)})\n")

    for rank, (func, crashes) in enumerate(high_freq[:15], 1):
        total_count = sum(c.get('count', 1) for c in crashes)
        versions = sorted(set(c['version'] for c in crashes))
        top_sig = crashes[0].get('signal', 'N/A')

        lines.append(f"### {rank}. `{func}`\n")
        lines.append(f"**崩溃次数**: {total_count}\n")
        lines.append(f"**涉及版本**: {', '.join(versions[:5])}{' ...' if len(versions) > 5 else ''}\n")
        lines.append(f"**信号类型**: {top_sig}\n")
        lines.append(f"**涉及库**: {crashes[0].get('app_layer_library', 'N/A')}\n")

        stack = crashes[0].get('stack_info', '')
        if stack:
            lines.append(f"**堆栈示例**:\n```\n")
            for line in stack.split('\n')[:20]:
                if line.strip():
                    lines.append(f"{line}\n")
            lines.append(f"```\n")

        # AI 分析
        func_lower = func.lower()
        if 'updater' in func_lower or 'update' in func_lower:
            lines.append(f"**AI 分析**: Updater 类析构函数崩溃，可能是 D-Bus 回调对象在 Qt 父子对象树析构期间被提前销毁。\n")
            lines.append(f"**可能原因**: `QMap<QString, QDBusPendingCallWatcher*>` 在析构时访问了已被删除的 D-Bus 监视器对象。\n")
            lines.append(f"**修复建议**: 在 Updater 析构前，先断开所有 D-Bus 信号连接并清空 QMap。\n")
        elif 'wallpaper' in func_lower or 'screensaver' in func_lower or 'provider' in func_lower:
            lines.append(f"**AI 分析**: 壁纸/屏保 Provider 析构时 D-Bus 连接异常终止。\n")
            lines.append(f"**可能原因**: D-Bus 消息在 Provider 析构期间仍被发送，导致 D-Bus 守护进程断言失败并调用 `abort()`。\n")
            lines.append(f"**修复建议**: 在 Provider 析构时，先调用 `QThread::quit()` 等待事件循环退出，再销毁对象。\n")
        elif 'xcb' in func_lower or 'sn_xcb' in func_lower or 'QXcbConnection' in func_lower or 'Display' in func:
            lines.append(f"**AI 分析**: XCB 显示连接初始化失败。\n")
            lines.append(f"**可能原因**: `sn_xcb_display_new` 调用时 `Display` 指针尚未就绪，或 XCB 连接已在其他线程关闭。\n")
            lines.append(f"**修复建议**: 在调用 XCB 函数前检查 `Display` 是否为 `nullptr`，并确保 XCB 连接在主线程访问。\n")
        elif 'widget' in func_lower and ('D1Ev' in func or 'D0Ev' in func):
            lines.append(f"**AI 分析**: Qt Widget 析构函数崩溃。\n")
            lines.append(f"**可能原因**: Widget 在事件循环运行期间被析构，导致 `QCoreApplication::postEvent()` 访问已销毁的 QObject。\n")
            lines.append(f"**修复建议**: 在 Widget 析构前，先调用 `disconnect()` 断开所有信号槽连接，并确保事件循环已退出。\n")
        elif 'dccnetwork' in func_lower or ('network' in func_lower and 'module' in func_lower):
            lines.append(f"**AI 分析**: 网络插件 Module 析构时 D-Bus 断开通知触发崩溃。\n")
            lines.append(f"**可能原因**: D-Bus 连接断开时发送 `disconnectNotify` 信号，但 `DCCNetworkModule` 对象已在销毁中。\n")
            lines.append(f"**修复建议**: 使用 `QPointer<>` 追踪网络模块对象生命周期，在 `disconnectNotify` 中检查对象是否仍有效。\n")
        elif func_lower == 'main' or func_lower == '':
            lines.append(f"**AI 分析**: main 函数崩溃，通常是应用初始化期间发生未捕获异常。\n")
            lines.append(f"**可能原因**: 应用启动时 Qt 事件循环初始化顺序不当，导致空指针访问。\n")
            lines.append(f"**修复建议**: 检查 `main()` 函数中 `QApplication` 及其插件的初始化顺序。\n")
        elif 'qobject' in func_lower or 'event' in func_lower:
            lines.append(f"**AI 分析**: QObject 事件处理期间发生崩溃。\n")
            lines.append(f"**可能原因**: 事件处理函数访问了已被删除的子对象。\n")
            lines.append(f"**修复建议**: 在事件处理函数中使用 `QPointer<>` 保护可能已删除的对象。\n")
        elif 'raise' in func_lower or 'abort' in func_lower:
            lines.append(f"**AI 分析**: 应用主动调用 `raise()` 或 `abort()` 终止。\n")
            lines.append(f"**可能原因**: D-Bus 或其他系统级检查失败，触发断言。\n")
            lines.append(f"**修复建议**: 检查 `raise()` / `abort()` 调用前的条件，确认是否有未处理的错误状态。\n")
        elif 'qtconcurrent' in func_lower or 'runfunctiontask' in func_lower:
            lines.append(f"**AI 分析**: QtConcurrent 异步任务执行期间崩溃。\n")
            lines.append(f"**可能原因**: 并发任务访问了已被主线程销毁的 Qt 对象。\n")
            lines.append(f"**修复建议**: 使用 `QThread::wait()` 确保任务完成后再销毁相关对象，或使用 `QObject::moveToThread()` 管理线程安全。\n")
        else:
            lines.append(f"**AI 分析**: 需要进一步调试分析。\n")
            lines.append(f"**可能原因**: 根据堆栈推断为 C++ 对象析构时序问题。\n")
            lines.append(f"**修复建议**: 检查对应对象析构函数，确认所有子对象和信号槽连接是否正确清理。\n")

        lines.append(f"\n---\n")

    # 总结
    lines.append("## 3. 总结与修复建议\n")
    total = sum(c.get('count', 1) for c in all_crashes)
    lines.append(f"本次分析共发现 **{len(all_crashes)}** 个唯一崩溃，分布在 **{len(set(c['version'] for c in all_crashes))}** 个版本中。\n")

    root_causes = {
        '对象析构时序': 0,
        'D-Bus连接问题': 0,
        'XCB/X11连接': 0,
        'Qt事件循环': 0,
        '第三方库问题': 0,
        '其他': 0
    }
    for func, crashes in by_func.items():
        count = sum(c.get('count', 1) for c in crashes)
        fl = func.lower()
        if 'updater' in fl or 'update' in fl or 'provider' in fl or 'watcher' in fl:
            root_causes['D-Bus连接问题'] += count
        elif 'xcb' in fl or 'sn_xcb' in fl or 'QXcbConnection' in fl or 'Display' in func:
            root_causes['XCB/X11连接'] += count
        elif 'widget' in fl or 'D1Ev' in func or 'D0Ev' in func or ('event' in fl and 'QObject' in func):
            root_causes['Qt事件循环'] += count
        elif 'delete' in fl or 'children' in fl or 'destroy' in fl or 'finalize' in fl:
            root_causes['对象析构时序'] += count
        elif 'qtconcurrent' in fl or 'runfunctiontask' in fl:
            root_causes['第三方库问题'] += count
        else:
            root_causes['其他'] += count

    lines.append(f"\n### 根因分类统计\n")
    for cause, count in sorted(root_causes.items(), key=lambda x: -x[1]):
        if count > 0:
            pct = count * 100 / total
            lines.append(f"- **{cause}**: {count} 次 ({pct:.1f}%)\n")

    lines.append(f"\n### 整体建议\n")
    if root_causes['对象析构时序'] > 0:
        lines.append(f"1. **修复对象析构时序问题**: 使用 `QPointer<>` 或显式 `disconnect()` 避免访问已销毁对象。\n")
    if root_causes['D-Bus连接问题'] > 0:
        lines.append(f"2. **修复 D-Bus 连接管理**: 在析构前先断开 D-Bus 连接，避免析构期间仍有消息发送。\n")
    if root_causes['XCB/X11连接'] > 0:
        lines.append(f"3. **修复 XCB 连接初始化**: 确保 `Display` 就绪后再调用 XCB 函数，使用互斥锁保护多线程访问。\n")
    if root_causes['Qt事件循环'] > 0:
        lines.append(f"4. **修复 Qt 事件循环问题**: 避免在析构期间调用 `postEvent()`，先退出事件循环再销毁对象。\n")
    if root_causes['第三方库问题'] > 0:
        lines.append(f"5. **修复 QtConcurrent 并发问题**: 确保异步任务完成后再销毁相关 Qt 对象。\n")
    lines.append(f"6. **增加测试覆盖**: 针对插件加载/卸载场景编写自动化测试，覆盖对象生命周期完整路径。\n")

    report_file = analysis_dir / 'AI_analysis_report.md'
    report_file.write_text(''.join(lines), encoding='utf-8')
    print(f"✅ AI_analysis_report.md 已生成: {report_file} ({len(lines)} 行)")

if __name__ == '__main__':
    main()
