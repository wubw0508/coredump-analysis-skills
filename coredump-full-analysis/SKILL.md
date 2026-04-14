---
name: coredump-full-analysis
description: 一站式崩溃分析自动化流程。组合6个Skills完成从下载崩溃数据、筛选去重、克隆源码、下载包、安装调试符号、到生成崩溃分析报告的完整流程。触发词：完整崩溃分析、一站式崩溃分析、全流程崩溃分析、自动化崩溃分析。
---

# Coredump 完整崩溃分析自动化流程

一站式崩溃分析自动化流程，组合使用6个Skills完成从下载数据到生成报告的全流程。

## 目录结构

```
coredump-full-analysis/
├── SKILL.md                           # 本文件
├── scripts/
│   ├── setup_accounts.py              # 账号配置管理脚本 (新增)
│   ├── analyze_crash_complete.sh       # 一站式分析脚本
│   ├── step1_download.sh               # 步骤1: 数据下载
│   ├── step2_filter.sh                # 步骤2: 数据筛选
│   ├── step3_source.sh                # 步骤3: 代码管理
│   ├── step4_packages.sh              # 步骤4: 包管理
│   └── step5_analyze.sh               # 步骤5: 崩溃分析
├── config/                           # 配置文件 (自动生成)
│   ├── metabase.env                   # Metabase配置
│   ├── gerrit.env                     # Gerrit配置
│   ├── shuttle.env                    # Shuttle配置
│   ├── package-server.env             # 内部服务器配置
│   ├── system.env                     # 系统配置
│   └── local.env                      # 本地路径配置
├── centralized/
│   └── accounts.template.json         # 账号配置模板
└── references/
    └── ...                            # 参考文档
```

## 快速开始

### 1. 配置账号信息 (首次使用必需)

```bash
cd /home/wubw/skills/coredump-full-analysis/scripts
python3 setup_accounts.py
```

**交互式配置流程**：
- 系统会提示输入各服务账号信息
- 直接回车使用默认值（方括号中的值）
- 支持的配置项：
  - **Shuttle**: deb包下载账号
  - **Metabase**: 崩溃数据下载账号
  - **Gerrit**: 源码仓库访问账号
  - **Internal Server**: 内部构建服务器
  - **System**: sudo密码等系统配置
  - **Paths**: 工作目录路径配置

**非交互式配置**：
```bash
# 使用默认配置
python3 setup_accounts.py --non-interactive

# 从JSON文件加载
python3 setup_accounts.py --accounts ../centralized/accounts.template.json

# 设置工作目录
python3 setup_accounts.py --workspace /home/wubw/workspace
```

**显示当前配置**：
```bash
python3 setup_accounts.py --show
```

### 2. 一键执行完整分析

```bash
bash /home/wubw/skills/coredump-full-analysis/scripts/analyze_crash_complete.sh \
    --package dde-session-shell \
    --start-date 2026-03-10 \
    --end-date 2026-04-09 \
    --sys-version 1070-1075 \
    --workspace /home/wubw/workspace
```

## 配置说明

### 配置文件位置

配置自动生成到 `config/` 目录：

| 文件 | 说明 |
|------|------|
| `metabase.env` | Metabase API 认证信息 |
| `gerrit.env` | Gerrit SSH 和认证信息 |
| `shuttle.env` | Shuttle API 认证信息 |
| `package-server.env` | 内部构建服务器地址 |
| `system.env` | 系统配置 (sudo密码等) |
| `local.env` | 工作目录路径 |

### 账号配置模板

配置文件模板位于 `centralized/accounts.template.json`：

```json
{
  "shuttle": {
    "url": "https://shuttle.uniontech.com",
    "api_url": "https://shuttle.uniontech.com/api/download",
    "account": {
      "username": "ut000168",
      "password": "wubowen~123"
    }
  },
  "metabase": {
    "url": "https://metabase.cicd.getdeepin.org",
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
    "host": "gerrit.uniontech.com",
    "port": 29418,
    "account": {
      "username": "ut000168",
      "password": "wubowen~123"
    },
    "ssh_key": "~/.ssh/id_rsa"
  },
  "internal_server": {
    "url": "http://10.0.32.60:5001",
    "tasks_endpoint": "/tasks/"
  },
  "system": {
    "sudo_password": ""
  },
  "paths": {
    "workspace": "/home/wubw/workspace",
    "code_dir": "/home/wubw/workspace/3.代码管理",
    "download_dir": "/home/wubw/workspace/4.包管理/下载包/downloads"
  }
}
```

### 配置项说明

| 服务 | 必需配置 | 默认值 |
|------|---------|--------|
| **Shuttle** | username, password | - |
| **Metabase** | username, password | app@deepin.org / deepin123 |
| **Gerrit** | username | - |
| **Internal Server** | url | http://10.0.32.60:5001 |
| **System** | sudo_password | 空 |
| **Paths** | workspace | 当前目录 |

## 使用方法

### 方式1: 一键执行（推荐）

```bash
bash /home/wubw/skills/coredump-full-analysis/scripts/analyze_crash_complete.sh \
    --package dde-session-shell \
    --start-date 2026-04-01 \
    --end-date 2026-04-08
```

### 方式2: 分步执行

```bash
# 步骤1: 下载数据
bash scripts/step1_download.sh --package dde-session-shell --start-date 2026-04-01 --end-date 2026-04-08

# 步骤2: 筛选数据
bash scripts/step2_filter.sh --package dde-session-shell

# 步骤3: 克隆源码
bash scripts/step3_source.sh --package dde-session-shell

# 步骤4: 下载包
bash scripts/step4_packages.sh --package dde-session-shell

# 步骤5: 崩溃分析
bash scripts/step5_analyze.sh --package dde-session-shell
```

## 命令行参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--package <name>` | 包名（必需） | - |
| `--start-date <date>` | 开始日期 | 7天前 |
| `--end-date <date>` | 结束日期 | 今天 |
| `--sys-version <ver>` | 系统版本 | 1070-1075 |
| `--workspace <dir>` | 工作目录 | ./workspace |

## 6个Skills对应关系

| 步骤 | Skill | 功能 | 脚本 |
|------|-------|------|------|
| 1 | coredump-data-download | 从Metabase下载崩溃数据 | step1_download.sh |
| 2 | coredump-data-filter | 数据筛选/去重/统计 | step2_filter.sh |
| 3 | coredump-code-management | 从Gerrit克隆源码 | step3_source.sh |
| 4 | coredump-package-management | 下载deb/dbgsym包 | step4_packages.sh |
| 5 | coredump-crash-analysis | GDB堆栈分析/定位 | step5_analyze.sh |
| 6 | coredump-full-analysis | 组合以上5个流程 | analyze_crash_complete.sh |

## 执行流程图

```
┌─────────────────────────────────────────────────────────────────┐
│  配置账号信息 (首次使用)                                          │
│  python3 setup_accounts.py                                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  步骤1: coredump-data-download                                   │
│  从Metabase下载崩溃数据CSV                                       │
│  → 输出: download_*/<package>_X86_crash_*.csv                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  步骤2: coredump-data-filter                                     │
│  基于堆栈签名去重，生成版本/信号统计                              │
│  → 输出: filtered_<package>_crash_data.csv                       │
│  → 输出: <package>_crash_statistics.json                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  步骤3: coredump-code-management                                │
│  从Gerrit克隆源码仓库                                            │
│  → 输出: <package>/ (git仓库)                                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  步骤4: coredump-package-management                             │
│  从Shuttle下载deb包和dbgsym调试符号                              │
│  → 输出: downloads/                                              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  步骤5: coredump-crash-analysis                                 │
│  GDB堆栈分析，定位崩溃原因，生成修复建议                          │
│  → 输出: <package>_crash_analysis_report.md                      │
└─────────────────────────────────────────────────────────────────┘
```

## 输出文件

| 文件 | 说明 |
|------|------|
| `workspace/1.数据下载/download_*/<package>_X86_crash_*.csv` | 原始崩溃数据 |
| `workspace/2.数据筛选/filtered_<package>_crash_data.csv` | 去重后数据 |
| `workspace/2.数据筛选/<package>_crash_statistics.json` | 统计报告 |
| `workspace/3.代码管理/<package>/` | 源码仓库 |
| `workspace/4.包管理/downloads/` | 下载的deb/dbgsym包 |
| `workspace/5.崩溃分析/<package>_crash_analysis_report.md` | 分析报告 |

## 统计报告JSON结构

```json
{
  "summary": {
    "total_records": 64247,
    "unique_crashes": 120,
    "duplicate_count": 64127
  },
  "by_version": {
    "5.8.14-1": 769,
    "5.7.30-1": 363
  },
  "by_signal": {
    "SIGSEGV": 1896,
    "SIGABRT": 79
  },
  "top_crashes": [
    {
      "rank": 1,
      "count": 45,
      "signal": "SIGSEGV",
      "version": "5.8.14-1",
      "app_layer_symbol": "QWidget::show"
    }
  ]
}
```

## 注意事项

1. **首次运行**：必须先运行 `python3 setup_accounts.py` 配置账号
2. **SSH密钥**：确保Gerrit SSH密钥配置正确
3. **网络要求**：需要访问Metabase、Gerrit、Shuttle服务器
4. **磁盘空间**：大数据量可能占用数GB空间
5. **执行时间**：取决于数据量，通常5-30分钟

## 故障排除

**Q: 配置脚本提示权限错误**
```bash
chmod +x setup_accounts.py
```

**Q: Gerrit克隆失败**
- 检查SSH密钥: `ls -la ~/.ssh/id_rsa`
- 测试连接: `ssh -T gerrit.uniontech.com`

**Q: 数据下载为空**
- 检查Metabase配置是否正确
- 放宽日期范围或系统版本过滤条件

**Q: 包下载失败**
- 检查Shuttle服务器地址是否可达
- 确认账户密码正确

## 相关文档

- `centralized/accounts.template.json` - 账号配置模板
- `config/` - 各服务配置文件 (自动生成)
