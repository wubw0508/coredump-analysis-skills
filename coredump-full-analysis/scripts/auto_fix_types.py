#!/usr/bin/env python3
"""Shared types for crash-cluster automatic analysis and fixes."""

from dataclasses import dataclass, field
from typing import Dict, List, Optional


@dataclass
class CrashCluster:
    cluster_id: str
    package: str
    key: str
    title: str
    category: str
    confidence: str
    representative_crash: Dict
    crashes: List[Dict] = field(default_factory=list)

    @property
    def total_count(self) -> int:
        return sum(int(crash.get("count") or 0) for crash in self.crashes)

    @property
    def versions(self) -> List[str]:
        return sorted({str(crash.get("version") or "unknown") for crash in self.crashes})

    def to_dict(self) -> Dict:
        return {
            "cluster_id": self.cluster_id,
            "package": self.package,
            "key": self.key,
            "title": self.title,
            "category": self.category,
            "confidence": self.confidence,
            "total_count": self.total_count,
            "versions": self.versions,
            "representative_crash": self.representative_crash,
            "crashes": self.crashes,
        }


@dataclass
class FixPlan:
    cluster_id: str
    action: str
    confidence: str
    target_files: List[str]
    commit_subject: str
    root_cause: str
    fix_description: str
    influence: str
    submitted: bool = False
    reviewer_note: str = ""

    def to_dict(self) -> Dict:
        return {
            "cluster_id": self.cluster_id,
            "action": self.action,
            "confidence": self.confidence,
            "target_files": self.target_files,
            "commit_subject": self.commit_subject,
            "root_cause": self.root_cause,
            "fix_description": self.fix_description,
            "influence": self.influence,
            "submitted": self.submitted,
            "reviewer_note": self.reviewer_note,
        }


@dataclass
class FixResult:
    cluster_id: str
    action: str
    changed: bool
    detail: str
    files_changed: List[str] = field(default_factory=list)
    commit_hash: Optional[str] = None
    submitted: bool = False

    def to_dict(self) -> Dict:
        return {
            "cluster_id": self.cluster_id,
            "action": self.action,
            "changed": self.changed,
            "detail": self.detail,
            "files_changed": self.files_changed,
            "commit_hash": self.commit_hash,
            "submitted": self.submitted,
        }
