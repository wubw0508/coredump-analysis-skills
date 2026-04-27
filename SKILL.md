# coredump-analysis-skills

DDE/UOS 崩溃数据分析工具集，提供从数据下载、筛选去重、源码管理、包管理到崩溃分析的完整流程。

## ⚠️ 每次分析前必须检查账号配置

**`accounts.json` 是唯一的账号配置入口**，所有需要人工配置的数据都集中在这里。

**每次崩溃分析启动时，系统会自动检查 `accounts.json`**：
- ✅ Gerrit 用户名有效 → 正常执行分析
- ❌ Gerrit 用户名缺失或仍是占位符 → 中止并提示配置
- ⚠️ Shuttle、Gerrit 密码、sudo 密码缺失 → 给出警告但继续执行；无法安装调试包时会跳过 deb/dbgsym 下载与安装，仍基于崩溃数据生成分析报告

**accounts.json 文件路径**：
```
~/.openclaw/skills/coredump-analysis-skills/accounts.json
```

**如需更新账号**：
```bash
# 交互式编辑账号配置
python3 coredump-full-analysis/scripts/setup_accounts.py
```

**配置项说明**：
| 服务 | 字段 | 说明 |
|------|------|------|
| **Shuttle** | `shuttle.account` | 下载 deb/dbgsym 包（可选；无 sudo 安装能力时会跳过包下载） |
| **Gerrit** | `gerrit.account` | 克隆源码仓库（至少需要用户名；优先使用 SSH/本机凭据） |
| **Metabase** | `metabase.account` | 下载崩溃数据（已有默认账号） |
| **System** | `system.sudo_password` | 安装调试符号包时需要（可选；无密码且无免密 sudo 时跳过安装） |

> **提示**：迁移到新机器后、或长时间未使用后，首次分析前务必检查 `accounts.json` 中的账号是否过期或失效。
> **paths.workspace** 无需配置，每次分析自动创建带时间戳的目录。

---

## 目录结构

```
coredump-analysis-skills/
├── accounts.json                          # 账号配置文件（必需，每次分析前检查）
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

## Skills 列表

| Skill | 功能 | 触发词示例 |
|-------|------|-----------|
| [coredump-data-download](./coredump-data-download) | 从 Metabase 下载崩溃数据 | 下载崩溃数据、Metabase下载 |
| [coredump-data-filter](./coredump-data-filter) | 崩溃数据去重和统计 | 去重崩溃数据、崩溃数据过滤 |
| [coredump-code-management](./coredump-code-management) | 从 Gerrit 拉取源码并切换版本 | 拉取源码、Gerrit克隆 |
| [coredump-package-management](./coredump-package-management) | 下载 deb 包和调试符号包 | 下载deb包、下载调试包 |
| [coredump-crash-analysis](./coredump-crash-analysis) | 崩溃堆栈分析和定位 | 崩溃分析、堆栈分析、GDB调试 |
| [coredump-full-analysis](./coredump-full-analysis) | 一站式完整分析流程 | 完整崩溃分析、自动化崩溃分析 |

## 默认分析项目清单

**`packages.txt`** 文件包含24个默认分析项目。

全量分析时，系统自动读取此文件获取项目列表，逐个执行分析。

**指定项目时**，只分析指定项目，忽略此文件：
```bash
# 全量分析（读取 packages.txt）
bash run_analysis_agent.sh

# 指定单个项目（默认分析所有能下载的崩溃）
bash run_analysis_agent.sh --packages dde-dock

# 指定多个项目
bash run_analysis_agent.sh --packages dde-dock,dde-launcher
```

## 工作目录自动创建

**重要变更**：每次分析自动创建带时间戳的工作目录，无需手动指定或预先创建。

```
~/coredump-workspace-YYYYMMDD_HHMMSS/     # Agent 入口
~/coredump-workspace-YYYYMMDD-HHMMSS/     # 完整流程脚本入口
├── 1.数据下载/
├── 2.数据筛选/
├── 3.代码管理/
├── 4.包管理/
├── 5.崩溃分析/
├── 6.修复补丁/
└── 7.总结报告/
```

- **不指定 `--workspace`** → 自动创建带时间戳的 `~/coredump-workspace-*`
- **指定 `--workspace /path`** → 使用指定目录

## Agent 使用（⭐推荐）

使用崩溃分析 Agent，一键执行完整分析流程（自动创建时间戳工作目录）。当前默认行为是不传日期时下载并分析所有能取到的崩溃数据：

```bash
cd ~/.openclaw/skills/coredump-analysis-skills

# 全量分析：读取 packages.txt 中 24 个默认项目，分析所有能下载的崩溃
bash run_analysis_agent.sh

# 分析单个包所有能下载的崩溃 (x86)
bash run_analysis_agent.sh --packages dde-session-ui

# 分析指定日期范围内的崩溃
bash run_analysis_agent.sh --packages dde-session-ui --start-date 2026-03-14 --end-date 2026-04-14

# 分析 arm64 架构所有能下载的崩溃
bash run_analysis_agent.sh --packages dde-session-ui --arch arm64

# 后台运行
bash run_analysis_agent.sh --packages dde-session-ui --background

# 查看帮助
bash run_analysis_agent.sh --help
```

**Agent 特点**：
- ⭐ 一键执行完整分析流程（下载→筛选→源码→包→分析→报告）
- 默认不限制日期，分析所有能下载的崩溃数据
- `--start-date` / `--end-date` 仅作为可选过滤条件，可只传其中一个
- 全量多包顺序执行时，单个包失败会记录失败列表并继续分析后续包
- 支持多架构（x86, x86_64, arm64）
- 支持自定义日期范围、系统版本
- 后台运行模式
- 自动使用预设账号（分析前检查 Gerrit 用户名；其余账号缺失时降级继续）
- 无 sudo 密码且当前用户无免密 sudo 时，跳过 deb/dbgsym 下载与安装，仍生成数据筛选和 AI 分析报告
- deb/dbgsym 版本匹配支持 `-1`、`+build`、`.1-1` 等 Debian 构建后缀

## 快速开始

### 方式1: Agent 一键分析（⭐推荐）

```bash
# 1. ⚠️ 每次分析前检查账号是否有效
python3 coredump-full-analysis/scripts/setup_accounts.py --show

# 2. 使用 Agent 执行完整分析（默认所有能下载的数据）
bash run_analysis_agent.sh --packages dde-session-shell

# 3. 如需限制日期，再显式传入日期范围
bash run_analysis_agent.sh --packages dde-session-shell --start-date 2026-03-10 --end-date 2026-04-09
```

### 方式2: 手动完整流程（跳过 Agent 直接调用脚本）

```bash
# ⚠️ 每次分析前检查账号
python3 coredump-full-analysis/scripts/setup_accounts.py --show

# 执行完整分析（自动创建带时间戳的工作目录，默认所有能下载的数据）
bash coredump-full-analysis/scripts/analyze_crash_complete.sh \
    --package dde-session-shell \
    --sys-version 1070-1075

# 指定日期范围时再添加 --start-date / --end-date
bash coredump-full-analysis/scripts/analyze_crash_complete.sh \
    --package dde-session-shell \
    --start-date 2026-03-10 \
    --end-date 2026-04-09 \
    --sys-version 1070-1075
```

### 方式3: 分步执行

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

## 当前默认行为

- **日期范围**：不传 `--start-date` / `--end-date` 时，不再默认最近 7 天或最近 30 天，而是下载接口当前能返回的全部崩溃数据。
- **多包全量**：`bash run_analysis_agent.sh` 会读取 `packages.txt` 中 24 个默认项目逐个分析；某个包失败不会阻断后续包，最终会列出失败包。
- **报告位置**：每个包的独立报告位于 `<workspace>/5.崩溃分析/<package>/`，包括 `AI_analysis_report.md`、`full_analysis_report.md` 和各版本 `version_*/analysis_report.md`。
- **共享总结**：`<workspace>/7.总结报告/final_conclusion.md` 和 `summary_statistics.json` 是当前包的总结文件，多包顺序分析时会被后续包覆盖；以每个包目录下的报告作为主要产物。
- **无 sudo 降级**：没有有效 `system.sudo_password` 且用户无免密 sudo 时，脚本跳过 deb/dbgsym 下载和安装，不再卡在 sudo 密码提示。
- **源码失败降级**：源码克隆或版本 tag 不可用时，脚本仍基于已下载和筛选的崩溃数据生成分析报告。

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

## 账号配置补充

**⚠️ `accounts.json` 是唯一的账号配置入口**，所有需要人工配置的数据都集中在这里。

首次使用前配置账号：
```bash
python3 coredump-full-analysis/scripts/setup_accounts.py
```

账号配置文件路径：
```
~/.openclaw/skills/coredump-analysis-skills/accounts.json
```

**关键配置项**：
- `shuttle.account` — Shuttle 下载账号（可选；无 sudo 安装能力时跳过 deb/dbgsym）
- `gerrit.account` — Gerrit 代码仓库账号（至少需要用户名）
- `metabase.account` — Metabase 崩溃数据账号
- `system.sudo_password` — 本机 sudo 密码（可选；无密码且无免密 sudo 时跳过安装调试符号）

**自动检查**：每次分析启动时自动检查 `accounts.json`。Gerrit 用户名缺失会中止；Shuttle、Gerrit 密码或 sudo 密码缺失只警告并降级继续。
