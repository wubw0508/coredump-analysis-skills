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
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

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
        msg_file.unlink(missing_ok=True)


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

        pending_auto_fix.append((entry, spec, crash))

    unique_fix_commits = []
    seen_commits = set()
    for entry, spec, _ in pending_auto_fix:
        auto_fixer = spec.get("auto_fixer")
        preferred_commit = spec.get("preferred_commit")
        if auto_fixer != "cherry_pick_known_fix" or not preferred_commit:
            result["manual_required"].append(
                {
                    **entry,
                    "reason": f"auto fixer '{auto_fixer}' is not supported by dispatcher",
                }
            )
            continue
        if preferred_commit in seen_commits:
            continue
        seen_commits.add(preferred_commit)
        unique_fix_commits.append((preferred_commit, spec, entry))

    if unique_fix_commits:
        branch_name = build_fix_branch_name(args.package, clean_version(args.version))
        result["branch_name"] = branch_name
        checkout_target_branch(code_dir, args.target_branch, branch_name)

        applied = []
        for commit, spec, entry in unique_fix_commits:
            pick = cherry_pick_commit(code_dir, commit)
            if pick.returncode == 0:
                applied.append(
                    {
                        "pattern_name": entry["pattern_name"],
                        "source_commit": commit,
                        "reason": spec.get("description") or "cherry-picked known upstream fix",
                    }
                )
                continue

            abort_cherry_pick(code_dir)
            result["manual_required"].append(
                {
                    **entry,
                    "reason": f"cherry-pick failed for commit {commit}",
                }
            )

        if applied:
            result["auto_fixed"].extend(applied)
            head = run_git(code_dir, ["rev-parse", "HEAD"])
            result["commit_hash"] = head.stdout.strip()
            if not args.dry_run:
                result["submitted"] = push_to_gerrit(
                    code_dir,
                    args.target_branch.replace("origin/", "", 1),
                    args.reviewer,
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
