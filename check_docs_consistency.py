#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
DOC_FILES = [ROOT / 'SKILL.md', ROOT / 'FLOW.md']
DOC_FILES += sorted(ROOT.glob('coredump-*/SKILL.md'))
DOC_FILES += sorted(ROOT.glob('references/*.md'))

OLD_PATH_PATTERNS = [
    re.compile(r'~/.openclaw/skills/coredump-analysis-skills'),
    re.compile(r'/home/ut000168@uos/code/coredump-analysis-skills'),
]

PACKAGE_COUNT_REFS = [
    re.compile(r'24个默认项目'),
    re.compile(r'24个项目'),
    re.compile(r'24 个默认项目'),
    re.compile(r'24 个项目'),
]


def active_package_count() -> int:
    packages = ROOT / 'packages.txt'
    count = 0
    for line in packages.read_text(encoding='utf-8').splitlines():
        line = re.sub(r'#.*', '', line).strip()
        if line:
            count += 1
    return count


def main() -> int:
    errors = []
    package_count = active_package_count()

    for path in DOC_FILES:
        text = path.read_text(encoding='utf-8')
        rel = path.relative_to(ROOT)
        for pattern in OLD_PATH_PATTERNS:
            if pattern.search(text):
                errors.append(f'{rel}: contains machine-specific or old skill path: {pattern.pattern}')

        if path.name == 'FLOW.md':
            matched = any(p.search(text) for p in PACKAGE_COUNT_REFS)
            if not matched:
                errors.append(f'{rel}: does not mention current packages.txt active count ({package_count}) explicitly')

    if errors:
        print('FAIL')
        for err in errors:
            print('-', err)
        return 1

    print(f'OK: checked {len(DOC_FILES)} docs, packages.txt active count = {package_count}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
