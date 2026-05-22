"""
Gerrit 客户端 - 支持 SSH 和 REST API 双通道
SSH 优先，失败后自动回退到 REST API
"""
import subprocess
import json
import time
import urllib.request
import urllib.parse
import urllib.error
import re
from typing import Optional, Dict, List
from dataclasses import dataclass


@dataclass
class GerritConfig:
    """Gerrit连接配置"""
    host: str = "gerrit.uniontech.com"
    port: int = 29418
    user: str = "ut000168"
    ssh_key: str = "~/.ssh/id_rsa"
    rest_url: str = "https://gerrit.uniontech.com/r/a"


class GerritClient:
    """Gerrit SSH + REST 双通道客户端"""

    def __init__(self, config: Optional[GerritConfig] = None):
        self.config = config or GerritConfig()
        self.host = self.config.host
        self.port = self.config.port
        self.user = self.config.user
        self.ssh_key = self.config.ssh_key
        self.rest_url = self.config.rest_url
        self.cache: Dict[str, Dict] = {}
        self._ssh_available = None

    def _check_ssh_available(self) -> bool:
        """检查 SSH 是否可用"""
        if self._ssh_available is not None:
            return self._ssh_available

        try:
            result = subprocess.run(
                ["ssh", "-p", str(self.port), "-i", self.ssh_key,
                 "-o", "StrictHostKeyChecking=no",
                 "-o", "UserKnownHostsFile=/dev/null",
                 "-o", "ConnectTimeout=10",
                 f"{self.user}@{self.host}", "gerrit version"],
                capture_output=True,
                text=True,
                timeout=15
            )
            self._ssh_available = (result.returncode == 0)
        except Exception:
            self._ssh_available = False

        return self._ssh_available

    def _run_gerrit_command(self, query: str) -> Optional[str]:
        """执行 gerrit SSH 命令"""
        if not self._check_ssh_available():
            return None

        cmd = [
            "ssh",
            "-p", str(self.port),
            "-i", self.ssh_key,
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=10",
            f"{self.user}@{self.host}",
            "gerrit", "query",
            "--format=JSON",
            "--current-patch-set",
            query
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0:
                return result.stdout
            return None
        except Exception:
            return None

    def _parse_ssh_query_output(self, output: str, project: str = "") -> Optional[Dict]:
        try:
            lines = output.strip().split('\n')
            for line in lines:
                if not line.startswith('{') or '"type":"stats"' in line:
                    continue
                data = json.loads(line)
                if project and data.get('project') != project:
                    continue
                current_patch_set = data.get('currentPatchSet', {}) or {}
                owner = data.get('owner') or {}
                reviewers = []
                for reviewer in data.get('allReviewers', []) or []:
                    name = reviewer.get('name') or reviewer.get('username') or reviewer.get('email')
                    if name and name not in reviewers:
                        reviewers.append(name)
                return {
                    "change_number": data.get('number'),
                    "change_id": data.get('id'),
                    "subject": data.get('subject'),
                    "status": data.get('status'),
                    "url": data.get('url'),
                    "revision": current_patch_set.get('revision'),
                    "project": data.get('project', ''),
                    "branch": data.get('branch', ''),
                    "updated": data.get('lastUpdated', ''),
                    "owner": owner.get('name') or owner.get('username') or owner.get('email', ''),
                    "reviewers": reviewers,
                }
        except Exception:
            pass
        return None

    def _normalize_rest_response(self, data: Dict) -> Dict:
        project = data.get('project', '')
        owner = data.get('owner') or {}
        reviewers = []
        labels = data.get('labels') or {}
        for label in labels.values():
            for reviewer in label.get('all', []) or []:
                name = reviewer.get('name') or reviewer.get('username') or reviewer.get('email')
                if name and name not in reviewers:
                    reviewers.append(name)
        return {
            "change_number": data.get('_number'),
            "change_id": data.get('change_id') or data.get('id'),
            "subject": data.get('subject'),
            "status": data.get('status'),
            "url": f"https://gerrit.uniontech.com/c/{project}/+/{data.get('_number')}" if project and data.get('_number') else "",
            "revision": data.get('current_revision', ''),
            "project": project,
            "branch": data.get('branch', ''),
            "updated": data.get('updated', ''),
            "owner": owner.get('name') or owner.get('username') or owner.get('email', ''),
            "reviewers": reviewers,
        }

    def _query_by_rest(self, commit_hash: str, project: str = "") -> Optional[Dict]:
        """通过 REST API 查询 commit 对应的 change 信息"""
        # 构建查询 URL
        if project:
            query_url = f"{self.rest_url}/changes/?q=commit:{commit_hash}+project:{project}&o=ALL_REVISIONS"
        else:
            query_url = f"{self.rest_url}/changes/?q=commit:{commit_hash}&o=ALL_REVISIONS"

        try:
            # 创建请求
            request = urllib.request.Request(query_url)
            request.add_header('Content-Type', 'application/json')

            # 使用 Python 的 urllib 进行请求
            # 注意：Gerrit REST API 需要先获取 session
            response = urllib.request.urlopen(request, timeout=30)

            # 解析响应
            # Gerrit 返回的是 JSON 数组，最后一个元素是 -statistics 信息
            data = response.read().decode('utf-8')

            # 解析多行 JSON
            lines = data.strip().split('\n')
            for line in lines:
                line = line.strip()
                if line.startswith(')]}') or line.startswith('[{'):
                    # 移除 Gerrit 的 JSONP 前缀
                    if line.startswith(')]}'):
                        line = line[4:]
                    try:
                        changes = json.loads(line)
                        if isinstance(changes, list) and len(changes) > 0:
                            # 找到匹配的 change
                            for change in changes:
                                if change.get('status') == 'MERGED':
                                    return self._normalize_rest_response(change)
                    except json.JSONDecodeError:
                        continue

        except Exception as e:
            print(f"  [!] REST API 查询失败: {e}")

        return None

    def get_change_by_commit(self, commit_hash: str, project: str = "") -> Optional[Dict]:
        """
        通过 commit hash 查询 Gerrit change 信息
        优先使用 SSH，SSH 失败则回退到 REST API

        参数:
            commit_hash: git commit hash
            project: 项目名称 (如 "dde-dock", "dde-session-shell")

        返回:
            包含 change_number, change_id, url 等信息的字典，失败返回 None
        """
        if not commit_hash:
            return None

        # 检查缓存
        cache_key = f"{project}:{commit_hash}" if project else commit_hash
        if cache_key in self.cache:
            return self.cache[cache_key]

        result = None

        # 1. 优先使用 SSH
        if self._check_ssh_available():
            result = self._query_by_ssh(commit_hash, project)
            if result:
                self.cache[cache_key] = result
                return result

        # 2. SSH 失败则使用 REST API
        if not result:
            result = self._query_by_rest(commit_hash, project)
            if result:
                self.cache[cache_key] = result
                return result

        return None

    def _query_by_ssh(self, commit_hash: str, project: str = "") -> Optional[Dict]:
        """通过 SSH 查询 commit 对应的 change 信息"""
        query = f"commit:{commit_hash}"
        if project:
            query += f" project:{project}"

        output = self._run_gerrit_command(query)
        if not output:
            return None
        return self._parse_ssh_query_output(output, project)

    def _run_gerrit_change_number_query(self, change_number: int) -> Optional[str]:
        if not self._check_ssh_available():
            return None

        cmd = [
            "ssh",
            "-p", str(self.port),
            "-i", self.ssh_key,
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=10",
            f"{self.user}@{self.host}",
            "gerrit", "query",
            "--format=JSON",
            "--current-patch-set",
            "--all-reviewers",
            f"change:{change_number}"
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0:
                return result.stdout
            return None
        except Exception:
            return None

    def _query_change_by_number_ssh(self, change_number: int, project: str = "") -> Optional[Dict]:
        output = self._run_gerrit_change_number_query(change_number)
        if not output:
            return None
        return self._parse_ssh_query_output(output, project)

    def _query_change_by_number_rest(self, change_number: int, project: str = "") -> Optional[Dict]:
        query = str(change_number)
        if project:
            query += f"+project:{urllib.parse.quote(project)}"
        query_url = (
            f"{self.rest_url}/changes/?q={query}"
            "&o=DETAILED_LABELS&o=DETAILED_ACCOUNTS&o=CURRENT_REVISION"
        )

        try:
            request = urllib.request.Request(query_url)
            request.add_header('Content-Type', 'application/json')
            response = urllib.request.urlopen(request, timeout=30)
            data = response.read().decode('utf-8')
            cleaned = re.sub(r"^\)\]\}'\s*", "", data)
            changes = json.loads(cleaned)
            if isinstance(changes, list):
                for change in changes:
                    if project and change.get('project') != project:
                        continue
                    return self._normalize_rest_response(change)
        except Exception as e:
            print(f"  [!] REST API change number 查询失败: {e}")

        return None

    def get_change_by_number(self, change_number: int, project: str = "") -> Optional[Dict]:
        if not change_number:
            return None

        cache_key = f"change-number:{project}:{change_number}" if project else f"change-number:{change_number}"
        if cache_key in self.cache:
            return self.cache[cache_key]

        result = None
        if self._check_ssh_available():
            result = self._query_change_by_number_ssh(change_number, project)
            if result:
                self.cache[cache_key] = result
                return result

        if not result:
            result = self._query_change_by_number_rest(change_number, project)
            if result:
                self.cache[cache_key] = result
                return result

        return None

    def get_change_url(self, commit_hash: str, project: str = "") -> str:
        """
        获取 commit 对应的 Gerrit 变更 URL

        参数:
            commit_hash: git commit hash
            project: 项目名称

        返回:
            Gerrit 变更 URL，失败返回空字符串
        """
        result = self.get_change_by_commit(commit_hash, project)
        if result:
            return result.get("url", "")
        return ""

    def get_change_number(self, commit_hash: str, project: str = "") -> Optional[int]:
        """获取 commit 对应的 change number"""
        result = self.get_change_by_commit(commit_hash, project)
        if result:
            return result.get("change_number")
        return None

    def batch_get_changes(self, commit_hashes: List[str], project: str = "") -> Dict[str, Dict]:
        """
        批量查询 commit 对应的 change 信息

        参数:
            commit_hashes: commit hash 列表
            project: 项目名称

        返回:
            {commit_hash: change_info} 的字典
        """
        results = {}
        for commit_hash in commit_hashes:
            if commit_hash and commit_hash not in self.cache:
                result = self.get_change_by_commit(commit_hash, project)
                if result:
                    results[commit_hash] = result
                # 避免请求过快
                time.sleep(0.2)

        return results

    def is_commit_merged(self, commit_hash: str, project: str = "") -> bool:
        """检查 commit 是否已合并"""
        result = self.get_change_by_commit(commit_hash, project)
        if result:
            return result.get("status") == "MERGED"
        return False

    def clear_cache(self):
        """清空缓存"""
        self.cache.clear()


# 便捷函数
def get_gerrit_client() -> GerritClient:
    """获取默认配置的 GerritClient 实例"""
    return GerritClient()
