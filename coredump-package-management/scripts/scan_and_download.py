#!/usr/bin/env python3
"""
从内部构建服务器下载 deb 包和调试包（dbgsym）
支持命令行参数指定包名、版本、架构
支持批量下载
"""

import argparse
import json
import logging
import re
import sys
import time
from pathlib import Path
from urllib.parse import unquote

import requests
from requests.adapters import HTTPAdapter

# 默认配置
DEFAULT_BASE_URL = "http://10.0.32.60:5001"
DEFAULT_ARCH = "amd64"
DEFAULT_SUBDIR = "unstable-amd64"
DEFAULT_DOWNLOAD_DIR = "./downloads"
MAX_RETRIES = 3
TIMEOUT = 60

logger = logging.getLogger(__name__)


def configure_logging(download_dir: str):
    """将日志写入 workspace 包管理目录，避免落在 skills 仓库中。"""
    log_dir = Path(download_dir).resolve().parent
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "download.log"

    # Python 3.7 不支持 basicConfig(force=True)，手动清理已有 handler。
    root_logger = logging.getLogger()
    for handler in list(root_logger.handlers):
        root_logger.removeHandler(handler)
        handler.close()

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler()
        ],
    )


class DebDownloader:
    def __init__(self, base_url, download_dir, arch, subdir):
        self.base_url = base_url
        self.arch = arch
        self.subdir = subdir
        self.session = requests.Session()
        adapter = HTTPAdapter(pool_connections=50, pool_maxsize=50)
        self.session.mount('http://', adapter)
        self.session.mount('https://', adapter)
        self.download_dir = Path(download_dir)
        self.download_dir.mkdir(parents=True, exist_ok=True)
        self.found_packages = []
        self.downloaded_files = []
        self._task_ids_cache = None

    @staticmethod
    def _matches_version_prefix(deb_file, package_prefix, version):
        """Match version prefixes without confusing 1.2.3 with 1.2.30."""
        prefix = f"{package_prefix}{version}"
        if not deb_file.startswith(prefix):
            return False
        suffix = deb_file[len(prefix):]
        return bool(suffix) and suffix[0] in "_-+."

    def get_all_task_ids(self):
        """获取所有可用的 task_id（带缓存）"""
        if self._task_ids_cache is not None:
            return self._task_ids_cache

        logger.info(f"正在从 {self.base_url}/tasks/ 获取 task_id 列表...")
        try:
            resp = self.session.get(f"{self.base_url}/tasks/", timeout=60)
            resp.raise_for_status()
            task_ids = re.findall(r'href="(\d+)/"', resp.text)
            task_ids = sorted({tid for tid in task_ids if tid.isdigit()}, key=int, reverse=True)
            logger.info(f"找到 {len(task_ids)} 个 task_id")
            if task_ids:
                logger.info(f"范围: {task_ids[-1]} ~ {task_ids[0]}")
            self._task_ids_cache = task_ids
            return task_ids
        except Exception as e:
            logger.error(f"获取 task_id 失败: {e}")
            return []

    def scan_task_directory(self, task_id, package, version):
        """扫描单个 task 目录，查找目标包"""
        target_url = f"{self.base_url}/tasks/{task_id}/{self.subdir}/"
        try:
            resp = self.session.get(target_url, timeout=30)
            if resp.status_code != 200:
                return []

            # 提取所有 .deb 文件
            deb_files = re.findall(r'href="([^"]+\.deb)"', resp.text)

            # 筛选目标包（主包和 dbgsym 包）
            target_files = []
            for deb_file in deb_files:
                # 使用前缀匹配版本（支持 epoch:version 或 version 或 version-1 格式）
                if version:
                    # 主包匹配：package_version_arch.deb
                    # 去掉 version 中的 epoch（前缀的数字+冒号）
                    clean_version = version.split(':')[-1] if ':' in version else version
                    # 去掉 -1 后缀（Debian 版本格式）
                    base_version = clean_version.rsplit('-', 1)[0] if clean_version.endswith('-1') else clean_version

                    # 尝试多种版本格式匹配
                    version_formats = [
                        version,           # 原始版本
                        clean_version,     # 去掉 epoch
                        base_version,     # 去掉 -1
                    ]

                    matched = False
                    for v in version_formats:
                        if deb_file == f"{package}_{v}_{self.arch}.deb" or \
                           deb_file == f"{package}-dbgsym_{v}_{self.arch}.deb":
                            target_files.append(deb_file)
                            matched = True
                            break

                    # 如果没精确匹配，尝试前缀匹配（模糊匹配）
                    if not matched:
                        if self._matches_version_prefix(deb_file, f"{package}_", version) or \
                           self._matches_version_prefix(deb_file, f"{package}-dbgsym_", version):
                            target_files.append(deb_file)
                else:
                    # 无版本时匹配所有版本
                    if (deb_file.startswith(f"{package}_") and deb_file.endswith(f"_{self.arch}.deb")) or \
                       (deb_file.startswith(f"{package}-dbgsym_") and deb_file.endswith(f"_{self.arch}.deb")):
                        target_files.append(deb_file)

            return target_files
        except Exception as e:
            logger.debug(f"扫描出错: {e}")
            return []

    def find_task_for_package(self, package, version):
        """查找包含目标包的 task_id，自动搜索所有 task"""
        task_ids = self.get_all_task_ids()
        if not task_ids:
            return None, []

        total_tasks = len(task_ids)
        logger.info(f"正在查找: {package} {version or '(所有版本)'} {self.arch}")
        logger.info(f"将扫描全部 {total_tasks} 个 task")

        for idx, task_id in enumerate(task_ids, 1):
            if idx % 500 == 0 or idx == 1:
                logger.info(f"  扫描进度: {idx}/{total_tasks} ({idx*100//total_tasks}%)...")

            target_files = self.scan_task_directory(task_id, package, version)
            if target_files:
                logger.info(f"  ✓ 在 task_id={task_id} 找到 {len(target_files)} 个文件")
                return task_id, target_files

        logger.warning(f"  ✗ 扫描全部 {total_tasks} 个 task 后未找到匹配的包")
        return None, []

    def download_file(self, task_id, filename):
        """下载单个文件"""
        # URL decode filename (e.g., %2B -> +)
        decoded_filename = unquote(filename)
        filepath = self.download_dir / decoded_filename

        if filepath.exists():
            logger.info(f"  文件已存在，跳过: {decoded_filename}")
            return True

        # 尝试多个可能的路径，使用URL解码后的文件名
        possible_paths = [
            f"/tasks/{task_id}/{self.subdir}/{decoded_filename}",
            f"/tasks/{task_id}/{decoded_filename}",
            f"/tasks/{task_id}/amd64/{decoded_filename}",
            f"/tasks/{task_id}/unstable/{decoded_filename}",
        ]

        for path in possible_paths:
            url = f"{self.base_url}{path}"
            try:
                # 先检查文件是否存在
                head_resp = self.session.head(url, timeout=10)
                if head_resp.status_code == 200:
                    logger.info(f"  下载: {url}")
                    return self._do_download(url, filepath, decoded_filename)
            except Exception:
                continue

        logger.error(f"  ✗ 无法找到文件: {decoded_filename}")
        return False

    def _do_download(self, url, filepath, filename):
        """执行下载"""
        for retry in range(MAX_RETRIES):
            try:
                resp = self.session.get(url, timeout=TIMEOUT, stream=True)
                resp.raise_for_status()

                downloaded = 0
                with open(filepath, 'wb') as f:
                    for chunk in resp.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
                            downloaded += len(chunk)

                file_size = downloaded / 1024 / 1024
                logger.info(f"  ✓ 下载完成: {filename} ({file_size:.2f}MB)")
                self.downloaded_files.append(filename)
                return True

            except Exception as e:
                logger.warning(f"  ⚠ 下载重试 {retry + 1}/{MAX_RETRIES}: {e}")
                if retry < MAX_RETRIES - 1:
                    time.sleep(2 * (retry + 1))

        return False

    def download_package(self, package, version=None):
        """下载指定包"""
        logger.info("=" * 60)
        logger.info(f"下载任务: {package} {version or '(所有版本)'} {self.arch}")
        logger.info("=" * 60)

        task_id, target_files = self.find_task_for_package(package, version)

        if not task_id:
            logger.error(f"未找到包: {package} {version}")
            return False

        success = True
        for filename in target_files:
            if not self.download_file(task_id, filename):
                success = False

        return success

    def download_batch(self, tasks):
        """批量下载多个包"""
        logger.info("=" * 60)
        logger.info(f"开始批量下载，共 {len(tasks)} 个任务")
        logger.info("=" * 60)

        total_success = 0
        total_failed = 0

        for idx, task in enumerate(tasks, 1):
            package = task['package']
            version = task.get('version')
            arch = task.get('arch', self.arch)

            logger.info(f"\n[{idx}/{len(tasks)}] 处理: {package} {version or '(所有版本)'} {arch}")

            # 如果架构不同，需要重新配置
            if arch != self.arch:
                logger.warning(f"  架构不匹配: 任务需要 {arch}，当前配置为 {self.arch}，跳过")
                total_failed += 1
                continue

            if self.download_package(package, version):
                total_success += 1
            else:
                total_failed += 1

        logger.info("\n" + "=" * 60)
        logger.info("批量下载完成")
        logger.info(f"  ✓ 成功: {total_success}")
        logger.info(f"  ✗ 失败: {total_failed}")
        logger.info(f"  下载目录: {self.download_dir}")
        logger.info("=" * 60)

        return total_success, total_failed


def parse_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        description='从内部构建服务器下载 deb 包和调试包',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
使用示例:

  # 下载单个包的所有版本
  python3 %(prog)s dde-control-center

  # 下载指定版本
  python3 %(prog)s dde-control-center 5.9.8-1

  # 下载指定版本和架构
  python3 %(prog)s dde-control-center 5.9.8-1 amd64

  # 批量下载（从 JSON 文件）
  python3 %(prog)s --batch download_tasks.json

  # 批量下载（多次指定参数）
  python3 %(prog)s dde-control-center 5.9.8-1 dde-control-center 5.9.7-1

  # 指定下载目录
  python3 %(prog)s -d ./my_downloads dde-control-center 5.9.8-1

  # 指定架构和子目录
  python3 %(prog)s -a arm64 -s unstable-arm64 dde-control-center 5.9.8-1
'''
    )

    # 位置参数：包名和版本（支持多个）
    parser.add_argument(
        'packages',
        nargs='*',
        help='包名和版本，格式：包名 [版本] [包名 [版本] ...]'
    )

    # 批量下载文件
    parser.add_argument(
        '-b', '--batch',
        help='从 JSON 文件批量下载任务'
    )

    # 下载目录
    parser.add_argument(
        '-d', '--download-dir',
        default=DEFAULT_DOWNLOAD_DIR,
        help=f'下载目录 (默认: {DEFAULT_DOWNLOAD_DIR})'
    )

    # 架构
    parser.add_argument(
        '-a', '--arch',
        default=DEFAULT_ARCH,
        help=f'架构 (默认: {DEFAULT_ARCH})'
    )

    # 子目录
    parser.add_argument(
        '-s', '--subdir',
        default=DEFAULT_SUBDIR,
        help=f'子目录 (默认: {DEFAULT_SUBDIR})'
    )

    # 服务器地址
    parser.add_argument(
        '-u', '--url',
        default=DEFAULT_BASE_URL,
        help=f'服务器地址 (默认: {DEFAULT_BASE_URL})'
    )

    return parser.parse_args()


def main():
    args = parse_args()
    configure_logging(args.download_dir)

    # 创建下载器
    downloader = DebDownloader(
        base_url=args.url,
        download_dir=args.download_dir,
        arch=args.arch,
        subdir=args.subdir
    )

    tasks = []

    # 从批量文件读取任务
    if args.batch:
        try:
            with open(args.batch, 'r', encoding='utf-8') as f:
                data = json.load(f)
                if 'tasks' in data:
                    tasks.extend(data['tasks'])
                elif isinstance(data, list):
                    tasks.extend(data)
                else:
                    logger.error(f"无法解析批量文件格式: {args.batch}")
                    sys.exit(1)
            logger.info(f"从 {args.batch} 加载了 {len(tasks)} 个任务")
        except Exception as e:
            logger.error(f"读取批量文件失败: {e}")
            sys.exit(1)

    # 从命令行参数解析任务
    if args.packages:
        i = 0
        while i < len(args.packages):
            package = args.packages[i]
            i += 1

            # 检查下一个参数是否是版本号（不是包名）
            version = None
            if i < len(args.packages):
                next_arg = args.packages[i]
                # 如果下一个参数不以常见包名前缀开头，认为是版本号
                if not next_arg.startswith(('lib', 'python', 'node', 'dde-', 'deepin-')):
                    version = next_arg
                    i += 1

            tasks.append({
                'package': package,
                'version': version,
                'arch': args.arch
            })

    # 如果没有任务，显示帮助
    if not tasks:
        logger.error("未指定下载任务，请使用 -h 查看帮助")
        sys.exit(1)

    # 执行下载
    if len(tasks) == 1:
        # 单个任务
        task = tasks[0]
        downloader.download_package(task['package'], task.get('version'))
    else:
        # 批量任务
        downloader.download_batch(tasks)


if __name__ == "__main__":
    main()
