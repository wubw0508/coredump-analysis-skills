# coredump-analysis-skills

DDE/UOS 崩溃数据分析工具集，提供从数据下载、筛选去重、源码管理、包管理到崩溃分析的完整流程。

## Agent 使用（推荐）

使用崩溃分析 Agent，一键执行完整分析流程：

```bash
cd ~/.claude/skills/coredump-analysis-skills

# 分析 dde-session-ui 最近一个月崩溃 (x86)
bash run_analysis_agent.sh --package dde-session-ui --start-date 2026-03-14 --end-date 2026-04-14

# 分析 dde-session-ui arm64 架构
bash run_analysis_agent.sh --package dde-session-ui --arch arm64 --start-date 2026-03-14 --end-date 2026-04-14

# 后台运行
bash run_analysis_agent.sh --package dde-session-ui --background

# 查看帮助
bash run_analysis_agent.sh --help
```

**Agent 特点**：
- 一键执行完整分析流程（下载→筛选→统计）
- 支持多架构（x86, x86_64, arm64）
- 支持自定义日期范围、系统版本
- 后台运行模式
- 自动使用预设账号

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
python3 coredump-full-analysis/scripts/setup_accounts.py

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

## 技能打包与安装

将技能打包成分发文件，或从 .skill 文件安装技能。

### 打包技能

```bash
# 列出所有可用技能
python3 package_skills.py --list

# 打包完整套装（推荐）
# 包含 6 个 skills + agent + 打包工具
python3 package_skills.py --bundle

# 打包所有技能（各自独立）
python3 package_skills.py --all

# 打包单个技能
python3 package_skills.py coredump-data-filter
```

### 安装技能

```bash
# 查看 .skill 文件内容
python3 install_skill.py coredump-data-filter.skill --list

# 安装 .skill 文件
python3 install_skill.py coredump-data-filter.skill

# 批量安装目录中的所有 .skill 文件
python3 install_skill.py /path/to/skills/ --batch
```

### 分发文件

| 文件 | 大小 | 说明 |
|------|------|------|
| `coredump-analysis-skills-bundle.skill` | ~172 KB | 完整套装（推荐） |
| `coredump-*.skill` | ~5-98 KB | 各技能独立打包 |

**推荐使用完整套装** (`--bundle`)，包含所有 skills 和 agent，可独立完整运行。

### .skill 文件格式

`.skill` 文件是 ZIP 压缩包，包含技能目录结构：
- SKILL.md（必需）
- scripts/（可选）
- references/（可选）
- agent/（完整套装包含）

### 打包规则

以下文件会被自动排除：`__pycache__`、`.git`、`.pyc`、`.log`、`accounts.json`

## 目录结构

```
coredump-analysis-skills/
├── accounts.json                          # 账号配置文件（必需）
├── run_analysis_agent.sh                   # 一键分析入口脚本
├── package_skills.py                      # 打包技能为 .skill 文件
├── install_skill.py                       # 从 .skill 文件安装技能
├── coredump-data-download/       # 数据下载
├── coredump-data-filter/         # 数据筛选去重
├── coredump-code-management/     # 源码管理
├── coredump-package-management/  # 包管理
├── coredump-crash-analysis/      # 崩溃分析
└── coredump-full-analysis/       # 完整流程
```

## 账号配置（必需）

首次使用前，必须配置 `accounts.json`：

```bash
cd ~/.claude/skills/coredump-analysis-skills
python3 coredump-full-analysis/scripts/setup_accounts.py
```

或直接编辑 `accounts.json`（项目根目录）。

**关键配置项**：
- `shuttle.account` — Shuttle 下载账号
- `gerrit.account` — Gerrit 代码仓库账号
- `system.sudo_password` — 当前用户密码（用于安装调试符号）

**运行前检查**：`run_analysis_agent.sh` 会自动检测 `accounts.json` 是否包含未填写的占位符，若未配置则报错退出。
