#!/usr/bin/env python3
"""dde-control-center cluster-level automatic fix plans and actions."""

from pathlib import Path
from typing import Dict

from auto_fix_types import CrashCluster, FixPlan, FixResult


def get_fix_specs() -> Dict[str, Dict]:
    return {}


def build_fix_plan_for_cluster(cluster: CrashCluster) -> FixPlan:
    plans = {
        "updater-dbus-watchers-dtor": FixPlan(
            cluster_id=cluster.cluster_id,
            action="apply_updater_dbus_watcher_cleanup",
            confidence="high",
            target_files=[],
            commit_subject="[coredump-analysis] fix: 修复 Updater 析构阶段 watcher 崩溃",
            root_cause="Updater 析构阶段仍持有 D-Bus 异步 watcher 映射，插件卸载或对象销毁时 watcher 回调/容器状态可能失效并触发崩溃。",
            fix_description="在本地源码定位到稳定修改点后，清理未完成的 D-Bus watcher 并断开回调，避免析构阶段访问失效映射。",
            influence="请重点验证控制中心更新插件打开、关闭、切换模块、退出控制中心和 D-Bus 更新状态回调路径。",
        ),
        "wallpaper-provider-dtor": FixPlan(
            cluster_id=cluster.cluster_id,
            action="record_conservative_analysis_only",
            confidence="medium",
            target_files=[],
            commit_subject="[coredump-analysis] analyze: WallpaperProvider 析构阶段崩溃",
            root_cause="WallpaperProvider 析构阶段触发 SIGABRT，当前本地源码中尚未定位到可安全自动改写的稳定代码片段。",
            fix_description="记录自动根因簇分析，不修改源码。",
            influence="请重点验证壁纸插件加载、卸载、退出控制中心和文件管理器壁纸提供方生命周期。",
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


def apply_fix_plan(code_dir: Path, plan: FixPlan) -> FixResult:
    del code_dir
    return FixResult(plan.cluster_id, plan.action, False, "no safe local source edit for this cluster", [])
