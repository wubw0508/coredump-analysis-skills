# coredump-analysis-skills

DDE/UOS 崩溃数据分析工具集，提供从数据下载、筛选去重、源码管理、包管理到崩溃分析的完整流程。

## Skills 列表

| Skill | 功能 | 触发词示例 |
|-------|------|-----------|
| [coredump-data-download](./coredump-data-download) | 从 Metabase 下载崩溃数据 | 下载崩溃数据、Metabase下载 |
| [coredump-data-filter](./coredump-data-filter) | 崩溃数据去重和统计 | 去重崩溃数据、崩溃数据过滤 |
| [coredump-code-management](./coredump-code-management) | 从 Gerrit 拉取源码并切换版本 | 拉取源码、Gerrit克隆 |
| [coredump-package-management](./coredump-package-management) | 下载 deb 包和调试符号包 | 下载deb包、下载调试包 |
| [coredump-crash-analysis](./coredump-crash-analysis) | 崩溃堆栈分析和定位 | 崩溃分析、堆栈分析、GDB调试 |
| [coredump-full-analysis](./coredump-full-analysis) | 一站式完整分析流程 | 完整崩溃分析、自动化崩溃分析 |

## 快速开始

### 完整流程（推荐）

使用 `coredump-full-analysis` 一站式完成所有步骤：

```bash
# 1. 首次使用，配置账号
cd coredump-full-analysis/scripts
python3 setup_accounts.py

# 2. 执行完整分析
bash analyze_crash_complete.sh \
    --package dde-session-shell \
    --start-date 2026-03-10 \
    --end-date 2026-04-09 \
    --sys-version 1070-1075
```

### 分步执行

按需使用单个 Skill：

```bash
# 步骤1: 下载崩溃数据
cd coredump-data-download/scripts
./download_metabase_csv.sh --sys-version 1070-1075 dde-dock x86 crash

# 步骤2: 去重筛选
cd coredump-data-filter/scripts
python3 filter_crash_data.py dde-dock

# 步骤3: 克隆源码
cd coredump-code-management/scripts
./download_crash_source.sh ../../filtered_dde-dock_crash_data.csv 2

# 步骤4: 下载调试包
cd coredump-package-management/scripts
python3 scan_and_download.py dde-dock 5.7.16.1

# 步骤5: 崩溃分析
cd coredump-crash-analysis/scripts
python3 analyze_crash_final.py --package dde-dock
```

## 工作流程

```
崩溃数据下载 → 数据去重 → 源码拉取 → 包管理 → 崩溃分析 → 报告生成
     ↓            ↓          ↓          ↓          ↓
  Metabase     堆栈签名    Gerrit     Shuttle     GDB/addr2line
```

## 目录结构

```
coredump-analysis-skills/
├── coredump-data-download/       # 数据下载
├── coredump-data-filter/         # 数据筛选去重
├── coredump-code-management/     # 源码管理
├── coredump-package-management/  # 包管理
├── coredump-crash-analysis/      # 崩溃分析
└── coredump-full-analysis/       # 完整流程
```
