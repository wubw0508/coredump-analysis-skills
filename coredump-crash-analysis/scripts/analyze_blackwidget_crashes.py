#!/usr/bin/env python3
"""
dde-blackwidget 专项崩溃分析脚本

输入:
- 一份包含 dde-session-ui 崩溃记录的 CSV
- 或一个包含多份 CSV 的目录

输出:
- dde-blackwidget 专用记录集
- 签名汇总
- 低频记录清单
- 签名分层结果
- 最终问题清单
"""

import argparse
import csv
import glob
import os
import re
from collections import Counter, defaultdict


def get_field(row, field_name):
    if field_name in row:
        return row[field_name]
    for key, value in row.items():
        if key.lower() == field_name.lower():
            return value
    return ""


def row_text(row):
    return "\n".join(str(value) for value in row.values()).lower()


def is_blackwidget_row(row):
    return "dde-blackwidget" in row_text(row)


def classify_stack(stack_info):
    text = (stack_info or "").lower()
    if "qxcbconnection10internatom" in text or "initializeallatoms" in text or "getedid" in text:
        return "XCB atom/screen init"
    if "dplatformintegration10initialize" in text or "xcbnativeeventfilter" in text:
        return "Dtk dxcb platform init"
    if "atspibus" in text or "xcb_get_property_value_length" in text:
        return "AT-SPI / xcb property"
    if "raise (libc.so.6)" in text or "abort (libc.so.6)" in text or "__gi_abort" in text:
        return "Abort path"
    if "ld-linux-x86-64.so.2" in text:
        return "Loader/runtime init"
    if "radeonsi_dri.so" in text or "libllvm-7.so.1" in text:
        return "Mesa/LLVM graphics"
    if "qmetaobjectbuilder" in text or "dnativesettings" in text or "dxcbxsettings" in text:
        return "dxcb teardown/metaobject"
    if "dde-blackwidget" in text:
        return "Other blackwidget path"
    return "Other/unknown"


def build_signature(stack_info, frame_limit=5):
    parts = []
    for line in (stack_info or "").splitlines():
        match = re.match(r"\s*#\s*\d+\s+0x[0-9a-f]+\s+(\S+)\s+\(([^)]+)\)", line)
        if match:
            parts.append(f"{match.group(2)}:{match.group(1)}")
        if len(parts) >= frame_limit:
            break
    return "|".join(parts) or "NO_STACK"


def parse_counter_string(value):
    result = Counter()
    for item in [part for part in (value or "").split("; ") if part]:
        if ":" not in item:
            continue
        name, count = item.split(":", 1)
        try:
            result[name] += int(count)
        except ValueError:
            continue
    return result


def triage_signature(category, signature, sample_stack):
    text = f"{signature}\n{sample_stack}".lower()
    if category in ("Dtk dxcb platform init", "XCB atom/screen init", "AT-SPI / xcb property"):
        return (
            "未修复主问题",
            "黑屏程序启动过早，进入 Qt/Xcb/Dtk 平台初始化链；首帧虽在系统库，但触发点在 dde-blackwidget 启动/建窗流程。",
            "增加启动前置检查、延迟初始化或规避 Xcb/AT-SPI 访问；重点对照 main()、Window 构造、平台窗口初始化。",
        )

    if category in ("Abort path", "dxcb teardown/metaobject"):
        return (
            "已有修复关联",
            "退出/析构阶段资源释放时序异常，涉及鼠标键盘抓取、窗口属性、DNativeSettings/DXcbXSettings 析构。",
            "重点关联 4260bb60；继续评估是否还需补充释放顺序或幂等保护。",
        )

    if category == "Other blackwidget path":
        if any(token in text for token in ("qaccessible", "qapplicationd2ev", "qt_call_post_routines", "exit", "__cxa_finalize")):
            return (
                "已有修复关联",
                "大概率属于退出阶段对象树/可访问性/窗口资源清理问题。",
                "关联 4260bb60；核对 cleanupBeforeExit 是否覆盖全部退出路径。",
            )
        if any(token in text for token in ("qxcbscreend1ev", "qxcbscreend0ev", "qxcbconnectiond1ev", "vtablehook15autocleanvtable")):
            return (
                "可归并到退出时序问题",
                "Xcb screen/connection 销毁链异常，属于 Qt/Xcb/dxcb 退出清理路径。",
                "并入析构时序问题，结合 4260bb60 和 DXcbXSettings/DNativeSettings 析构链继续看。",
            )
        if any(token in text for token in ("libdbus-1.so.3", "libqt5dbus.so.5", "dbus_connection_dispatch", "_dbus_warn_check_failed")):
            return (
                "可归并到退出时序问题",
                "DBus 消息分发/注销阶段异常，较大概率与黑屏服务注册/注销和退出时序有关。",
                "并入 cleanupBeforeExit/quitDBusService 相关问题，补查 DBus 注册对象、serviceUnregistered 回调与退出顺序。",
            )
        if any(token in text for token in ("qeventdispatcherglib", "g_main_context_iteration", "g_main_loop_run")):
            return (
                "可归并到事件循环时序问题",
                "GLib/Qt 事件分发器运行或销毁阶段异常，通常发生在应用退出或线程唤醒期间。",
                "并入退出时序问题，检查 quit、postEvent、timer、DBus 回调的收尾顺序。",
            )
        if "dde-blackwidget + 0x" in text:
            return (
                "待进一步定位",
                "命中 blackwidget 本体偏移，但当前仍需结合版本代码进一步映射到具体函数。",
                "优先结合本地 tag 和 objdump/nm 做偏移到函数映射。",
            )
        return (
            "待进一步定位",
            "位于 blackwidget/Qt 窗口链，但证据不足以直接归到单一根因。",
            "结合版本 tag 对照 Window::raiseWindow/event/cleanupBeforeExit 等路径。",
        )

    if category in ("Loader/runtime init", "Mesa/LLVM graphics"):
        return (
            "环境/外部依赖",
            "更偏运行时装载器或图形驱动栈异常，不像 blackwidget 业务代码单点故障。",
            "保留逐条记录，单独评估系统环境、驱动、图形栈版本。",
        )

    if any(token in text for token in ("libdbus-1.so.3", "libqt5dbus.so.5", "dbus_connection_dispatch", "_dbus_warn_check_failed")):
        return (
            "可归并到退出时序问题",
            "DBus 消息分发/注销阶段异常，较大概率与黑屏服务注册/注销和退出时序有关。",
            "并入 cleanupBeforeExit/quitDBusService 相关问题，补查 DBus 注册对象、serviceUnregistered 回调与退出顺序。",
        )

    if any(token in text for token in ("qeventdispatcherglib", "g_main_context_iteration", "g_main_loop_run")):
        return (
            "可归并到事件循环时序问题",
            "GLib/Qt 事件分发器运行或销毁阶段异常，通常发生在应用退出或线程唤醒期间。",
            "并入退出时序问题，检查 quit、postEvent、timer、DBus 回调的收尾顺序。",
        )

    if any(token in text for token in ("n/a + 0x0:n/a", "n/a:n/a")):
        return (
            "信息不足待保留",
            "堆栈信息残缺，当前只能保留记录与版本归属。",
            "后续如能补齐对应 coredump 或符号，再单独回补。",
        )

    if any(token in text for token in ("libglx_mesa.so.0", "libxcb-keysyms.so.1", "g_type_register_static", "xkb_x11_keymap_new_from_device")):
        return (
            "环境/外部依赖",
            "更接近图形栈/X11 输入法或系统库环境问题。",
            "单独记录环境依赖，不优先归到 blackwidget 主逻辑修复。",
        )

    if "dbus" in text or "xcb_wait_for_event" in text:
        return (
            "待进一步定位",
            "事件循环/DBus 分发或注销阶段异常，可能与退出时序相关。",
            "补充对 DBus 注册、注销、serviceUnregistered 回调的时序检查。",
        )

    return (
        "待定",
        "当前只能确认发生在外围系统库或运行时栈中。",
        "保留记录，后续按版本或环境聚类继续分析。",
    )


def review_remaining_signatures(signature_rows):
    main_hint = "黑屏程序启动过早，进入 Qt/Xcb/Dtk 平台初始化链；首帧虽在系统库，但触发点在 dde-blackwidget 启动/建窗流程。"
    main_fix = "增加启动前置检查、延迟初始化或规避 Xcb/AT-SPI 访问；重点对照 main()、Window 构造、平台窗口初始化。"
    env_hint = "崩溃主栈位于图形驱动、EGL/GLX 或外部运行时组件，dde-blackwidget 更可能只是触发者而非根因。"
    env_fix = "优先按显卡驱动/图形栈兼容性处理；保留版本和驱动信息，必要时规避特定图形后端。"
    dbus_hint = "崩溃栈落在 GLib/GIO/DBus 分发或序列化路径，倾向于事件循环或退出收尾时序问题。"
    dbus_fix = "重点核对 DBus 注销、对象销毁和事件循环退出顺序，避免退出阶段继续发送/处理消息。"
    paint_hint = "崩溃已进入 blackwidget 自身绘制路径，典型落在 QWidget 背景绘制和 QRasterPaintEngine::fillRect，触发点与 paintBackground()/setupSize()/show 流程相关。"
    paint_fix = "减少启动阶段重复 show/resize/style 操作，优先在窗口就绪后一次性设置尺寸和背景；继续核对 paintBackground、setupSize 和首帧显示顺序。"
    exit_hint = "崩溃栈命中 main() 局部对象析构或 QWidget/QObject/QGSettings 退出销毁链，更像应用退出阶段的对象生命周期问题。"
    exit_fix = "继续收紧 cleanupBeforeExit 与 main() 尾部对象析构顺序，减少退出阶段的 DBus/GSettings/窗口对象交叉销毁。"
    reviewable_statuses = {"待进一步定位", "待定", "信息不足待保留"}
    changed_rows = []

    for row in signature_rows:
        if row["status"] not in reviewable_statuses:
            continue

        text = f"{row['signature']}\n{row['sample_stack']}".lower()
        original = (row["category"], row["status"], row["root_cause_hint"], row["fix_hint"])

        if "qmessagelogger5fatal" in text and "createplatformintegration" in text:
            row["category"] = "Dtk dxcb platform init"
            row["status"] = "未修复主问题"
            row["root_cause_hint"] = main_hint
            row["fix_hint"] = main_fix
        elif "getselectionowner" in text and "initializescreens" in text:
            row["category"] = "XCB atom/screen init"
            row["status"] = "未修复主问题"
            row["root_cause_hint"] = main_hint
            row["fix_hint"] = main_fix
        elif any(token in text for token in (
            "qrasterpaintengine8fillrect",
            "qpainter8fillrect",
            "qwidgetprivate15paintbackground",
        )):
            row["category"] = "Window background paint"
            row["status"] = "未修复主问题"
            row["root_cause_hint"] = paint_hint
            row["fix_hint"] = paint_fix
        elif any(token in text for token in (
            "qgsettingsd2ev",
            "qcommandlineparserd1ev",
            "qobjectd2ev",
            "qwidgetd2ev",
        )) and "__libc_start_main" in text:
            row["status"] = "可归并到退出时序问题"
            row["root_cause_hint"] = exit_hint
            row["fix_hint"] = exit_fix
        elif "malloc_printerr" in text or "_int_free" in text:
            row["status"] = "可归并到退出时序问题"
            row["root_cause_hint"] = exit_hint
            row["fix_hint"] = "优先排查退出阶段对象重复释放、异步回调晚到和 grab/release 交叉调用；重点核对 cleanupBeforeExit、QObject 析构与 DBus/GSettings 清理。"
        elif all(token in text for token in ("raise", "abort", "libc.so.6 + 0x79968")) or "libc.so.6 + 0x7fec8" in text:
            row["status"] = "可归并到退出时序问题"
            row["root_cause_hint"] = exit_hint
            row["fix_hint"] = "这类栈仍表现为 libc 内存错误/主动 abort，优先按退出阶段对象重复释放和收尾重入处理。"
        elif "dde-blackwidget" in text and "__libc_start_main" in text:
            row["status"] = "可归并到退出时序问题"
            row["root_cause_hint"] = exit_hint
            row["fix_hint"] = exit_fix
        elif any(token in text for token in (
            "qmapdatabase8freetree",
            "qmetatype7destroy",
            "qmetaobject8activate",
            "qobject9destroyed",
            "qobjectd2ev",
            "qwidgetd2ev",
            "dplatformthemed0ev",
            "dguiapplicationhelperd1ev",
        )):
            row["status"] = "可归并到退出时序问题"
            row["root_cause_hint"] = exit_hint
            row["fix_hint"] = exit_fix
        elif any(token in text for token in (
            "ld-2.28.so",
            "ld-linux-x86-64.so.2",
            "libfcitxplatforminputcontextplugin.so",
            "g_settings_backend_get_default",
            "libgpg-error.so.0",
        )):
            row["status"] = "环境/外部依赖"
            row["root_cause_hint"] = env_hint
            row["fix_hint"] = env_fix
        elif any(token in text for token in (
            "handlexcbevent",
            "processxcbevents",
            "handlepropertynotifyevent",
            "handleexposeevent",
            "updatescreens",
            "filternativeevent",
            "xcb_wait_for_event",
            "qapplicationprivate13notify_helper",
            "qapplication6notify",
            "sendthroughobjecteventfilters",
            "notifyinternal2",
        )):
            row["status"] = "可归并到事件循环时序问题"
            row["root_cause_hint"] = "崩溃位于 Xcb 事件分发和窗口事件处理链，倾向于窗口事件循环或退出收尾阶段的时序问题。"
            row["fix_hint"] = "继续核对 raiseWindow、WindowDeactivate、输入抓取和窗口属性变更后触发的 Xcb 事件回流。"
        elif any(token in text for token in (
            "libdconfsettings.so",
            "g_assertion_message_expr",
            "g_settings_backend_get_default",
            "g_dbus_connection_call",
            "g_dbus_message_new_method_call",
            "g_type_check_instance_is_a",
            "g_weak_ref_set",
        )):
            row["status"] = "环境/外部依赖"
            row["root_cause_hint"] = "崩溃栈更接近 dconf/gsettings/glib 运行时断言或后端访问问题，blackwidget 更像触发者而不是唯一根因。"
            row["fix_hint"] = "单独记录环境和配置后端信息，优先按 dconf/gsettings/glib 兼容性与运行时状态处理。"
        elif any(token in text for token in (
            "g_hash_table_lookup",
            "g_str_equal",
            "g_quark_try_string",
            "g_signal_connect_data",
            "g_param_spec_pool_lookup",
            "g_object_notify",
        )):
            row["status"] = "环境/外部依赖"
            row["root_cause_hint"] = "崩溃栈主要落在 glib/gobject 类型系统和信号连接链，更偏运行时环境或库内部状态异常。"
            row["fix_hint"] = "保留环境依赖归档，必要时结合 glib/gsettings 版本和线程收尾路径继续排查。"
        elif any(token in text for token in (
            "pthread_cond_wait",
            "_pthread_cleanup_pop",
            "__nptl_deallocate_tsd",
            "start_thread",
            "__clone",
        )):
            row["status"] = "环境/外部依赖"
            row["root_cause_hint"] = "崩溃栈停留在线程回收或等待链，缺少直接应用层证据，更偏线程/运行时收尾问题。"
            row["fix_hint"] = "作为线程收尾型尾部问题保留，优先结合环境、线程模型和退出阶段日志继续看。"
        elif any(token in text for token in (
            "xcb-randr.so.0",
            "xcb_poll_for_queued_event",
        )):
            row["status"] = "可归并到事件循环时序问题"
            row["root_cause_hint"] = "崩溃栈位于 Xcb randr/poll 事件处理链，倾向于屏幕资源刷新或窗口事件循环时序异常。"
            row["fix_hint"] = "并入 Xcb 事件循环问题，重点结合 initializeScreens、updateScreens 和窗口拉起时序继续看。"
        elif any(token in text for token in (
            "libglx_nvidia.so.0",
            "libnvidia-glcore",
            "libegl_mwv207.so.0",
            "libglx_mesa.so.0",
            "libegl.so.1",
            "libqxcb-egl-integration.so",
        )):
            row["category"] = "Mesa/LLVM graphics"
            row["status"] = "环境/外部依赖"
            row["root_cause_hint"] = env_hint
            row["fix_hint"] = env_fix
        elif any(token in text for token in ("g_dbus_message_to_blob", "g_io_stream_get_output_stream", "dbus_bus_remove_match")):
            row["status"] = "可归并到事件循环时序问题"
            row["root_cause_hint"] = dbus_hint
            row["fix_hint"] = dbus_fix

        updated = (row["category"], row["status"], row["root_cause_hint"], row["fix_hint"])
        if updated != original:
            changed_rows.append(row.copy())

    return signature_rows, changed_rows


def build_remaining_review(output_dir, original_rows, reviewed_rows, changed_rows):
    before = Counter(row["status"] for row in original_rows)
    after = Counter(row["status"] for row in reviewed_rows)
    path = os.path.join(output_dir, "remaining_issue_review_v3.md")
    with open(path, "w", encoding="utf-8") as file_obj:
        file_obj.write("# Remaining Issue Review V3\n\n")
        file_obj.write(f"- reviewed_signatures: {len(reviewed_rows)}\n")
        file_obj.write(f"- reclassified_signatures: {len(changed_rows)}\n")
        file_obj.write(f"- reclassified_records: {sum(int(row['count']) for row in changed_rows)}\n\n")
        file_obj.write("## Status Delta\n")
        for status in sorted(set(before) | set(after)):
            file_obj.write(f"- {status}: {before[status]} -> {after[status]}\n")
        file_obj.write("\n## Reclassified Samples\n")
        for row in sorted(changed_rows, key=lambda item: (-int(item["count"]), item["status"], item["category"]))[:20]:
            file_obj.write(f"- {row['count']} | {row['status']} | {row['category']} | {row['version_top']}\n")
            file_obj.write(f"  {row['signature'][:260]}\n")
    return path


def write_csv(path, fieldnames, rows):
    with open(path, "w", newline="", encoding="utf-8-sig") as file_obj:
        writer = csv.DictWriter(file_obj, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def resolve_input_files(csv_path):
    if os.path.isdir(csv_path):
        files = sorted(glob.glob(os.path.join(csv_path, "**", "*.csv"), recursive=True))
        filtered = []
        for path in files:
            if not os.path.isfile(path):
                continue
            name = os.path.basename(path).lower()
            if "blackwidget" in name:
                continue
            if "crash" not in name:
                continue
            filtered.append(path)
        return filtered
    if os.path.isfile(csv_path):
        return [csv_path]
    return []


def aggregate_actionable(rows):
    keep_statuses = {
        "未修复主问题",
        "已有修复关联",
        "可归并到退出时序问题",
        "可归并到事件循环时序问题",
        "待进一步定位",
    }
    groups = defaultdict(lambda: {
        "count": 0,
        "versions": Counter(),
        "signals": Counter(),
        "sample": None,
        "signatures": 0,
    })

    for row in rows:
        if row["status"] not in keep_statuses:
            continue
        key = (row["category"], row["status"], row["root_cause_hint"], row["fix_hint"])
        group = groups[key]
        group["count"] += int(row["count"])
        group["versions"].update(parse_counter_string(row["version_top"]))
        group["signals"].update(parse_counter_string(row["signal_top"]))
        group["signatures"] += 1
        if group["sample"] is None or int(row["count"]) > int(group["sample"]["count"]):
            group["sample"] = row

    output_rows = []
    for (category, status, cause, fix), group in sorted(groups.items(), key=lambda item: (-item[1]["count"], item[0][1], item[0][0])):
        if status == "未修复主问题":
            priority = "P1"
        elif status in ("已有修复关联", "可归并到退出时序问题", "可归并到事件循环时序问题"):
            priority = "P2"
        else:
            priority = "P3"
        sample = group["sample"]
        output_rows.append({
            "priority": priority,
            "category": category,
            "status": status,
            "signatures": group["signatures"],
            "records": group["count"],
            "version_top": "; ".join(f"{key}:{value}" for key, value in group["versions"].most_common(6)),
            "signal_top": "; ".join(f"{key}:{value}" for key, value in group["signals"].most_common(4)),
            "sample_version": sample["sample_version"],
            "sample_sig": sample["sample_sig"],
            "sample_id": sample["sample_id"],
            "root_cause_hint": cause,
            "fix_hint": fix,
            "sample_signature": sample["signature"],
        })
    return output_rows


def aggregate_retained(rows):
    keep_statuses = {"环境/外部依赖", "信息不足待保留", "待定"}
    groups = defaultdict(lambda: {
        "count": 0,
        "versions": Counter(),
        "signals": Counter(),
        "sample": None,
        "signatures": 0,
    })

    for row in rows:
        if row["status"] not in keep_statuses:
            continue
        key = (row["category"], row["status"], row["root_cause_hint"], row["fix_hint"])
        group = groups[key]
        group["count"] += int(row["count"])
        group["versions"].update(parse_counter_string(row["version_top"]))
        group["signals"].update(parse_counter_string(row["signal_top"]))
        group["signatures"] += 1
        if group["sample"] is None or int(row["count"]) > int(group["sample"]["count"]):
            group["sample"] = row

    output_rows = []
    for (category, status, cause, fix), group in sorted(groups.items(), key=lambda item: (-item[1]["count"], item[0][1], item[0][0])):
        sample = group["sample"]
        output_rows.append({
            "category": category,
            "status": status,
            "signatures": group["signatures"],
            "records": group["count"],
            "version_top": "; ".join(f"{key}:{value}" for key, value in group["versions"].most_common(6)),
            "signal_top": "; ".join(f"{key}:{value}" for key, value in group["signals"].most_common(4)),
            "sample_version": sample["sample_version"],
            "sample_sig": sample["sample_sig"],
            "sample_id": sample["sample_id"],
            "root_cause_hint": cause,
            "fix_hint": fix,
            "sample_signature": sample["signature"],
        })
    return output_rows


def build_markdown_summary(output_dir, actionable_rows, retained_rows):
    path = os.path.join(output_dir, "final_issue_summary.md")
    with open(path, "w", encoding="utf-8") as file_obj:
        file_obj.write("# dde-blackwidget 问题清单\n\n")
        file_obj.write("## 可行动问题\n")
        for row in actionable_rows:
            file_obj.write(
                f"- {row['priority']} | {row['records']} 条 | {row['signatures']} 个签名 | "
                f"{row['status']} | {row['category']}\n"
            )
            file_obj.write(f"  版本: {row['version_top']}\n")
            file_obj.write(f"  信号: {row['signal_top']}\n")
            file_obj.write(f"  原因: {row['root_cause_hint']}\n")
            file_obj.write(f"  建议: {row['fix_hint']}\n")

        file_obj.write("\n## 保留问题\n")
        for row in retained_rows:
            file_obj.write(
                f"- {row['records']} 条 | {row['signatures']} 个签名 | {row['status']} | {row['category']}\n"
            )
            file_obj.write(f"  版本: {row['version_top']}\n")
            file_obj.write(f"  信号: {row['signal_top']}\n")
            file_obj.write(f"  原因: {row['root_cause_hint']}\n")
            file_obj.write(f"  建议: {row['fix_hint']}\n")
    return path


def main():
    parser = argparse.ArgumentParser(description="dde-blackwidget 专项崩溃分析")
    parser.add_argument("--csv", required=True, help="输入 CSV 文件路径，或包含多份 CSV 的目录")
    parser.add_argument("--output-dir", required=True, help="输出目录")
    parser.add_argument("--slice-label", default="", help="可选来源标签")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    input_files = resolve_input_files(args.csv)
    if not input_files:
        raise SystemExit(f"未找到可用 CSV: {args.csv}")

    all_rows = []
    fieldnames = []
    for csv_file in input_files:
        with open(csv_file, newline="", encoding="utf-8-sig") as file_obj:
            reader = csv.DictReader(file_obj)
            if not fieldnames:
                fieldnames = list(reader.fieldnames or [])
                if "SourceSlice" not in fieldnames:
                    fieldnames.append("SourceSlice")
            for row in reader:
                if not is_blackwidget_row(row):
                    continue
                row["SourceSlice"] = get_field(row, "SourceSlice") or args.slice_label or os.path.basename(csv_file)
                row["_signature"] = build_signature(get_field(row, "StackInfo"))
                row["_category"] = classify_stack(get_field(row, "StackInfo"))
                all_rows.append(row)

    dataset_path = os.path.join(args.output_dir, "dde-blackwidget_all_records.csv")
    write_csv(dataset_path, fieldnames, [{key: row.get(key, "") for key in fieldnames} for row in all_rows])

    signature_counts = Counter(row["_signature"] for row in all_rows)

    signature_agg = {}
    for row in all_rows:
        signature = row["_signature"]
        item = signature_agg.setdefault(signature, {
            "signature": signature,
            "category": row["_category"],
            "count": 0,
            "signals": Counter(),
            "versions": Counter(),
            "slices": Counter(),
            "sample_id": "",
            "sample_date": "",
            "sample_version": "",
            "sample_sig": "",
            "sample_stack": "",
        })
        item["count"] += 1
        item["signals"][get_field(row, "Sig")] += 1
        item["versions"][get_field(row, "Version")] += 1
        item["slices"][get_field(row, "SourceSlice")] += 1
        if not item["sample_id"]:
            item["sample_id"] = get_field(row, "ID")
            item["sample_date"] = get_field(row, "Dt")
            item["sample_version"] = get_field(row, "Version")
            item["sample_sig"] = get_field(row, "Sig")
            item["sample_stack"] = "\n".join((get_field(row, "StackInfo") or "").splitlines()[:6])

    signature_rows = []
    for item in sorted(signature_agg.values(), key=lambda current: (-current["count"], current["category"], current["signature"])):
        status, cause, fix = triage_signature(item["category"], item["signature"], item["sample_stack"])
        signature_rows.append({
            "signature": item["signature"],
            "category": item["category"],
            "count": item["count"],
            "signal_top": "; ".join(f"{key}:{value}" for key, value in item["signals"].most_common(3)),
            "version_top": "; ".join(f"{key}:{value}" for key, value in item["versions"].most_common(5)),
            "version_count": len(item["versions"]),
            "slice_span": "; ".join(f"{key}:{value}" for key, value in item["slices"].most_common()),
            "sample_id": item["sample_id"],
            "sample_date": item["sample_date"],
            "sample_version": item["sample_version"],
            "sample_sig": item["sample_sig"],
            "sample_stack": item["sample_stack"],
            "status": status,
            "root_cause_hint": cause,
            "fix_hint": fix,
        })

    signature_rows_v2 = [row.copy() for row in signature_rows]
    signature_rows_v3, changed_rows = review_remaining_signatures([row.copy() for row in signature_rows])

    signature_summary_path = os.path.join(args.output_dir, "signature_summary.csv")
    write_csv(
        signature_summary_path,
        ["signature", "category", "count", "signal_top", "version_top", "version_count", "slice_span", "sample_id", "sample_date", "sample_version", "sample_sig", "sample_stack"],
        [{key: row[key] for key in ["signature", "category", "count", "signal_top", "version_top", "version_count", "slice_span", "sample_id", "sample_date", "sample_version", "sample_sig", "sample_stack"]} for row in signature_rows],
    )

    signature_triage_path = os.path.join(args.output_dir, "signature_triage_v2.csv")
    write_csv(
        signature_triage_path,
        ["category", "status", "root_cause_hint", "fix_hint", "count", "signal_top", "version_top", "version_count", "sample_id", "sample_date", "sample_version", "sample_sig", "signature", "sample_stack"],
        [{
            "category": row["category"],
            "status": row["status"],
            "root_cause_hint": row["root_cause_hint"],
            "fix_hint": row["fix_hint"],
            "count": row["count"],
            "signal_top": row["signal_top"],
            "version_top": row["version_top"],
            "version_count": row["version_count"],
            "sample_id": row["sample_id"],
            "sample_date": row["sample_date"],
            "sample_version": row["sample_version"],
            "sample_sig": row["sample_sig"],
            "signature": row["signature"],
            "sample_stack": row["sample_stack"],
        } for row in signature_rows_v2],
    )

    signature_triage_v3_path = os.path.join(args.output_dir, "signature_triage_v3.csv")
    write_csv(
        signature_triage_v3_path,
        ["category", "status", "root_cause_hint", "fix_hint", "count", "signal_top", "version_top", "version_count", "sample_id", "sample_date", "sample_version", "sample_sig", "signature", "sample_stack"],
        [{
            "category": row["category"],
            "status": row["status"],
            "root_cause_hint": row["root_cause_hint"],
            "fix_hint": row["fix_hint"],
            "count": row["count"],
            "signal_top": row["signal_top"],
            "version_top": row["version_top"],
            "version_count": row["version_count"],
            "sample_id": row["sample_id"],
            "sample_date": row["sample_date"],
            "sample_version": row["sample_version"],
            "sample_sig": row["sample_sig"],
            "signature": row["signature"],
            "sample_stack": row["sample_stack"],
        } for row in signature_rows_v3],
    )

    lowfreq_rows = []
    for row in all_rows:
        if signature_counts[row["_signature"]] > 3:
            continue
        matching = next(item for item in signature_rows_v3 if item["signature"] == row["_signature"])
        lowfreq_rows.append({
            "ID": get_field(row, "ID"),
            "Dt": get_field(row, "Dt"),
            "Version": get_field(row, "Version"),
            "Sig": get_field(row, "Sig"),
            "SignatureCount": signature_counts[row["_signature"]],
            "Category": row["_category"],
            "ResolvedStatus": matching["status"],
            "ResolutionHint": matching["root_cause_hint"],
            "FixHint": matching["fix_hint"],
            "SourceSlice": get_field(row, "SourceSlice"),
            "Signature": row["_signature"],
            "TopFrames": "\n".join((get_field(row, "StackInfo") or "").splitlines()[:6]),
        })

    lowfreq_path = os.path.join(args.output_dir, "lowfreq_resolution_v2.csv")
    write_csv(
        lowfreq_path,
        ["ID", "Dt", "Version", "Sig", "SignatureCount", "Category", "ResolvedStatus", "ResolutionHint", "FixHint", "SourceSlice", "Signature", "TopFrames"],
        lowfreq_rows,
    )

    actionable_rows = aggregate_actionable(signature_rows_v3)
    actionable_path = os.path.join(args.output_dir, "actionable_issues.csv")
    write_csv(
        actionable_path,
        ["priority", "category", "status", "signatures", "records", "version_top", "signal_top", "sample_version", "sample_sig", "sample_id", "root_cause_hint", "fix_hint", "sample_signature"],
        actionable_rows,
    )

    retained_rows = aggregate_retained(signature_rows_v3)
    retained_path = os.path.join(args.output_dir, "retained_issues.csv")
    write_csv(
        retained_path,
        ["category", "status", "signatures", "records", "version_top", "signal_top", "sample_version", "sample_sig", "sample_id", "root_cause_hint", "fix_hint", "sample_signature"],
        retained_rows,
    )

    summary_path = build_markdown_summary(args.output_dir, actionable_rows, retained_rows)
    remaining_review_path = build_remaining_review(args.output_dir, signature_rows_v2, signature_rows_v3, changed_rows)

    print(f"dataset={dataset_path}")
    print(f"signature_summary={signature_summary_path}")
    print(f"signature_triage={signature_triage_path}")
    print(f"signature_triage_v3={signature_triage_v3_path}")
    print(f"lowfreq={lowfreq_path}")
    print(f"actionable={actionable_path}")
    print(f"retained={retained_path}")
    print(f"summary={summary_path}")
    print(f"remaining_review={remaining_review_path}")
    print(f"input_files={len(input_files)}")
    print(f"records={len(all_rows)}")
    print(f"signatures={len(signature_rows_v3)}")
    print(f"lowfreq_records={len(lowfreq_rows)}")


if __name__ == "__main__":
    main()
