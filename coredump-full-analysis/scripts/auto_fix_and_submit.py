#!/usr/bin/env python3
"""
自动分析崩溃并生成修复代码提交到Gerrit

功能：
1. 分析崩溃堆栈，识别常见崩溃模式
2. 生成具体的修复代码
3. 提交到develop/eagle分支（如果已修复则跳过）
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from datetime import datetime


@dataclass
class CrashPattern:
    """崩溃模式定义"""
    name: str
    description: str
    symbol_patterns: List[str]
    fix_type: str  # null_check, boundary_check, lifecycle_guard, etc.
    confidence: str  # high, medium, low


@dataclass
class FixCode:
    """修复代码"""
    file_path: str
    original_code: str
    fixed_code: str
    description: str


# 已知的崩溃模式和修复方案
KNOWN_PATTERNS = [
    CrashPattern(
        name="qmenu-popup-null",
        description="QMenu::popup 空指针崩溃",
        symbol_patterns=["_ZN5QMenu5popupERK6QPointP7QAction"],
        fix_type="null_check",
        confidence="high"
    ),
    CrashPattern(
        name="qwidget-event-null",
        description="QWidget::event 空指针崩溃",
        symbol_patterns=["_ZN7QWidget5eventEP6QEvent"],
        fix_type="null_check",
        confidence="medium"
    ),
    CrashPattern(
        name="qobject-event-null",
        description="QObject::event 空指针崩溃",
        symbol_patterns=["_ZN7QObject5eventEP6QEvent"],
        fix_type="null_check",
        confidence="medium"
    ),
    CrashPattern(
        name="snitraywidget-click",
        description="SNITrayWidget::sendClick 崩溃",
        symbol_patterns=["_ZN13SNITrayWidget9sendClickEhii"],
        fix_type="null_check",
        confidence="high"
    ),
    CrashPattern(
        name="snitraywidget-context-menu",
        description="SNITrayWidget::showContextMenu 崩溃",
        symbol_patterns=["_ZN13SNITrayWidget15showContextMenuEii"],
        fix_type="null_check",
        confidence="high"
    ),
    CrashPattern(
        name="dbusmenuimporter-slot",
        description="DBusMenuImporter 槽函数崩溃",
        symbol_patterns=["_ZN16DBusMenuImporter19slotMenuAboutToShowEv"],
        fix_type="null_check",
        confidence="high"
    ),
    CrashPattern(
        name="qtimer-timeout",
        description="QTimer::timeout 崩溃",
        symbol_patterns=["_ZN6QTimer7timeoutENS_14QPrivateSignalE"],
        fix_type="lifecycle_guard",
        confidence="medium"
    ),
    CrashPattern(
        name="qcoreapplication-sendposted",
        description="QCoreApplicationPrivate::sendPostedEvents 崩溃",
        symbol_patterns=["_ZN23QCoreApplicationPrivate16sendPostedEventsEP7QObjectiP11QThreadData"],
        fix_type="lifecycle_guard",
        confidence="medium"
    ),
    CrashPattern(
        name="qaccessible-isactive",
        description="QAccessible::isActive 崩溃",
        symbol_patterns=["_ZN11QAccessible8isActiveEv"],
        fix_type="null_check",
        confidence="high"
    ),
    CrashPattern(
        name="qscreen-geometry",
        description="QScreen::geometry 崩溃",
        symbol_patterns=["_ZNK7QScreen8geometryEv"],
        fix_type="null_check",
        confidence="high"
    ),
    CrashPattern(
        name="xcb-native-event-filter",
        description="XcbNativeEventFilter 崩溃",
        symbol_patterns=["_ZN22XcbNativeEventFilterC1EP14QXcbConnection"],
        fix_type="null_check",
        confidence="high"
    ),
    CrashPattern(
        name="qthread-storage",
        description="QThreadStorage 崩溃",
        symbol_patterns=["_ZN16QThreadStorageData3getEv"],
        fix_type="null_check",
        confidence="medium"
    ),
]


def run_git(repo_dir: str, args: List[str], check: bool = True) -> subprocess.CompletedProcess:
    """执行git命令"""
    cmd = ["git"] + args
    return subprocess.run(cmd, cwd=repo_dir, capture_output=True, text=True, check=check)


def branch_contains_commit(repo_dir: str, branch: str, commit: str) -> bool:
    """检查分支是否包含指定commit"""
    try:
        result = run_git(repo_dir, ["merge-base", "--is-ancestor", commit, branch], check=False)
        return result.returncode == 0
    except Exception:
        return False


def checkout_branch(repo_dir: str, target_branch: str, new_branch: str):
    """切换到目标分支并创建新分支"""
    run_git(repo_dir, ["fetch", "origin"])
    run_git(repo_dir, ["checkout", target_branch.replace("origin/", "")])
    run_git(repo_dir, ["checkout", "-b", new_branch])


def cherry_pick_commit(repo_dir: str, commit: str) -> bool:
    """Cherry-pick指定commit"""
    result = run_git(repo_dir, ["cherry-pick", commit], check=False)
    return result.returncode == 0


def abort_cherry_pick(repo_dir: str):
    """中止cherry-pick"""
    run_git(repo_dir, ["cherry-pick", "--abort"], check=False)


def push_to_gerrit(repo_dir: str, target_branch: str, reviewers: List[str] = None) -> bool:
    """推送到Gerrit"""
    refspec = f"HEAD:refs/for/{target_branch}"
    if reviewers:
        for reviewer in reviewers:
            refspec += f"%r={reviewer}"
    result = run_git(repo_dir, ["push", "origin", refspec], check=False)
    return result.returncode == 0


def identify_crash_pattern(crash: Dict) -> Optional[CrashPattern]:
    """识别崩溃模式"""
    stack_info = crash.get("stack_info", "")
    app_symbol = crash.get("app_layer_symbol", "")
    
    # 构建搜索文本
    search_text = f"{stack_info} {app_symbol}".lower()
    
    for pattern in KNOWN_PATTERNS:
        for symbol in pattern.symbol_patterns:
            if symbol.lower() in search_text:
                return pattern
    
    return None


def generate_null_check_fix(file_path: str, function_name: str, crash_info: Dict) -> Optional[FixCode]:
    """生成空指针检查修复代码"""
    # 读取源文件
    if not os.path.exists(file_path):
        return None
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 查找函数定义
    # 这里简化处理，实际需要更复杂的解析
    return None


def analyze_crash_and_fix(workspace: str, package: str, version: str, target_branch: str, dry_run: bool = False) -> Dict:
    """分析崩溃并生成修复"""
    result = {
        "package": package,
        "version": version,
        "target_branch": target_branch,
        "analysis_time": datetime.now().isoformat(),
        "total_crashes": 0,
        "identified_patterns": 0,
        "already_fixed": 0,
        "fixes_applied": 0,
        "fixes_submitted": False,
        "details": []
    }
    
    # 加载analysis.json
    analysis_file = Path(workspace) / "5.崩溃分析" / package / f"version_{version.replace('.', '_')}" / "analysis.json"
    if not analysis_file.exists():
        result["error"] = f"analysis.json not found: {analysis_file}"
        return result
    
    with open(analysis_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    crashes = data.get("crashes", [])
    result["total_crashes"] = len(crashes)
    
    # 代码目录
    code_dir = Path(workspace) / "3.代码管理" / package
    if not (code_dir / ".git").exists():
        result["error"] = f"Git repository not found: {code_dir}"
        return result
    
    # 识别崩溃模式
    pattern_counts = {}
    for crash in crashes:
        pattern = identify_crash_pattern(crash)
        if pattern:
            pattern_name = pattern.name
            if pattern_name not in pattern_counts:
                pattern_counts[pattern_name] = {
                    "pattern": pattern,
                    "count": 0,
                    "crashes": []
                }
            pattern_counts[pattern_name]["count"] += 1
            pattern_counts[pattern_name]["crashes"].append(crash)
    
    result["identified_patterns"] = len(pattern_counts)
    
    # 对每个模式生成修复
    branch_name = f"auto-fix/{package}-{version}-{datetime.now().strftime('%Y%m%d%H%M%S')}"
    
    if not dry_run and pattern_counts:
        checkout_branch(code_dir, target_branch, branch_name)
    
    for pattern_name, pattern_data in pattern_counts.items():
        pattern = pattern_data["pattern"]
        count = pattern_data["count"]
        
        detail = {
            "pattern": pattern_name,
            "description": pattern.description,
            "count": count,
            "confidence": pattern.confidence,
            "fix_status": "pending"
        }
        
        # 检查是否已修复
        # TODO: 实现检查逻辑
        
        # 生成修复代码
        # TODO: 实现修复代码生成
        
        # 对于已知有cherry-pick修复的模式
        if pattern.fix_type == "cherry_pick_known_fix":
            # 这里可以添加cherry-pick逻辑
            pass
        
        detail["fix_status"] = "analyzed"
        result["details"].append(detail)
    
    # 提交到Gerrit
    if not dry_run and result["fixes_applied"] > 0:
        result["fixes_submitted"] = push_to_gerrit(code_dir, target_branch.replace("origin/", ""))
    
    return result


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="自动分析崩溃并生成修复代码提交到Gerrit")
    parser.add_argument("--package", required=True, help="包名")
    parser.add_argument("--version", required=True, help="版本号")
    parser.add_argument("--workspace", required=True, help="工作目录")
    parser.add_argument("--target-branch", default="origin/develop/eagle", help="目标分支")
    parser.add_argument("--dry-run", action="store_true", help="干运行，不实际修改")
    
    args = parser.parse_args()
    
    result = analyze_crash_and_fix(
        workspace=args.workspace,
        package=args.package,
        version=args.version,
        target_branch=args.target_branch,
        dry_run=args.dry_run
    )
    
    # 保存结果
    result_file = Path(args.workspace) / "5.崩溃分析" / args.package / f"version_{args.version.replace('.', '_')}" / "auto_fix_result.json"
    result_file.parent.mkdir(parents=True, exist_ok=True)
    
    with open(result_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    print(f"自动修复结果已保存: {result_file}")
    print(f"总崩溃数: {result['total_crashes']}")
    print(f"识别的模式数: {result['identified_patterns']}")
    print(f"已修复: {result['already_fixed']}")
    print(f"应用修复: {result['fixes_applied']}")
    print(f"已提交: {result['fixes_submitted']}")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
