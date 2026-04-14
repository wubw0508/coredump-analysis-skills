#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 shuttle.uniontech.com 下载 deb 包 (使用POST请求)
"""

import json
import requests
from pathlib import Path

# 配置
SCRIPT_DIR = Path(__file__).parent
COOKIE_FILE = SCRIPT_DIR / "cookie.txt"
DOWNLOAD_DIR = SCRIPT_DIR / "downloads_shuttle"
API_URL = "https://shuttle.uniontech.com/api/download"

# 读取cookie
with open(COOKIE_FILE, 'r') as f:
    cookie = f.read().strip()


def get_download_url(package, version, arch):
    """获取下载链接"""
    # 构建POST请求体
    payload = {
        "package": package,
        "version": version,
        "arch": arch
    }

    headers = {
        "Cookie": cookie,
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
        "Content-Type": "application/json"
    }

    print(f"[请求] {package} {version} {arch}")
    print(f"  Payload: {payload}")

    try:
        response = requests.post(API_URL, json=payload, headers=headers, timeout=60)

        print(f"  状态码: {response.status_code}")
        print(f"  响应头: {dict(response.headers)}")

        if response.status_code == 200:
            # 响应可能是下载链接或直接是文件内容
            content_type = response.headers.get('Content-Type', '')
            disposition = response.headers.get('Content-Disposition', '')

            # 检查是否是文件下载
            if 'attachment' in disposition or 'application/octet-stream' in content_type or 'application/vnd.debian.binary-package' in content_type:
                print(f"  ✓ 直接下载文件")
                return response.content, "direct"

            # 否则需要解析JSON获取下载链接
            result = response.json()

            if result.get("status") == "success" and result.get("url"):
                print(f"  ✓ 获取下载链接: {result['url']}")
                return result['url'], "redirect"
            elif result.get("status") == "success" and result.get("download_url"):
                print(f"  ✓ 获取下载链接: {result['download_url']}")
                return result['download_url'], "redirect"
            else:
                print(f"  ✗ 响应: {result}")
                return None, None
        else:
            print(f"  ✗ 请求失败")
            print(f"  响应: {response.text[:500]}")
            return None, None

    except Exception as e:
        print(f"  ✗ 错误: {e}")
        import traceback
        traceback.print_exc()
        return None, None


def download_package(package, version, arch, suffix=""):
    """下载指定包"""
    actual_package = f"{package}{suffix}" if suffix else package
    filename = f"{actual_package}_{version}_{arch}.deb"
    filepath = DOWNLOAD_DIR / filename

    if filepath.exists():
        print(f"[跳过] {filename} 已存在")
        return True

    # 获取下载链接或内容
    result, result_type = get_download_url(actual_package, version, arch)

    if not result:
        print(f"    ✗ 未获取到下载内容")
        return False

    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

    if result_type == "direct":
        # 直接保存响应内容
        with open(filepath, 'wb') as f:
            f.write(result)
        print(f"    ✓ 保存文件: {filename}")
        return True
    else:
        # 下载链接
        headers = {
            "Cookie": cookie,
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
        }

        print(f"    正在下载...")
        response = requests.get(result, headers=headers, timeout=300)

        if response.status_code == 200:
            with open(filepath, 'wb') as f:
                f.write(response.content)
            file_size = len(response.content)
            print(f"    ✓ 下载成功 ({file_size} bytes)")
            return True
        else:
            print(f"    ✗ 下载失败: HTTP {response.status_code}")
            return False


def main():
    print("=" * 60)
    print("从 shuttle.uniontech.com 下载包")
    print("=" * 60)

    # 读取下载任务
    tasks_file = SCRIPT_DIR / "download_tasks.json"
    with open(tasks_file, 'r') as f:
        tasks_data = json.load(f)

    tasks = tasks_data["tasks"]

    print(f"\n共有 {len(tasks)} 个下载任务\n")

    success = 0
    failed = 0
    not_found = 0

    for idx, task in enumerate(tasks, 1):
        package = task["package"]
        version = task["version"]
        arch = task["arch"]

        print(f"\n任务 {idx}/{len(tasks)}: {package}")

        # 下载主包
        result = download_package(package, version, arch, "")
        if result:
            success += 1
        else:
            not_found += 1

        # 下载调试包（尝试几种后缀）
        debug_suffixes = ["-dbgsym", "-dbg", "-debug"]
        for suffix in debug_suffixes:
            dresult = download_package(package, version, arch, suffix)
            if dresult:
                success += 1
            # 调试包可能不存在，不算失败也不算成功
            # 这里我们只统计主包的失败情况

    print("\n" + "=" * 60)
    print(f"下载完成: 成功 {success}, 未找到 {not_found}")
    print(f"下载目录: {DOWNLOAD_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    main()
