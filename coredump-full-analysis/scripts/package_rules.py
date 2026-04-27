#!/usr/bin/env python3
"""规则注册与包级模块装配。"""

import importlib
import re
from types import ModuleType
from typing import Dict, List, Optional

from rules.common import get_common_ai_explanations, get_common_patterns


def normalize_package_name(package: str) -> str:
    """将包名映射到 rules 目录下的模块名。"""
    return re.sub(r"[^a-z0-9_]+", "_", (package or "").strip().lower())


def load_package_rule_module(package: str) -> Optional[ModuleType]:
    """按约定加载包级规则模块，不存在时返回 None。"""
    module_name = normalize_package_name(package)
    if not module_name:
        return None

    try:
        return importlib.import_module(f"rules.{module_name}")
    except ModuleNotFoundError as exc:
        if exc.name == f"rules.{module_name}":
            return None
        raise


def get_package_patterns(package: str) -> List[Dict]:
    patterns = list(get_common_patterns())
    module = load_package_rule_module(package)

    if module and hasattr(module, "get_patterns"):
        patterns.extend(module.get_patterns())

    return patterns


def get_pattern_ai_explanations(package: str) -> Dict[str, Dict[str, str]]:
    explanations = dict(get_common_ai_explanations())
    module = load_package_rule_module(package)

    if module and hasattr(module, "get_ai_explanations"):
        explanations.update(module.get_ai_explanations())

    return explanations
