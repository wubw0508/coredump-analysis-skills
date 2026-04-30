#!/usr/bin/env python3
"""Common automatic-fix helpers."""

from pathlib import Path
from typing import Dict, Iterable, List, Tuple


def get_fix_specs() -> Dict[str, Dict]:
    return {}


def file_contains_all(path: Path, markers: Iterable[str]) -> bool:
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8")
    return all(marker in text for marker in markers)


def apply_replacements(path: Path, replacements: List[Tuple[str, str]]) -> bool:
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8")
    updated = text
    for old, new in replacements:
        if old not in updated:
            return False
        updated = updated.replace(old, new, 1)
    if updated == text:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def append_include_after(path: Path, anchor: str, include_line: str) -> bool:
    text = path.read_text(encoding="utf-8")
    if include_line in text:
        return False
    if anchor not in text:
        return False
    path.write_text(text.replace(anchor, anchor + include_line, 1), encoding="utf-8")
    return True
