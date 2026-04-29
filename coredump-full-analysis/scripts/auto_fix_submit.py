#!/usr/bin/env python3
"""按版本执行自动修复判定与 Gerrit 提交。

当前策略:
1. 只处理 analysis.json 中 fixable == true 的崩溃
2. 先检查 target branch 是否已包含已知修复提交
3. 已修复则跳过，不重复提交
4. 只有命中 package fixer 的模式才允许自动改代码
5. 没有稳定 fixer 的“可修复”崩溃只记录为 manual_required
"""

import argparse
import importlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from fixers.common import get_fix_specs as get_common_fix_specs


def normalize_package_name(package: str) -> str:
    return re.sub(r"[^a-z0-9_]+", "_", (package or "").strip().lower())


def load_package_fixer_module(package: str):
    module_name = normalize_package_name(package)
    if not module_name:
        return None

    try:
        return importlib.import_module(f"fixers.{module_name}")
    except ModuleNotFoundError as exc:
        if exc.name == f"fixers.{module_name}":
            return None
        raise


def get_fix_specs(package: str) -> Dict[str, Dict]:
    specs = dict(get_common_fix_specs())
    module = load_package_fixer_module(package)
    if module and hasattr(module, "get_fix_specs"):
        specs.update(module.get_fix_specs())
    return specs


def build_crash_haystack(crash: Dict) -> str:
    parts = []

    app_symbol = crash.get("app_layer_symbol") or ""
    if app_symbol:
        parts.append(app_symbol)

    key_frame = crash.get("key_frame") or {}
    for value in (key_frame.get("symbol") or "", key_frame.get("library") or ""):
        if value:
            parts.append(value)

    for frame in (crash.get("frames") or [])[:16]:
        for value in (frame.get("symbol") or "", frame.get("library") or ""):
            if value:
                parts.append(value)

    return " ".join(parts)


def resolve_fix_spec_for_crash(specs: Dict[str, Dict], crash: Dict) -> Dict:
    pattern = crash.get("pattern_name") or "unknown"
    spec = specs.get(pattern, {})
    if not spec:
        return {}

    haystack = build_crash_haystack(crash)
    haystack_lower = haystack.lower()

    for rule in spec.get("symbol_rules", []):
        tokens_all = rule.get("symbol_contains_all") or []
        if tokens_all and all(token.lower() in haystack_lower for token in tokens_all if token):
            merged = dict(spec)
            merged.update(rule)
            return merged

        token = rule.get("symbol_contains")
        if token and token.lower() in haystack_lower:
            merged = dict(spec)
            merged.update(rule)
            return merged

    return spec


def clean_version(version: str) -> str:
    version = re.sub(r"^1:", "", version)
    version = re.sub(r"-1$", "", version)
    return version


def version_to_dir(version: str) -> str:
    return version.replace(".", "_").replace("+", "_").replace("-", "_")


def run_git(code_dir: Path, args: List[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(code_dir)] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=check,
    )


def git_ref_exists(code_dir: Path, ref: str) -> bool:
    result = run_git(code_dir, ["rev-parse", "--verify", ref], check=False)
    return result.returncode == 0


def branch_contains_commit(code_dir: Path, target_ref: str, commit: str) -> bool:
    result = run_git(code_dir, ["merge-base", "--is-ancestor", commit, target_ref], check=False)
    return result.returncode == 0


def load_analysis_file(package: str, version: str, workspace: Path) -> Path:
    version_dir = version_to_dir(clean_version(version))
    return workspace / "5.崩溃分析" / package / f"version_{version_dir}" / "analysis.json"


def make_result_path(package: str, version: str, workspace: Path) -> Path:
    version_dir = version_to_dir(clean_version(version))
    return workspace / "5.崩溃分析" / package / f"version_{version_dir}" / "auto_fix_result.json"


def checkout_target_branch(code_dir: Path, target_ref: str, branch_name: str):
    run_git(code_dir, ["fetch", "origin"], check=False)
    if git_ref_exists(code_dir, target_ref):
        run_git(code_dir, ["checkout", "-B", branch_name, target_ref])
        return
    fallback = target_ref.replace("origin/", "")
    run_git(code_dir, ["checkout", "-B", branch_name, fallback])


def build_fix_branch_name(package: str, version: str) -> str:
    date_str = datetime.now().strftime("%Y%m%d")
    return f"auto-fix/{package}/v{version.replace('.', '_').replace('+', '_')}-{date_str}"


def create_commit(code_dir: Path, message: str) -> Optional[str]:
    run_git(code_dir, ["add", "-A"], check=False)
    diff = run_git(code_dir, ["diff", "--cached", "--name-only"], check=False)
    if diff.returncode != 0 or not diff.stdout.strip():
        return None
    msg_file = code_dir / ".git" / "AUTO_FIX_COMMIT_MSG"
    msg_file.write_text(message, encoding="utf-8")
    try:
        run_git(code_dir, ["commit", "-F", str(msg_file)])
        rev = run_git(code_dir, ["rev-parse", "HEAD"])
        return rev.stdout.strip()
    finally:
        if msg_file.exists():
            msg_file.unlink()


def generate_commit_message_via_template(package: str, version: str, workspace: Path, crash_context: Dict, spec: Dict) -> str:
    script_path = Path(__file__).with_name("submit_to_gerrit.sh")
    if not script_path.exists():
        raise FileNotFoundError(f"submit_to_gerrit.sh not found: {script_path}")

    env = os.environ.copy()
    env.setdefault("SKILLS_DIR", str(script_path.parent.parent.parent))
    context = dict(crash_context)
    overrides = spec.get("commit_message_overrides") or {}
    if overrides:
        context["crash_desc_override"] = overrides.get("crash_desc", "")
        context["root_cause_override"] = overrides.get("root_cause", "")
        context["fix_desc_override"] = overrides.get("fix_desc", "")
        context["log_override"] = overrides.get("log", "")
        context["influence_override"] = overrides.get("influence", "")
    context_file = workspace / "5.崩溃分析" / package / f"version_{version_to_dir(clean_version(version))}" / "auto_fix_commit_context.json"
    context_file.write_text(json.dumps(context, ensure_ascii=False, indent=2), encoding="utf-8")
    result = subprocess.run(
        [
            "bash",
            str(script_path),
            "--package",
            package,
            "--version",
            version,
            "--workspace",
            str(workspace),
            "--print-commit-message",
            "--crash-context-file",
            str(context_file),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
        env=env,
    )
    return result.stdout.strip()


def cherry_pick_commit(code_dir: Path, commit: str) -> subprocess.CompletedProcess:
    return run_git(code_dir, ["cherry-pick", "-x", commit], check=False)


def abort_cherry_pick(code_dir: Path):
    run_git(code_dir, ["cherry-pick", "--abort"], check=False)


def push_to_gerrit(code_dir: Path, target_branch: str, reviewers: List[str]) -> bool:
    refspec = f"HEAD:refs/for/{target_branch}"
    if reviewers:
        refspec += "%r=" + ",".join(reviewers)
    result = run_git(code_dir, ["push", "origin", refspec], check=False)
    return result.returncode == 0


def apply_string_replacements(file_path: Path, replacements: List[Tuple[str, str]]) -> bool:
    text = file_path.read_text(encoding="utf-8")
    updated = text
    for old, new in replacements:
        if old not in updated:
            return False
        updated = updated.replace(old, new, 1)
    if updated == text:
        return False
    file_path.write_text(updated, encoding="utf-8")
    return True


def apply_appitem_dbus_guard(appitem_cpp: Path) -> bool:
    helper_block = """
static QString readDockEntryStringProperty(DockEntryInter *entry, const char *propertyName, const QString &fallback = QString())
{
    if (!entry) {
        return fallback;
    }

    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral(\"com.deepin.dde.daemon.Dock\"),
        entry->path(),
        QStringLiteral(\"org.freedesktop.DBus.Properties\"),
        QStringLiteral(\"Get\"));
    message << QStringLiteral(\"dde.dock.Entry\") << QString::fromLatin1(propertyName);

    QDBusMessage reply = QDBusConnection::sessionBus().call(message);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
        return fallback;
    }

    const QDBusVariant variant = reply.arguments().constFirst().value<QDBusVariant>();
    return variant.variant().toString();
}

static bool readDockEntryBoolProperty(DockEntryInter *entry, const char *propertyName, bool fallback = false)
{
    if (!entry) {
        return fallback;
    }

    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral(\"com.deepin.dde.daemon.Dock\"),
        entry->path(),
        QStringLiteral(\"org.freedesktop.DBus.Properties\"),
        QStringLiteral(\"Get\"));
    message << QStringLiteral(\"dde.dock.Entry\") << QString::fromLatin1(propertyName);

    QDBusMessage reply = QDBusConnection::sessionBus().call(message);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
        return fallback;
    }

    const QDBusVariant variant = reply.arguments().constFirst().value<QDBusVariant>();
    return variant.variant().toBool();
}

static quint32 readDockEntryUIntProperty(DockEntryInter *entry, const char *propertyName, quint32 fallback = 0)
{
    if (!entry) {
        return fallback;
    }

    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral(\"com.deepin.dde.daemon.Dock\"),
        entry->path(),
        QStringLiteral(\"org.freedesktop.DBus.Properties\"),
        QStringLiteral(\"Get\"));
    message << QStringLiteral(\"dde.dock.Entry\") << QString::fromLatin1(propertyName);

    QDBusMessage reply = QDBusConnection::sessionBus().call(message);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
        return fallback;
    }

    const QDBusVariant variant = reply.arguments().constFirst().value<QDBusVariant>();
    return variant.variant().toUInt();
}
""".strip("\n")

    replacements = [
        (
            "#include <QGSettings>\n",
            "#include <QGSettings>\n#include <QDBusMessage>\n#include <QDBusReply>\n#include <QDBusVariant>\n",
        ),
        (
            "QPoint AppItem::MousePressPos;\n",
            f"QPoint AppItem::MousePressPos;\n\n{helper_block}\n",
        ),
        (
            "    setObjectName(m_itemEntryInter->name());\n",
            "    setObjectName(m_entry.path());\n",
        ),
        (
            "    m_id = m_itemEntryInter->id();\n    m_active = m_itemEntryInter->isActive();\n    m_currentWindowId = m_itemEntryInter->currentWindow();\n",
            "    m_id = readDockEntryStringProperty(m_itemEntryInter, \"Id\");\n    m_active = readDockEntryBoolProperty(m_itemEntryInter, \"IsActive\");\n    m_currentWindowId = readDockEntryUIntProperty(m_itemEntryInter, \"CurrentWindow\");\n",
        ),
        (
            "    updateWindowInfos(m_itemEntryInter->windowInfos());\n    refreshIcon();\n",
            "    QTimer::singleShot(0, this, [this] {\n        setObjectName(readDockEntryStringProperty(m_itemEntryInter, \"Name\", m_entry.path()));\n        updateWindowInfos(m_itemEntryInter->windowInfos());\n        refreshIcon();\n    });\n",
        ),
    ]
    return apply_string_replacements(appitem_cpp, replacements)


def read_file_at_ref(code_dir: Path, git_ref: str, relative_path: str) -> Optional[str]:
    result = run_git(code_dir, ["show", f"{git_ref}:{relative_path}"], check=False)
    if result.returncode != 0:
        return None
    return result.stdout


def is_fix_already_present(code_dir: Path, target_ref: str, spec: Dict) -> bool:
    auto_fixer = spec.get("auto_fixer")
    if auto_fixer == "apply_appitem_dbus_guard":
        target_file = spec.get("target_file") or "frame/item/appitem.cpp"
        content = read_file_at_ref(code_dir, target_ref, target_file)
        if not content:
            return False
        markers = [
            'readDockEntryStringProperty(m_itemEntryInter, "Id")',
            'readDockEntryBoolProperty(m_itemEntryInter, "IsActive")',
            'readDockEntryUIntProperty(m_itemEntryInter, "CurrentWindow")',
            'QTimer::singleShot(0, this, [this] {',
        ]
        return all(marker in content for marker in markers)
    return False


def apply_auto_fix(code_dir: Path, spec: Dict) -> Tuple[bool, str]:
    auto_fixer = spec.get("auto_fixer")
    if auto_fixer == "cherry_pick_known_fix":
        preferred_commit = spec.get("preferred_commit")
        if not preferred_commit:
            return False, "missing preferred_commit for cherry-pick fixer"
        pick = cherry_pick_commit(code_dir, preferred_commit)
        if pick.returncode == 0:
            return True, preferred_commit
        abort_cherry_pick(code_dir)
        return False, f"cherry-pick failed for commit {preferred_commit}"

    if auto_fixer == "apply_appitem_dbus_guard":
        target_file = spec.get("target_file") or "frame/item/appitem.cpp"
        file_path = code_dir / target_file
        if not file_path.exists():
            return False, f"target file not found: {file_path}"
        if apply_appitem_dbus_guard(file_path):
            return True, f"updated {target_file}"
        return False, f"unable to apply appitem dbus guard to {target_file}"

    return False, f"auto fixer '{auto_fixer}' is not supported by dispatcher"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--target-branch", default="origin/develop/eagle")
    parser.add_argument("--reviewer", action="append", default=[])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--auto-confirm", action="store_true")
    args = parser.parse_args()

    workspace = Path(args.workspace)
    code_dir = workspace / "3.代码管理" / args.package
    analysis_file = load_analysis_file(args.package, args.version, workspace)
    result_file = make_result_path(args.package, args.version, workspace)

    if not analysis_file.exists():
        print(f"错误: 分析文件不存在: {analysis_file}", file=sys.stderr)
        return 1
    if not (code_dir / ".git").exists():
        print(f"错误: 代码目录不是 git 仓库: {code_dir}", file=sys.stderr)
        return 1

    specs = get_fix_specs(args.package)
    data = json.loads(analysis_file.read_text(encoding="utf-8"))
    fixable_crashes = [c for c in data.get("crashes", []) if c.get("fixable") is True]

    result = {
        "package": args.package,
        "version": args.version,
        "target_branch": args.target_branch,
        "analysis_time": datetime.now().isoformat(),
        "total_fixable_crashes": len(fixable_crashes),
        "already_fixed": [],
        "manual_required": [],
        "auto_fixed": [],
        "submitted": False,
        "branch_name": None,
        "commit_hash": None,
    }

    pending_auto_fix = []

    for crash in fixable_crashes:
        pattern = crash.get("pattern_name") or "unknown"
        spec = resolve_fix_spec_for_crash(specs, crash)
        entry = {
            "id": crash.get("id"),
            "count": crash.get("count", 1),
            "pattern_name": pattern,
            "app_layer_symbol": crash.get("app_layer_symbol") or "",
        }

        matched_commit = None
        for commit in spec.get("fixed_commits", []):
            if branch_contains_commit(code_dir, args.target_branch, commit):
                matched_commit = commit
                break

        if matched_commit:
            entry["matched_commit"] = matched_commit
            entry["reason"] = spec.get("description") or "target branch already contains known fix"
            result["already_fixed"].append(entry)
            continue

        auto_fixer = spec.get("auto_fixer")
        if not auto_fixer:
            entry["reason"] = "no stable auto fixer registered"
            result["manual_required"].append(entry)
            continue

        if is_fix_already_present(code_dir, args.target_branch, spec):
            entry["reason"] = spec.get("description") or "target branch already contains equivalent fix"
            result["already_fixed"].append(entry)
            continue

        pending_auto_fix.append((entry, spec, crash))

    auto_fix_actions = []
    seen_actions = set()
    for entry, spec, _ in pending_auto_fix:
        auto_fixer = spec.get("auto_fixer")
        preferred_commit = spec.get("preferred_commit")
        target_file = spec.get("target_file")
        action_key = (auto_fixer, preferred_commit or "", target_file or "", entry["pattern_name"])
        if action_key in seen_actions:
            continue
        seen_actions.add(action_key)
        auto_fix_actions.append((entry, spec))

    if auto_fix_actions:
        branch_name = build_fix_branch_name(args.package, clean_version(args.version))
        result["branch_name"] = branch_name
        checkout_target_branch(code_dir, args.target_branch, branch_name)

        applied = []
        for entry, spec in auto_fix_actions:
            ok, detail = apply_auto_fix(code_dir, spec)
            if ok:
                applied.append(
                    {
                        "pattern_name": entry["pattern_name"],
                        "detail": detail,
                        "reason": spec.get("description") or spec.get("auto_fixer") or "auto fix applied",
                    }
                )
                continue

            result["manual_required"].append(
                {
                    **entry,
                    "reason": detail,
                }
            )

        if applied:
            commit_message = generate_commit_message_via_template(args.package, args.version, workspace, pending_auto_fix[0][2], auto_fix_actions[0][1])
            commit_hash = create_commit(code_dir, commit_message)
            if commit_hash:
                result["auto_fixed"].extend(applied)
                result["commit_hash"] = commit_hash
                if not args.dry_run:
                    result["submitted"] = push_to_gerrit(
                        code_dir,
                        args.target_branch.replace("origin/", "", 1),
                        args.reviewer,
                    )
            else:
                for item in applied:
                    result["manual_required"].append(
                        {
                            "pattern_name": item["pattern_name"],
                            "reason": "auto fixer produced no source changes to commit",
                        }
                    )

    result_file.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"自动修复结果已保存: {result_file}")
    print(f"可修复崩溃: {result['total_fixable_crashes']}")
    print(f"已在目标分支修复: {len(result['already_fixed'])}")
    print(f"自动修复应用: {len(result['auto_fixed'])}")
    print(f"仍需人工处理: {len(result['manual_required'])}")
    print(f"已提交 Gerrit: {result['submitted']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
