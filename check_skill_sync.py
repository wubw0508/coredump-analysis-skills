#!/usr/bin/env python3
from pathlib import Path
import argparse
import difflib
import sys

REPO = Path(__file__).resolve().parent
DEFAULT_EXTERNAL = Path.home() / '.hermes/skills/devops/coredump-analysis'
MANAGED_REFS = [
    'README.md',
    'enhanced-analysis.md',
    'automatic-deep-dive-policy.md',
    'fixer-architecture.md',
]


def normalize_external_skill(text: str) -> str:
    text = text.replace('cd /home/ut000168@uos/code/coredump-analysis-skills', 'cd "$SKILLS_DIR"')

    old_block = """Default packages from `packages.txt`:
```
dde-control-center, dde-dock, dde-launcher, dde-session-ui,
dde-session-shell, dde-daemon, dde-api, dde-clipboard,
startdde, go-lib, dde-polkit-agent, dde-wloutput,
dde-network-core, deepin-face, dde-wldpms,
deepin-sound-theme, deepin-authenticate, deepin-pw-check, deepin-proxy
```"""
    new_block = """Default scope from `packages.txt`:
```
Use `packages.txt` as the source of truth.
It currently has 24 active non-comment entries, including:
- direct package entries (for example `dde-dock`)
- project:package mappings (for example `go-lib:golang-github-linuxdeepin-go-lib-dev`)
- one-project-many-packages mappings (for example `dde-network-core:...`)
- upstream project entries with custom branches (for example `base/lightdm:lightdm uos`)
```

For the exact active list, inspect `$SKILLS_DIR/packages.txt` directly instead of copying a stale inline subset into this skill."""
    text = text.replace(old_block, new_block)

    needle = '- `references/fixer-architecture.md` — auto-fix pipeline architecture, fixer coverage analysis, and expansion guidance\n- `references/automatic-deep-dive-policy.md`'
    repl = '- `references/README.md` — index of repo-managed reference docs and when to use each one\n- `references/fixer-architecture.md` — auto-fix pipeline architecture, fixer coverage analysis, and expansion guidance\n- `references/automatic-deep-dive-policy.md`'
    text = text.replace(needle, repl)
    return text


def rewrite_external_skill(target_dir: Path) -> None:
    skill = target_dir / 'SKILL.md'
    original = skill.read_text(encoding='utf-8')
    updated = normalize_external_skill(original)
    if updated != original:
        skill.write_text(updated, encoding='utf-8')
        print(f'rewritten: {skill}')
    else:
        print(f'unchanged: {skill}')


def compare_files(repo_file: Path, external_file: Path) -> list:
    if not external_file.exists():
        return [f'missing: {external_file}']
    repo_text = repo_file.read_text(encoding='utf-8')
    ext_text = external_file.read_text(encoding='utf-8')
    if repo_text == ext_text:
        return []
    diff = ''.join(difflib.unified_diff(
        repo_text.splitlines(True),
        ext_text.splitlines(True),
        fromfile=str(repo_file),
        tofile=str(external_file),
        n=1,
    ))
    return [f'drift: {external_file}\n{diff[:4000]}']


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--external-dir', default=str(DEFAULT_EXTERNAL))
    parser.add_argument('--rewrite-external-skill', nargs='?', const=str(DEFAULT_EXTERNAL))
    args = parser.parse_args()

    if args.rewrite_external_skill:
        rewrite_external_skill(Path(args.rewrite_external_skill))

    external_dir = Path(args.external_dir)
    issues = []
    for name in MANAGED_REFS:
        issues.extend(compare_files(REPO / 'references' / name, external_dir / 'references' / name))

    skill_text = (external_dir / 'SKILL.md').read_text(encoding='utf-8')
    if '/home/ut000168@uos/code/coredump-analysis-skills' in skill_text:
        issues.append('drift: external SKILL.md still contains machine-specific repo path')
    if "grep -rn 'openclaw' /home/ut000168@uos/code/coredump-analysis-skills/" in skill_text:
        issues.append('drift: external SKILL.md still contains machine-specific verification command')
    if 'currently 24' in skill_text and 'For the exact active list, inspect `$SKILLS_DIR/packages.txt` directly' not in skill_text:
        issues.append('drift: external SKILL.md still describes package scope with an inline subset instead of delegating to packages.txt')

    if issues:
        print('FAIL')
        for item in issues:
            print(item)
        return 1

    print('OK: external skill matches repo-managed references and key drift checks')
    return 0


if __name__ == '__main__':
    sys.exit(main())
