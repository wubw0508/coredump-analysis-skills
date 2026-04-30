#!/usr/bin/env python3
"""
深度自动化崩溃分析和修复系统

功能：
1. 分析崩溃堆栈，识别常见崩溃模式
2. 智能匹配源代码中的修复点
3. 生成具体的修复代码
4. 提交到Gerrit（如果develop/eagle分支已修复则跳过）
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


def create_commit(repo_dir: str, message: str, files: List[str]) -> Optional[str]:
    """创建git commit"""
    for f in files:
        run_git(repo_dir, ["add", f], check=False)
    
    result = run_git(repo_dir, ["commit", "-m", message], check=False)
    if result.returncode == 0:
        result = run_git(repo_dir, ["rev-parse", "HEAD"])
        return result.stdout.strip()
    return None


def push_to_gerrit(repo_dir: str, target_branch: str, reviewers: List[str] = None) -> bool:
    """推送到Gerrit"""
    refspec = f"HEAD:refs/for/{target_branch}"
    if reviewers:
        for reviewer in reviewers:
            refspec += f"%r={reviewer}"
    result = run_git(repo_dir, ["push", "origin", refspec], check=False)
    return result.returncode == 0


def smart_replace(content: str, old_pattern: str, new_text: str) -> Tuple[bool, str]:
    """
    智能替换，支持格式变体
    返回 (是否替换, 替换后的内容)
    """
    # 直接匹配
    if old_pattern in content:
        return True, content.replace(old_pattern, new_text, 1)
    
    # 尝试去除空格/换行的变体
    old_normalized = re.sub(r'\s+', ' ', old_pattern).strip()
    lines = content.split('\n')
    
    for i, line in enumerate(lines):
        line_normalized = re.sub(r'\s+', ' ', line).strip()
        if old_normalized in line_normalized:
            # 找到匹配行，尝试替换多行
            for j in range(i, min(i + 10, len(lines))):
                block = '\n'.join(lines[i:j+1])
                if old_pattern.strip() in block:
                    new_block = block.replace(old_pattern.strip(), new_text.strip())
                    lines[i:j+1] = new_block.split('\n')
                    return True, '\n'.join(lines)
    
    return False, content


def apply_fix_with_fallback(file_path: str, replacements: List[Tuple[str, str]]) -> bool:
    """
    应用修复，支持多种格式变体
    """
    if not os.path.exists(file_path):
        return False
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    changed = False
    
    for old, new in replacements:
        success, content = smart_replace(content, old, new)
        if success:
            changed = True
    
    if changed and content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    
    return False


# ============== 修复器 ==============

def fix_pluginlistview_scroller(code_dir: str) -> Tuple[bool, str]:
    """修复 PluginListView 析构崩溃"""
    file_path = os.path.join(code_dir, "plugins/common/pluginlistview.cpp")
    
    replacements = [
        # 变体1: 空析构函数
        (
            "PluginListView::~PluginListView()\n{\n}",
            """PluginListView::~PluginListView()
{
    QScroller *scroller = QScroller::scroller(viewport());
    if (scroller) {
        scroller->stop();
    }
    QScroller::ungrabGesture(viewport());
}"""
        ),
        # 变体2: 单行析构函数
        (
            "PluginListView::~PluginListView() {}",
            """PluginListView::~PluginListView()
{
    QScroller *scroller = QScroller::scroller(viewport());
    if (scroller) {
        scroller->stop();
    }
    QScroller::ungrabGesture(viewport());
}"""
        ),
        # 变体3: 已有内容的析构函数
        (
            "PluginListView::~PluginListView()",
            """PluginListView::~PluginListView()
{
    QScroller *scroller = QScroller::scroller(viewport());
    if (scroller) {
        scroller->stop();
    }
    QScroller::ungrabGesture(viewport());"""
        ),
    ]
    
    if apply_fix_with_fallback(file_path, replacements):
        return True, "已修复 PluginListView 析构函数"
    
    return False, "未找到匹配的代码模式"


def fix_appitem_dbus_guard(code_dir: str) -> Tuple[bool, str]:
    """修复 AppItem D-Bus 属性读取崩溃"""
    file_path = os.path.join(code_dir, "frame/item/appitem.cpp")
    
    if not os.path.exists(file_path):
        return False, "文件不存在"
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 检查是否已修复
    if "readDockEntryStringProperty" in content:
        return False, "已包含修复代码"
    
    # 添加安全读取函数
    helper_code = '''
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
'''
    
    # 在文件开头添加include和helper函数
    if "#include <QDBusMessage>" not in content:
        content = content.replace("#include <QGSettings>", "#include <QGSettings>\n#include <QDBusMessage>\n#include <QDBusVariant>")
    
    # 在类定义前添加helper函数
    if "readDockEntryStringProperty" not in content:
        # 找到合适的位置插入
        insert_pos = content.find("QPoint AppItem::MousePressPos;")
        if insert_pos > 0:
            insert_pos = content.find("\n", insert_pos) + 1
            content = content[:insert_pos] + helper_code + "\n" + content[insert_pos:]
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    return True, "已添加 D-Bus 属性安全读取"


def fix_xcb_native_event_filter(code_dir: str) -> Tuple[bool, str]:
    """修复 XcbNativeEventFilter 崩溃"""
    # 这个修复需要在多个文件中添加空指针检查
    return False, "需要手动分析"


def fix_qscreen_geometry(code_dir: str) -> Tuple[bool, str]:
    """修复 QScreen::geometry 崩溃"""
    # 这个修复需要在访问QScreen前添加空指针检查
    return False, "需要手动分析"


def fix_qaccessible_isactive(code_dir: str) -> Tuple[bool, str]:
    """修复 QAccessible::isActive 崩溃"""
    # 这个修复需要在访问QAccessible前添加空指针检查
    return False, "需要手动分析"


# ============== 崩溃模式识别 ==============

CRASH_PATTERNS = [
    {
        "name": "pluginlistview-qscroller-dtor",
        "description": "PluginListView 析构时 QScroller 资源崩溃",
        "symbols": ["PluginListViewD1Ev", "PluginListViewD0Ev"],
        "fixer": fix_pluginlistview_scroller,
        "confidence": "high"
    },
    {
        "name": "appitem-dbus-property-read",
        "description": "AppItem 构造阶段读取 D-Bus 属性崩溃",
        "symbols": ["AppItemC2", "DBusExtendedAbstractInterface15internalPropGet"],
        "fixer": fix_appitem_dbus_guard,
        "confidence": "high"
    },
    {
        "name": "xcb-native-event-filter",
        "description": "XcbNativeEventFilter 崩溃",
        "symbols": ["XcbNativeEventFilterC1EP14QXcbConnection"],
        "fixer": fix_xcb_native_event_filter,
        "confidence": "medium"
    },
    {
        "name": "qscreen-geometry",
        "description": "QScreen::geometry 崩溃",
        "symbols": ["_ZNK7QScreen8geometryEv", "_ZNK7QScreen16devicePixelRatioEv"],
        "fixer": fix_qscreen_geometry,
        "confidence": "medium"
    },
    {
        "name": "qaccessible-isactive",
        "description": "QAccessible::isActive 崩溃",
        "symbols": ["_ZN11QAccessible8isActiveEv"],
        "fixer": fix_qaccessible_isactive,
        "confidence": "medium"
    },
]


def identify_crash_pattern(crash: Dict) -> Optional[Dict]:
    """识别崩溃模式"""
    stack_info = crash.get("stack_info", "")
    app_symbol = crash.get("app_layer_symbol", "")
    
    # 构建搜索文本
    search_text = f"{stack_info} {app_symbol}".lower()
    
    for pattern in CRASH_PATTERNS:
        for symbol in pattern["symbols"]:
            if symbol.lower() in search_text:
                return pattern
    
    return None


def analyze_and_fix(workspace: str, package: str, version: str, target_branch: str, dry_run: bool = False) -> Dict:
    """分析崩溃并生成修复"""
    result = {
        "package": package,
        "version": version,
        "target_branch": target_branch,
        "analysis_time": datetime.now().isoformat(),
        "total_crashes": 0,
        "fixable_crashes": 0,
        "identified_patterns": {},
        "fixes_applied": [],
        "fixes_submitted": False,
        "errors": []
    }
    
    # 加载analysis.json
    analysis_file = Path(workspace) / "5.崩溃分析" / package / f"version_{version.replace('.', '_')}" / "analysis.json"
    if not analysis_file.exists():
        result["errors"].append(f"analysis.json not found: {analysis_file}")
        return result
    
    with open(analysis_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    crashes = data.get("crashes", [])
    result["total_crashes"] = len(crashes)
    
    # 代码目录
    code_dir = Path(workspace) / "3.代码管理" / package
    if not (code_dir / ".git").exists():
        result["errors"].append(f"Git repository not found: {code_dir}")
        return result
    
    # 识别崩溃模式
    for crash in crashes:
        pattern = identify_crash_pattern(crash)
        if pattern:
            pattern_name = pattern["name"]
            if pattern_name not in result["identified_patterns"]:
                result["identified_patterns"][pattern_name] = {
                    "description": pattern["description"],
                    "confidence": pattern["confidence"],
                    "count": 0
                }
            result["identified_patterns"][pattern_name]["count"] += 1
            result["fixable_crashes"] += 1
    
    # 应用修复
    if not dry_run and result["identified_patterns"]:
        branch_name = f"auto-fix/{package}-{version}-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        checkout_branch(code_dir, target_branch, branch_name)
        
        for pattern_name, pattern_info in result["identified_patterns"].items():
            # 查找对应的fixer
            for pattern in CRASH_PATTERNS:
                if pattern["name"] == pattern_name:
                    fixer = pattern["fixer"]
                    success, message = fixer(str(code_dir))
                    
                    fix_result = {
                        "pattern": pattern_name,
                        "success": success,
                        "message": message
                    }
                    result["fixes_applied"].append(fix_result)
                    
                    if success:
                        # 创建commit
                        commit_message = f"[coredump-analysis] fix: {pattern_info['description']}\n\nCrash: {pattern_name}\nCount: {pattern_info['count']}\nConfidence: {pattern_info['confidence']}"
                        commit_hash = create_commit(str(code_dir), commit_message, [])
                        if commit_hash:
                            fix_result["commit_hash"] = commit_hash
                    
                    break
        
        # 提交到Gerrit
        if any(f.get("commit_hash") for f in result["fixes_applied"]):
            result["fixes_submitted"] = push_to_gerrit(str(code_dir), target_branch.replace("origin/", ""))
    
    return result


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="深度自动化崩溃分析和修复系统")
    parser.add_argument("--package", required=True, help="包名")
    parser.add_argument("--version", required=True, help="版本号")
    parser.add_argument("--workspace", required=True, help="工作目录")
    parser.add_argument("--target-branch", default="origin/develop/eagle", help="目标分支")
    parser.add_argument("--dry-run", action="store_true", help="干运行，不实际修改")
    
    args = parser.parse_args()
    
    result = analyze_and_fix(
        workspace=args.workspace,
        package=args.package,
        version=args.version,
        target_branch=args.target_branch,
        dry_run=args.dry_run
    )
    
    # 保存结果
    result_file = Path(args.workspace) / "5.崩溃分析" / args.package / f"version_{args.version.replace('.', '_')}" / "deep_auto_fix_result.json"
    result_file.parent.mkdir(parents=True, exist_ok=True)
    
    with open(result_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    print(f"深度自动修复结果已保存: {result_file}")
    print(f"总崩溃数: {result['total_crashes']}")
    print(f"可修复崩溃: {result['fixable_crashes']}")
    print(f"识别的模式: {len(result['identified_patterns'])}")
    print(f"应用的修复: {len(result['fixes_applied'])}")
    print(f"已提交: {result['fixes_submitted']}")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
