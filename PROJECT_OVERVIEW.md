# Coredump Analysis Skills 项目介绍

> 面向人类阅读的项目功能介绍。AI Agent 不需要主动加载本文；自动化执行和 Agent 路由以 `SKILL.md` 与 `references/` 中的专题文档为准。

## 这个项目解决什么问题

`coredump-analysis-skills` 用于自动化 DDE/UOS 桌面环境的 coredump 崩溃分析工作。它把原本需要人工串联的步骤整合成一套可重复执行的流程：下载崩溃数据、筛选去重、拉取源码、下载调试包、分析堆栈、尝试生成真实代码修复、汇总报告，并在满足条件时提交 Gerrit。

目标是让工程师可以从“某个包最近有哪些崩溃、哪些可修、哪些已有修复、哪些需要人工继续看”快速得到结构化结果。

## 主要能力

### 1. 崩溃数据下载

从内部 Metabase 查询 coredump 数据，按包名下载原始 CSV。

重要规则：下载崩溃数据时使用 package 名，不使用 Gerrit project 名。比如：

- `go-lib:golang-github-linuxdeepin-go-lib-dev` 下载时使用 `golang-github-linuxdeepin-go-lib-dev`
- `base/lightdm:lightdm` 下载时使用 `lightdm`

project 名只用于源码仓库、Gerrit 和修复映射上下文。

### 2. 数据筛选、去重和统计

对原始崩溃数据进行过滤和去重，生成每个包、每个版本的崩溃统计。流程会识别唯一崩溃、版本分布、信号类型、堆栈签名等信息，为后续分析确定范围。

项目还支持唯一崩溃 baseline，用于周期性对比新出现的崩溃。

### 3. 源码管理

根据包名和 project/package 映射拉取对应 Gerrit 源码仓库，准备后续分析和修复所需的源码目录。

对于 `project:package` 形式的配置，package 用于崩溃数据，project 用于源码/Gerrit 上下文。

### 4. deb 和 dbgsym 包处理

根据崩溃版本下载对应的 deb 包和调试符号包，安装后为 GDB、addr2line、objdump 等分析工具提供符号信息。

即使调试符号不完整，流程也会尽量保留降级原因，避免静默失败。

### 5. 崩溃分析和增强分析

基础分析会解析 GDB 堆栈、关键帧、信号、可疑模块和崩溃模式。

增强分析会进一步使用：

- addr2line / demangle
- 源码上下文查找
- git blame / git log
- objdump
- debuginfod
- 可选 LLM 辅助分析

UOS dbgsym 可能存在 DWARF 损坏，导致 addr2line 只能得到函数名而没有 file:line。项目会通过 qualified function name 搜索源码，并优先使用 `.cpp` 定义文件作为补充证据。

### 6. 自动二次深挖

当崩溃结果不确定、存在应用层信号、或崩溃频次较高时，流程会自动扩大分析深度，尝试解析更深的堆栈帧。

当前增强分析默认覆盖较大的 addr2line frame window，并在自动深挖时进一步扩大范围，以减少“只看到 Qt/GLib/DBus 包装层，没看到业务帧”的情况。

### 7. 自动修复和 Gerrit 提交

项目包含部分包的自动修复规则。当前自动修复大致分为两类：

- cluster fixer：按崩溃聚类选择确定性修复策略
- spec fixer：按已知规则或已知 commit 尝试修复或 cherry-pick

只有真实源码改动或已知代码修复 cherry-pick 才算真实修复。仅生成 `coredump-analysis-report.md` 的分支是分析记录，不算真实崩溃修复。

所有崩溃分析相关 Gerrit 提交标题都应带 `[coredump-analysis]` 前缀。

### 8. Workspace 汇总报告

完整运行会生成 workspace，常见目录包括：

```text
<workspace>/
  1.数据下载/
  2.数据筛选/
  3.代码管理/
  4.包管理/
  5.崩溃分析/
  6.修复补丁/
  7.总结报告/
```

优先查看 `6.总结报告/` 下的汇总文件：

- `package_status.tsv`
- `version_status.tsv`
- `run_manifest.json|md`
- `retry_summary.md`
- `auto_fix_overview.json|md`
- `new_crashes_overview.json|md`

这些文件适合用于判断整体进度、真实修复数量、分析报告数量、新增崩溃数量和需要重试的目标。

## 常用入口

### 全量/多包分析

```bash
bash run_analysis_agent.sh --background --progress 180
```

默认范围来自仓库根目录的 `packages.txt`。

### 单包分析

```bash
bash run_analysis_agent.sh --packages dde-dock --background
```

### 单包指定日期范围

```bash
bash run_analysis_agent.sh --packages dde-dock --start-date 2026-03-14 --end-date 2026-04-14
```

### 低层单包完整流程

```bash
bash coredump-full-analysis/scripts/analyze_crash_complete.sh --package dde-dock
```

## 配置文件

### accounts.json

仓库根目录的 `accounts.json` 存放内部系统账号配置，包括 Metabase、Gerrit、shuttle 和 sudo 密码等。

该文件包含敏感信息，不应提交真实凭据，也不应打入分发包。

### packages.txt

`packages.txt` 定义默认分析范围。条目可以是：

- 直接包名：`dde-dock`
- project/package 映射：`go-lib:golang-github-linuxdeepin-go-lib-dev`
- project/package/branch 映射：`base/lightdm:lightdm uos`

## 给维护者的说明

### AI 和文档加载边界

本文是给人看的项目功能介绍，不是 Agent 必须加载的 skill reference。AI Agent 的默认路由文档是：

- `SKILL.md`
- `references/README.md`
- 具体任务需要的 `references/*.md`

为了节省 token，不要把本文加入 `SKILL.md` 的 reference routing，也不要加入 `references/README.md` 的“当前本地 reference”受管清单。

### 修改项目后如何校验

修改 skill 文档或 reference 后运行：

```bash
python3 check_skill_sync.py
```

该脚本会检查：

- 根 `SKILL.md` 是否过大
- `references/README.md` 索引是否和实际 reference 文件一致
- 是否引用了不存在的 reference
- 是否包含个人 Hermes cache 路径或一次性 workspace 路径
- 是否存在 Python 缓存文件提示

### 分发包注意事项

`package_skills.py` 会排除运行缓存、pyc、workspace、accounts.json、dist/build、`.skill` 等不应分发的文件。

如果新增脚本会产生新的运行产物，应同步检查打包排除规则。

## 适合谁阅读

本文适合：

- 第一次接触本项目的工程师
- 想了解整体链路的维护者
- 需要判断运行产物含义的使用者
- 需要解释项目能力边界的团队成员

如果要执行具体分析，请优先看根 `SKILL.md` 或 `references/analysis-runbook.md`。如果要维护某个专项逻辑，再看对应 `references/*.md`。
