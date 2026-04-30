#!/usr/bin/env python3
"""dde-dock cluster-level automatic fix plans and actions."""

from pathlib import Path
from typing import Dict

from auto_fix_types import CrashCluster, FixPlan, FixResult
from fixers.common import apply_replacements, file_contains_all


def get_fix_specs() -> Dict[str, Dict]:
    return {}


def build_fix_plan_for_cluster(cluster: CrashCluster) -> FixPlan:
    plans = {
        "appitem-dbus-property-read": FixPlan(
            cluster_id=cluster.cluster_id,
            action="apply_appitem_dbus_guard",
            confidence="high",
            target_files=["frame/item/appitem.cpp"],
            commit_subject="[coredump-analysis] fix: 修复 AppItem 构造阶段读取属性崩溃",
            root_cause="AppItem 构造阶段同步读取 Dock Entry D-Bus 属性，属性链路未稳定时会触发非法内存访问。",
            fix_description="改为安全读取 Dock Entry 基础属性，并将名称、窗口信息和图标初始化延后到事件循环后执行。",
            influence="请重点验证 dde-dock 应用图标创建、窗口信息刷新、图标刷新以及 Dock Entry D-Bus 属性读取相关路径。",
        ),
        "pluginlistview-qscroller-dtor": FixPlan(
            cluster_id=cluster.cluster_id,
            action="apply_pluginlistview_scroller_cleanup",
            confidence="high",
            target_files=["plugins/common/pluginlistview.cpp"],
            commit_subject="[coredump-analysis] fix: 修复 PluginListView 析构崩溃",
            root_cause="PluginListView 析构时触摸滚动手势仍可能持有 viewport 相关资源，QScroller 清理顺序不稳定导致崩溃。",
            fix_description="析构阶段停止 QScroller 并注销 viewport 手势，避免 QWidget 销毁后仍访问滚动资源。",
            influence="请重点验证控制中心插件列表、护眼模式插件展开收起和触摸滚动路径。",
        ),
        "dock-context-menu-qwindow-dtor": FixPlan(
            cluster_id=cluster.cluster_id,
            action="apply_context_menu_lifecycle_guard",
            confidence="medium",
            target_files=["frame/item/dockitem.cpp", "plugins/quick-panel/quick-plugin/quickplugin.cpp"],
            commit_subject="[coredump-analysis] fix: 加强 Dock 菜单析构阶段防护",
            root_cause="DockContextMenuHelper 管理的菜单窗口在退出或 X11 资源异常时仍可能触发 QWidget/QWindow 析构链路崩溃。",
            fix_description="在显示和复用菜单前增加当前 widget 有效性检查，并在菜单隐藏后断开悬空引用路径。",
            influence="请重点验证任务栏右键菜单、快捷面板右键菜单、退出会话和 X11 断开场景。",
        ),
        "xrecord-x11-io-error": FixPlan(
            cluster_id=cluster.cluster_id,
            action="apply_event_monitor_xrecord_guard",
            confidence="medium",
            target_files=["plugins/tray/widgets/event_monitor.cpp"],
            commit_subject="[coredump-analysis] fix: 加强 XRecord 监听异常防护",
            root_cause="XRecord 监听线程遇到 X11 IO 异常时，libX11 默认处理会导致 dde-dock 异常退出。",
            fix_description="在两个 Display 上安装错误处理，检查 context/display 状态，并在关闭阶段避免重复释放 XRecord 资源。",
            influence="请重点验证托盘菜单、鼠标事件监听、Xorg 重启和会话退出路径。",
        ),
        "dock-application-notify-cast": FixPlan(
            cluster_id=cluster.cluster_id,
            action="apply_notify_safe_cast_guard",
            confidence="low",
            target_files=["frame/util/dockapplication.cpp"],
            commit_subject="[coredump-analysis] fix: 加强 DockApplication 事件分发防护",
            root_cause="DockApplication::notify 在事件对象异常时进行 RTTI 类型转换，存在访问异常事件对象的风险。",
            fix_description="改用事件类型判断后再静态转换，并保留多指触控拦截逻辑。",
            influence="请重点验证鼠标事件、触摸事件、多指触控和任务栏基础交互。",
        ),
        "speed-plugin-update-tip": FixPlan(
            cluster_id=cluster.cluster_id,
            action="apply_speed_plugin_tip_guard",
            confidence="low",
            target_files=["plugins/quick-panel/quick-plugin/quickplugin.cpp"],
            commit_subject="[coredump-analysis] fix: 加强插件提示更新防护",
            root_cause="插件定时器回调更新提示文本时，字符串或宿主对象状态可能已失效。",
            fix_description="在提示更新入口增加对象状态和字符串内容防护，避免回调阶段访问无效状态。",
            influence="请重点验证网速插件提示、快捷面板插件展示和定时刷新路径。",
        ),
    }
    return plans.get(
        cluster.key,
        FixPlan(
            cluster_id=cluster.cluster_id,
            action="record_conservative_analysis_only",
            confidence="low",
            target_files=[],
            commit_subject=f"[coredump-analysis] analyze: {cluster.title}",
            root_cause=f"{cluster.title} 已完成自动聚类，但当前本地源码中没有安全的直接修复点。",
            fix_description="记录自动分析结果，不修改源码。",
            influence="请结合该根因簇的代表堆栈继续验证。",
        ),
    )


def is_fix_present(code_dir: Path, plan: FixPlan) -> bool:
    markers = {
        "apply_appitem_dbus_guard": (
            "frame/item/appitem.cpp",
            ["readDockEntryStringProperty", "QTimer::singleShot(0, this"],
        ),
        "apply_pluginlistview_scroller_cleanup": (
            "plugins/common/pluginlistview.cpp",
            ["QScroller::scroller(viewport())", "QScroller::ungrabGesture(viewport())"],
        ),
        "apply_event_monitor_xrecord_guard": (
            "plugins/tray/widgets/event_monitor.cpp",
            ["XSetIOErrorHandler(customXIOErrorHandler)", "XRecordDisableContext"],
        ),
        "apply_notify_safe_cast_guard": (
            "frame/util/dockapplication.cpp",
            ["event->type() == QEvent::MouseButtonPress", "static_cast<QMouseEvent *>"],
        ),
    }
    marker = markers.get(plan.action)
    if not marker:
        return False
    relative_path, required_markers = marker
    return file_contains_all(code_dir / relative_path, required_markers)


def apply_fix_plan(code_dir: Path, plan: FixPlan) -> FixResult:
    if is_fix_present(code_dir, plan):
        return FixResult(plan.cluster_id, plan.action, False, "local source already contains equivalent fix", plan.target_files)

    actions = {
        "apply_appitem_dbus_guard": apply_appitem_dbus_guard,
        "apply_pluginlistview_scroller_cleanup": apply_pluginlistview_scroller_cleanup,
        "apply_event_monitor_xrecord_guard": apply_event_monitor_xrecord_guard,
        "apply_notify_safe_cast_guard": apply_notify_safe_cast_guard,
        "record_conservative_analysis_only": record_conservative_analysis_only,
    }
    action = actions.get(plan.action, record_conservative_analysis_only)
    return action(code_dir, plan)


def apply_appitem_dbus_guard(code_dir: Path, plan: FixPlan) -> FixResult:
    appitem_cpp = code_dir / "frame/item/appitem.cpp"
    helper_block = """
static QString readDockEntryStringProperty(DockEntryInter *entry, const char *propertyName, const QString &fallback = QString())
{
    if (!entry) {
        return fallback;
    }

    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("com.deepin.dde.daemon.Dock"),
        entry->path(),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Get"));
    message << QStringLiteral("dde.dock.Entry") << QString::fromLatin1(propertyName);

    QDBusMessage reply = QDBusConnection::sessionBus().call(message);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
        return fallback;
    }

    const QDBusVariant variant = reply.arguments().constFirst().value<QDBusVariant>();
    return variant.variant().toString();
}
""".strip("\n")
    changed = apply_replacements(appitem_cpp, [
        ("#include <QGSettings>\n", "#include <QGSettings>\n#include <QDBusMessage>\n#include <QDBusVariant>\n"),
        ("QPoint AppItem::MousePressPos;\n", f"QPoint AppItem::MousePressPos;\n\n{helper_block}\n"),
        ("    setObjectName(m_itemEntryInter->name());\n", "    setObjectName(m_entry.path());\n"),
        ("    m_id = m_itemEntryInter->id();\n", "    m_id = readDockEntryStringProperty(m_itemEntryInter, \"Id\");\n"),
        ("    updateWindowInfos(m_itemEntryInter->windowInfos());\n    refreshIcon();\n", "    QTimer::singleShot(0, this, [this] {\n        setObjectName(readDockEntryStringProperty(m_itemEntryInter, \"Name\", m_entry.path()));\n        updateWindowInfos(m_itemEntryInter->windowInfos());\n        refreshIcon();\n    });\n"),
    ])
    detail = "updated frame/item/appitem.cpp" if changed else "appitem guard not applied"
    return FixResult(plan.cluster_id, plan.action, changed, detail, ["frame/item/appitem.cpp"])


def apply_pluginlistview_scroller_cleanup(code_dir: Path, plan: FixPlan) -> FixResult:
    path = code_dir / "plugins/common/pluginlistview.cpp"
    changed = apply_replacements(path, [
        (
            "PluginListView::~PluginListView()\n{\n}\n",
            "PluginListView::~PluginListView()\n{\n    QScroller *scroller = QScroller::scroller(viewport());\n    if (scroller) {\n        scroller->stop();\n    }\n    QScroller::ungrabGesture(viewport());\n}\n",
        )
    ])
    detail = "updated plugins/common/pluginlistview.cpp" if changed else "plugin list cleanup not applied"
    return FixResult(plan.cluster_id, plan.action, changed, detail, ["plugins/common/pluginlistview.cpp"])


def apply_event_monitor_xrecord_guard(code_dir: Path, plan: FixPlan) -> FixResult:
    path = code_dir / "plugins/tray/widgets/event_monitor.cpp"
    changed = apply_replacements(path, [
        (
            "    if (d->display_datalink && d->context) {\n        XRecordDisableContext(d->display_datalink, d->context);\n        XSync(d->display_datalink, true);\n    }\n",
            "    if (d->display_datalink && d->context) {\n        XRecordDisableContext(d->display_datalink, d->context);\n        XSync(d->display_datalink, false);\n    }\n",
        ),
        (
            "    XSetIOErrorExitHandler(d->display, customXIOErrorExitHandler, NULL);\n\n    XRecordEnableContext(d->display, d->context, d->callback, (XPointer)d.data());\n",
            "    XSetIOErrorExitHandler(d->display, customXIOErrorExitHandler, NULL);\n    if (d->display_datalink) {\n        XSetIOErrorExitHandler(d->display_datalink, customXIOErrorExitHandler, NULL);\n    }\n\n    if (d->display && d->context) {\n        XRecordEnableContext(d->display, d->context, d->callback, (XPointer)d.data());\n    }\n",
        ),
    ])
    detail = "updated plugins/tray/widgets/event_monitor.cpp" if changed else "event monitor guard not applied"
    return FixResult(plan.cluster_id, plan.action, changed, detail, ["plugins/tray/widgets/event_monitor.cpp"])


def apply_notify_safe_cast_guard(code_dir: Path, plan: FixPlan) -> FixResult:
    path = code_dir / "frame/util/dockapplication.cpp"
    changed = apply_replacements(path, [
        (
            "    QMouseEvent *mouseEvent = dynamic_cast<QMouseEvent *>(event);\n\n    if (mouseEvent) {\n",
            "    QMouseEvent *mouseEvent = nullptr;\n    if (event && (event->type() == QEvent::MouseButtonPress || event->type() == QEvent::MouseButtonRelease || event->type() == QEvent::MouseMove)) {\n        mouseEvent = static_cast<QMouseEvent *>(event);\n    }\n\n    if (mouseEvent) {\n",
        ),
        (
            "    QTouchEvent *touchEvent = dynamic_cast<QTouchEvent *>(event);\n    if(touchEvent && (touchEvent->touchPoints().size() > 1)) {\n",
            "    QTouchEvent *touchEvent = nullptr;\n    if (event && (event->type() == QEvent::TouchBegin || event->type() == QEvent::TouchUpdate || event->type() == QEvent::TouchEnd)) {\n        touchEvent = static_cast<QTouchEvent *>(event);\n    }\n    if (touchEvent && (touchEvent->touchPoints().size() > 1)) {\n",
        ),
    ])
    detail = "updated frame/util/dockapplication.cpp" if changed else "notify guard not applied"
    return FixResult(plan.cluster_id, plan.action, changed, detail, ["frame/util/dockapplication.cpp"])


def record_conservative_analysis_only(_code_dir: Path, plan: FixPlan) -> FixResult:
    del _code_dir
    return FixResult(plan.cluster_id, plan.action, False, "no safe local source edit for this cluster", [])
