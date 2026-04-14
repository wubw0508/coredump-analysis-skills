#!/usr/bin/env python3
"""
账号配置管理脚本
支持交互式配置和默认值，用于 coredump 全流程分析

用法:
    python3 setup_accounts.py                    # 交互式配置
    python3 setup_accounts.py --show             # 显示当前配置
    python3 setup_accounts.py --accounts <file>   # 从文件加载配置
"""

import json
import os
import sys
import argparse
from pathlib import Path

# 默认配置
DEFAULT_CONFIG = {
    "shuttle": {
        "name": "Shuttle UnionTech",
        "description": "用于从 shuttle.uniontech.com 下载 deb 包",
        "url": "https://shuttle.uniontech.com",
        "api_url": "https://shuttle.uniontech.com/api/download",
        "account": {
            "username": "",
            "password": ""
        }
    },
    "metabase": {
        "name": "Metabase",
        "description": "用于下载崩溃数据",
        "url": "https://metabase.cicd.getdeepin.org",
        "api_session": "/api/session",
        "api_dataset": "/api/dataset",
        "account": {
            "username": "app@deepin.org",
            "password": "deepin123"
        },
        "database": {
            "id": 10,
            "source_table_id": 196
        }
    },
    "gerrit": {
        "name": "Gerrit",
        "description": "用于下载和管理代码仓库",
        "host": "gerrit.uniontech.com",
        "port": "29418",
        "account": {
            "username": "",
            "password": ""
        },
        "ssh_key": "~/.ssh/id_rsa"
    },
    "internal_server": {
        "name": "内部构建服务器",
        "description": "用于从内部构建服务器下载 deb 包和 dbgsym",
        "url": "http://10.0.32.60:5001",
        "tasks_endpoint": "/tasks/"
    },
    "system": {
        "name": "系统配置",
        "description": "系统级配置",
        "sudo_password": ""
    },
    "paths": {
        "workspace": "",
        "code_dir": "",
        "download_dir": ""
    }
}

# 配置文件路径
SCRIPT_DIR = Path(__file__).parent.resolve()
CONFIG_DIR = SCRIPT_DIR.parent / "config"
ACCOUNTS_FILE = CONFIG_DIR / "accounts.json"
CENTRALIZED_CONFIG = CONFIG_DIR / "centralized_config.json"


def print_header():
    print("=" * 70)
    print("           Coredump 崩溃分析 - 账号配置管理")
    print("=" * 70)
    print()


def print_section(title):
    print()
    print("-" * 70)
    print(f"  {title}")
    print("-" * 70)


def prompt_input(prompt_text, default="", is_password=False):
    """提示用户输入，支持默认值"""
    if is_password:
        import getpass
        value = getpass.getpass(f"  {prompt_text}")
        if not value:
            return default
    else:
        value = input(f"  {prompt_text} [{default}]: ").strip()
        if not value:
            return default
    return value


def load_accounts():
    """加载账号配置"""
    if ACCOUNTS_FILE.exists():
        with open(ACCOUNTS_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    return None


def save_accounts(config):
    """保存账号配置"""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(ACCOUNTS_FILE, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"\n配置已保存到: {ACCOUNTS_FILE}")


def generate_env_files(config):
    """生成各服务的 .env 文件"""
    # Metabase 配置
    metabase_env = f'''# Metabase 配置
METABASE_BASE_URL="{config.get("metabase", {}).get("url", "https://metabase.cicd.getdeepin.org")}"
METABASE_USERNAME="{config.get("metabase", {}).get("account", {}).get("username", "")}"
METABASE_PASSWORD="{config.get("metabase", {}).get("account", {}).get("password", "")}"
METABASE_DATABASE_ID="{config.get("metabase", {}).get("database", {}).get("id", 10)}"
'''
    with open(CONFIG_DIR / "metabase.env", 'w', encoding='utf-8') as f:
        f.write(metabase_env)
    print(f"  生成: {CONFIG_DIR}/metabase.env")

    # Gerrit 配置
    gerrit_env = f'''# Gerrit 配置
GERRIT_HOST="{config.get("gerrit", {}).get("host", "gerrit.uniontech.com")}"
GERRIT_PORT="{config.get("gerrit", {}).get("port", 29418)}"
GERRIT_USER="{config.get("gerrit", {}).get("account", {}).get("username", "")}"
GERRIT_PASSWORD="{config.get("gerrit", {}).get("account", {}).get("password", "")}"
GERRIT_SSH_KEY="{config.get("gerrit", {}).get("ssh_key", "~/.ssh/id_rsa")}"
'''
    with open(CONFIG_DIR / "gerrit.env", 'w', encoding='utf-8') as f:
        f.write(gerrit_env)
    print(f"  生成: {CONFIG_DIR}/gerrit.env")

    # Shuttle 配置
    shuttle_env = f'''# Shuttle 配置
SHUTTLE_URL="{config.get("shuttle", {}).get("url", "https://shuttle.uniontech.com")}"
SHUTTLE_API_URL="{config.get("shuttle", {}).get("api_url", "https://shuttle.uniontech.com/api/download")}"
SHUTTLE_USERNAME="{config.get("shuttle", {}).get("account", {}).get("username", "")}"
SHUTTLE_PASSWORD="{config.get("shuttle", {}).get("account", {}).get("password", "")}"
'''
    with open(CONFIG_DIR / "shuttle.env", 'w', encoding='utf-8') as f:
        f.write(shuttle_env)
    print(f"  生成: {CONFIG_DIR}/shuttle.env")

    # Package Server 配置
    package_env = f'''# 内部构建服务器配置
PACKAGE_SERVER_URL="{config.get("internal_server", {}).get("url", "http://10.0.32.60:5001")}"
PACKAGE_SERVER_TASKS_ENDPOINT="{config.get("internal_server", {}).get("tasks_endpoint", "/tasks/")}"
'''
    with open(CONFIG_DIR / "package-server.env", 'w', encoding='utf-8') as f:
        f.write(package_env)
    print(f"  生成: {CONFIG_DIR}/package-server.env")

    # System 配置
    system_env = f'''# 系统配置
SUDO_PASSWORD="{config.get("system", {}).get("sudo_password", "")}"
'''
    with open(CONFIG_DIR / "system.env", 'w', encoding='utf-8') as f:
        f.write(system_env)
    print(f"  生成: {CONFIG_DIR}/system.env")

    # Local paths 配置
    workspace = config.get("paths", {}).get("workspace", os.getcwd())
    local_env = f'''# 本地路径配置
WORKSPACE="{workspace}"
CODE_DIR="{config.get("paths", {}).get("code_dir", workspace + "/3.代码管理")}"
DOWNLOAD_DIR="{config.get("paths", {}).get("download_dir", workspace + "/4.包管理/下载包/downloads")}"
'''
    with open(CONFIG_DIR / "local.env", 'w', encoding='utf-8') as f:
        f.write(local_env)
    print(f"  生成: {CONFIG_DIR}/local.env")

    # Centralized config
    with open(CENTRALIZED_CONFIG, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"  生成: {CENTRALIZED_CONFIG}")


def check_required_config(config):
    """检查必要配置是否存在

    必需配置项:
    - shuttle.account.username, shuttle.account.password
    - gerrit.account.username, gerrit.account.password
    - paths.workspace
    """
    required = [
        ("shuttle.account.username", config.get("shuttle", {}).get("account", {}).get("username", "")),
        ("shuttle.account.password", config.get("shuttle", {}).get("account", {}).get("password", "")),
        ("gerrit.account.username", config.get("gerrit", {}).get("account", {}).get("username", "")),
        ("gerrit.account.password", config.get("gerrit", {}).get("account", {}).get("password", "")),
        ("paths.workspace", config.get("paths", {}).get("workspace", "")),
    ]

    missing = []
    for name, value in required:
        if not value:
            missing.append(name)

    return missing


def quick_setup():
    """简化的交互式配置，只收集必要信息

    必需配置:
    - Shuttle (https://shuttle.uniontech.com) 用户名/密码
    - Gerrit (gerrit.uniontech.com) 用户名/密码
    - workspace 路径
    """
    print_header()
    print("检测到缺少必要配置，请输入以下信息：")
    print("（其他账户信息将使用默认值）")
    print()

    config = DEFAULT_CONFIG.copy()

    # Shuttle 配置
    print_section("Shuttle 配置 (https://shuttle.uniontech.com)")
    print("  用于从 shuttle.uniontech.com 下载 deb 包")
    print()
    config["shuttle"]["account"]["username"] = prompt_input(
        "Shuttle 用户名",
        config["shuttle"]["account"].get("username", "")
    )
    config["shuttle"]["account"]["password"] = prompt_input(
        "Shuttle 密码",
        config["shuttle"]["account"].get("password", ""),
        is_password=True
    )

    # Gerrit 配置
    print_section("Gerrit 配置 (gerrit.uniontech.com)")
    print("  用于下载和管理代码仓库")
    print()
    config["gerrit"]["account"]["username"] = prompt_input(
        "Gerrit 用户名",
        config["gerrit"]["account"].get("username", "")
    )
    config["gerrit"]["account"]["password"] = prompt_input(
        "Gerrit 密码",
        config["gerrit"]["account"].get("password", ""),
        is_password=True
    )

    # Workspace 配置
    print_section("工作路径配置")
    print("  用于存放分析数据、源码、下载包等")
    print()
    default_workspace = os.path.join(os.path.expanduser("~"), "coredump_workspace")
    config["paths"]["workspace"] = prompt_input(
        "工作目录路径",
        config["paths"].get("workspace", default_workspace)
    )
    # 自动设置子目录
    config["paths"]["code_dir"] = config["paths"]["workspace"] + "/3.代码管理"
    config["paths"]["download_dir"] = config["paths"]["workspace"] + "/4.包管理/下载包/downloads"

    return config


def interactive_setup():
    """完整的交互式配置（保留原有功能）"""
    print_header()
    print("首次使用需要配置账号信息，可使用默认值直接回车跳过")
    print()

    config = DEFAULT_CONFIG.copy()

    # Shuttle 配置
    print_section("Shuttle 配置 (用于下载 deb 包)")
    shuttle = config.get("shuttle", {})
    shuttle["url"] = prompt_input("Shuttle URL", shuttle.get("url", "https://shuttle.uniontech.com"))
    shuttle["api_url"] = prompt_input("Shuttle API URL", shuttle.get("api_url", "https://shuttle.uniontech.com/api/download"))
    shuttle["account"]["username"] = prompt_input("Shuttle 用户名", shuttle["account"].get("username", ""))
    shuttle["account"]["password"] = prompt_input("Shuttle 密码", shuttle["account"].get("password", ""), is_password=True)

    # Metabase 配置
    print_section("Metabase 配置 (用于下载崩溃数据)")
    metabase = config.get("metabase", {})
    metabase["url"] = prompt_input("Metabase URL", metabase.get("url", "https://metabase.cicd.getdeepin.org"))
    metabase["account"]["username"] = prompt_input("Metabase 用户名", metabase["account"].get("username", "app@deepin.org"))
    metabase["account"]["password"] = prompt_input("Metabase 密码", metabase["account"].get("password", ""), is_password=True)
    metabase["database"]["id"] = prompt_input("数据库 ID", str(metabase["database"].get("id", 10)))

    # Gerrit 配置
    print_section("Gerrit 配置 (用于下载源码)")
    gerrit = config.get("gerrit", {})
    gerrit["host"] = prompt_input("Gerrit Host", gerrit.get("host", "gerrit.uniontech.com"))
    gerrit["port"] = prompt_input("Gerrit Port", str(gerrit.get("port", 29418)))
    gerrit["account"]["username"] = prompt_input("Gerrit 用户名", gerrit["account"].get("username", ""))
    gerrit["account"]["password"] = prompt_input("Gerrit 密码", gerrit["account"].get("password", ""), is_password=True)
    gerrit["ssh_key"] = prompt_input("SSH 密钥路径", gerrit.get("ssh_key", "~/.ssh/id_rsa"))

    # Internal Server 配置
    print_section("内部构建服务器配置 (用于下载 deb/dbgsym)")
    internal = config.get("internal_server", {})
    internal["url"] = prompt_input("服务器 URL", internal.get("url", "http://10.0.32.60:5001"))
    internal["tasks_endpoint"] = prompt_input("Tasks Endpoint", internal.get("tasks_endpoint", "/tasks/"))

    # System 配置
    print_section("系统配置")
    system = config.get("system", {})
    system["sudo_password"] = prompt_input("Sudo 密码 (用于安装包)", system.get("sudo_password", ""), is_password=True)

    # Paths 配置
    print_section("路径配置")
    paths = config.get("paths", {})
    default_workspace = os.path.join(os.path.expanduser("~"), "workspace")
    paths["workspace"] = prompt_input("工作目录", paths.get("workspace", default_workspace))
    paths["code_dir"] = prompt_input("代码目录", paths.get("code_dir", paths["workspace"] + "/3.代码管理"))
    paths["download_dir"] = prompt_input("下载目录", paths.get("download_dir", paths["workspace"] + "/4.包管理/下载包/downloads"))

    return config


def show_config():
    """显示当前配置"""
    config = load_accounts()
    if not config:
        print("未找到配置，请先运行交互式配置: python3 setup_accounts.py")
        return

    print_header()
    print("当前配置:")
    print()

    # 隐藏密码显示
    def mask_password(obj):
        if isinstance(obj, dict):
            return {k: mask_password(v) if k != "password" else "********" for k, v in obj.items()}
        return obj

    print(json.dumps(mask_password(config), indent=2, ensure_ascii=False))
    print()
    print(f"配置文件位置: {ACCOUNTS_FILE}")


def main():
    parser = argparse.ArgumentParser(description='Coredump 账号配置管理')
    parser.add_argument('--show', action='store_true', help='显示当前配置')
    parser.add_argument('--accounts', type=str, help='从 JSON 文件加载配置')
    parser.add_argument('--workspace', type=str, help='设置工作目录')
    parser.add_argument('--non-interactive', action='store_true', help='使用默认配置')
    parser.add_argument('--quick', action='store_true', help='快速配置（只输入必要信息）')
    parser.add_argument('--check', action='store_true', help='检查配置完整性（用于脚本调用）')

    args = parser.parse_args()

    if args.show:
        show_config()
        return

    if args.check:
        # 检查模式：返回配置是否完整（用于脚本调用）
        config = load_accounts()
        if not config:
            print("MISSING: 配置文件不存在")
            sys.exit(1)
        missing = check_required_config(config)
        if missing:
            print(f"MISSING: {', '.join(missing)}")
            sys.exit(1)
        print("OK: 配置完整")
        sys.exit(0)

    if args.accounts:
        # 从文件加载配置
        with open(args.accounts, 'r', encoding='utf-8') as f:
            config = json.load(f)
        print(f"已从 {args.accounts} 加载配置")
    elif args.non_interactive:
        # 使用默认配置（不交互）
        config = DEFAULT_CONFIG.copy()
    elif args.quick:
        # 快速配置模式：只收集必要信息
        existing = load_accounts()
        if existing:
            # 使用现有配置作为默认值
            for key in DEFAULT_CONFIG:
                if key in existing:
                    if isinstance(DEFAULT_CONFIG[key], dict):
                        DEFAULT_CONFIG[key].update(existing[key])
            config = quick_setup()
        else:
            config = quick_setup()
    else:
        # 检查是否有现有配置
        existing = load_accounts()
        if existing:
            # 检查配置是否完整
            missing = check_required_config(existing)
            if missing:
                print(f"检测到缺少必要配置: {', '.join(missing)}")
                print("将进入快速配置模式...")
                print()
                # 使用现有配置作为默认值
                for key in DEFAULT_CONFIG:
                    if key in existing:
                        if isinstance(DEFAULT_CONFIG[key], dict):
                            DEFAULT_CONFIG[key].update(existing[key])
                config = quick_setup()
            else:
                print("发现现有完整配置，是否重新配置？")
                choice = input("  [y] 重新配置  [q] 快速配置  [其他] 使用现有配置: ").strip().lower()
                if choice == 'y':
                    config = interactive_setup()
                elif choice == 'q':
                    config = quick_setup()
                else:
                    print("使用现有配置")
                    config = existing
        else:
            # 无现有配置，进入快速配置
            print("未找到配置文件，进入快速配置模式...")
            print()
            config = quick_setup()

    # 如果指定了 workspace，覆盖配置
    if args.workspace:
        config.setdefault("paths", {})["workspace"] = args.workspace
        config["paths"]["code_dir"] = args.workspace + "/3.代码管理"
        config["paths"]["download_dir"] = args.workspace + "/4.包管理/下载包/downloads"

    # 保存配置
    save_accounts(config)

    # 生成各服务的 .env 文件
    print()
    print("生成配置文件...")
    generate_env_files(config)

    print()
    print("=" * 70)
    print("配置完成！")
    print("=" * 70)
    print()
    print("下一步:")
    print("  1. 运行完整分析: bash scripts/analyze_crash_complete.sh --package dde-session-shell")
    print("  2. 或分步执行各个 Skill")
    print()


if __name__ == "__main__":
    main()