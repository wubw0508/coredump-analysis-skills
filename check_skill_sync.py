#!/usr/bin/env python3
"""Validate project-local skill documentation consistency.

This repository is the distributable skill source of truth. Do not compare or
sync against user-private cache directories.

`references/README.md` is the single source of truth for managed reference
files: add/remove reference files there first, then make SKILL.md route to them.
"""
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parent
MANAGED_ROOT_FILES = [
    'SKILL.md',
]
REFERENCE_INDEX = REPO / 'references' / 'README.md'
CURRENT_REF_SECTION_RE = re.compile(
    r'^## 当前本地 reference\s*$(.*?)^## ',
    re.MULTILINE | re.DOTALL,
)
REFERENCE_BULLET_RE = re.compile(r'^- `([A-Za-z0-9_.-]+\.md)`', re.MULTILINE)
REFERENCE_TOKEN_RE = re.compile(r'`(references/[A-Za-z0-9_.-]+\.md)`')
README_LOCAL_REF_RE = re.compile(r'`([A-Za-z0-9_.-]+\.md)`')
FORBIDDEN_PATH_SNIPPETS = [
    '/home/ut000168@uos/code/coredump-analysis-skills',
    '/home/ut000168@uos/.hermes/skills/devops/coredump-analysis',
    '~/.hermes/skills/devops/coredump-analysis',
    '.hermes/skills/devops/coredump-analysis',
    '/home/ut000168@uos/.hermes/skills',
    '~/.hermes/skills',
    'coredump-workspace-202',
]
DEPRECATED_REFERENCE_NAMES = [
    'auto-fix-submit-and-retry-classification.md',
    'auto-fix-target-branch-normalization.md',
    'gerrit-real-fix-triage.md',
    'gerrit-no-new-changes-verification.md',
]
SKILL_MD_MAX_LINES = 140
SKILL_MD_MAX_BYTES = 6500
REFERENCE_WARN_BYTES = 12000
GENERATED_CACHE_DIR_NAMES = {
    '__pycache__',
    '.pytest_cache',
    '.mypy_cache',
    '.ruff_cache',
}
GENERATED_FILE_GLOBS = (
    '*.pyc',
    '*.pyo',
)


def read_text(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def rel(path: Path) -> str:
    return str(path.relative_to(REPO))


def ordered_unique(items):
    seen = set()
    result = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def managed_ref_names_from_readme(issues: list) -> list:
    if not REFERENCE_INDEX.exists():
        issues.append('missing: references/README.md')
        return []
    text = read_text(REFERENCE_INDEX)
    match = CURRENT_REF_SECTION_RE.search(text + '\n## ')
    if not match:
        issues.append('references/README.md missing "## 当前本地 reference" section')
        return []
    section = match.group(1)
    names = REFERENCE_BULLET_RE.findall(section)
    if not names:
        issues.append('references/README.md current-reference section lists no reference files')
        return []
    dupes = sorted({name for name in names if names.count(name) > 1})
    if dupes:
        issues.append('duplicate entries in references/README.md current-reference section: ' + ', '.join(dupes))
    return ordered_unique(names)


def managed_ref_paths(issues: list) -> set:
    return {f'references/{name}' for name in managed_ref_names_from_readme(issues)}


def repo_ref_paths() -> set:
    ref_dir = REPO / 'references'
    if not ref_dir.exists():
        return set()
    return {f'references/{path.name}' for path in ref_dir.glob('*.md')}


def check_exists(path: Path, issues: list) -> None:
    if not path.exists():
        issues.append(f'missing: {rel(path)}')


def check_forbidden_paths(path: Path, issues: list) -> None:
    if not path.exists():
        return
    text = read_text(path)
    for snippet in FORBIDDEN_PATH_SNIPPETS:
        if snippet in text:
            issues.append(f'forbidden path snippet in {rel(path)}: {snippet}')


def check_deprecated_reference_names(path: Path, issues: list) -> None:
    if not path.exists():
        return
    text = read_text(path)
    for name in DEPRECATED_REFERENCE_NAMES:
        if name in text:
            issues.append(f'deprecated reference name in {rel(path)}: {name}')


def referenced_from_skill() -> set:
    skill = REPO / 'SKILL.md'
    if not skill.exists():
        return set()
    return set(REFERENCE_TOKEN_RE.findall(read_text(skill)))


def referenced_from_readme_all() -> set:
    if not REFERENCE_INDEX.exists():
        return set()
    refs = set()
    for token in README_LOCAL_REF_RE.findall(read_text(REFERENCE_INDEX)):
        if token == 'SKILL.md' or '*' in token:
            continue
        refs.add(f'references/{token}')
    return refs


def check_reference_targets(source: str, refs: set, issues: list) -> None:
    for ref in sorted(refs):
        if not (REPO / ref).exists():
            issues.append(f'{source} references missing local file: {ref}')


def check_ref_directory_matches_index(managed: set, issues: list) -> None:
    actual = repo_ref_paths()
    unmanaged = actual - managed
    missing_files = managed - actual
    if unmanaged:
        issues.append('references/*.md files not listed in references/README.md current-reference section: ' + ', '.join(sorted(unmanaged)))
    if missing_files:
        issues.append('references/README.md current-reference entries missing from references/: ' + ', '.join(sorted(missing_files)))


def check_documented_refs_match_index(managed: set, issues: list) -> None:
    skill_refs = referenced_from_skill()
    readme_refs = referenced_from_readme_all()

    documented = skill_refs | readme_refs
    extra_documented = documented - managed
    if extra_documented:
        issues.append('references documented outside current-reference index: ' + ', '.join(sorted(extra_documented)))

    missing_from_skill = managed - skill_refs
    if missing_from_skill:
        issues.append('references/README.md current-reference entries not routed from SKILL.md: ' + ', '.join(sorted(missing_from_skill)))


def check_generated_artifacts(warnings: list) -> None:
    cache_dirs = []
    for name in GENERATED_CACHE_DIR_NAMES:
        cache_dirs.extend(path for path in REPO.rglob(name) if path.is_dir())
    generated_files = []
    for pattern in GENERATED_FILE_GLOBS:
        generated_files.extend(path for path in REPO.rglob(pattern) if path.is_file())
    if cache_dirs or generated_files:
        warnings.append(
            'generated Python cache artifacts present in working tree: '
            f'{len(cache_dirs)} cache dirs, {len(generated_files)} bytecode files; '
            'safe to remove with find ... -name __pycache__ -type d -prune -exec rm -rf {} +'
        )


def check_size_guards(managed: set, issues: list, warnings: list) -> None:
    skill = REPO / 'SKILL.md'
    if skill.exists():
        text = read_text(skill)
        line_count = len(text.splitlines())
        byte_count = len(text.encode('utf-8'))
        if line_count > SKILL_MD_MAX_LINES:
            issues.append(f'SKILL.md too large: {line_count} lines > {SKILL_MD_MAX_LINES}')
        if byte_count > SKILL_MD_MAX_BYTES:
            issues.append(f'SKILL.md too large: {byte_count} bytes > {SKILL_MD_MAX_BYTES}')

    for ref in sorted(managed):
        path = REPO / ref
        if not path.exists():
            continue
        byte_count = path.stat().st_size
        if byte_count > REFERENCE_WARN_BYTES:
            warnings.append(f'large reference, consider splitting or summarizing: {ref} ({byte_count} bytes)')


def collect_stats(managed: set) -> dict:
    skill = REPO / 'SKILL.md'
    skill_lines = 0
    skill_bytes = 0
    if skill.exists():
        text = read_text(skill)
        skill_lines = len(text.splitlines())
        skill_bytes = len(text.encode('utf-8'))

    ref_bytes = 0
    existing_refs = 0
    for ref in managed:
        path = REPO / ref
        if path.exists():
            existing_refs += 1
            ref_bytes += path.stat().st_size
    return {
        'skill_lines': skill_lines,
        'skill_bytes': skill_bytes,
        'reference_count': existing_refs,
        'reference_bytes': ref_bytes,
    }


def main() -> int:
    issues = []
    warnings = []

    managed = managed_ref_paths(issues)
    check_ref_directory_matches_index(managed, issues)

    for name in MANAGED_ROOT_FILES:
        path = REPO / name
        check_exists(path, issues)
        check_forbidden_paths(path, issues)
        check_deprecated_reference_names(path, issues)

    for ref in sorted(managed):
        path = REPO / ref
        check_exists(path, issues)
        check_forbidden_paths(path, issues)
        check_deprecated_reference_names(path, issues)

    skill_refs = referenced_from_skill()
    readme_refs = referenced_from_readme_all()
    check_reference_targets('SKILL.md', skill_refs, issues)
    check_reference_targets('references/README.md', readme_refs, issues)
    check_documented_refs_match_index(managed, issues)
    check_size_guards(managed, issues, warnings)
    check_generated_artifacts(warnings)

    stats = collect_stats(managed)
    if issues:
        print('FAIL')
        for item in issues:
            print(item)
        for item in warnings:
            print('WARN: ' + item)
        print('STATS: SKILL.md={skill_lines} lines/{skill_bytes} bytes, references={reference_count} files/{reference_bytes} bytes'.format(**stats))
        return 1

    print('OK: project-local skill docs are self-contained, indexed from references/README.md, and contain no forbidden private paths')
    for item in warnings:
        print('WARN: ' + item)
    print('STATS: SKILL.md={skill_lines} lines/{skill_bytes} bytes, references={reference_count} files/{reference_bytes} bytes'.format(**stats))
    return 0


if __name__ == '__main__':
    sys.exit(main())
