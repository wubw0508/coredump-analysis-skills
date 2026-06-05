# references 目录说明

本目录只保存当前可分发 skill 需要的本地专题资料。根 `SKILL.md` 保持轻量，只放硬规则、入口和路由；不要引用个人 Hermes cache 中才存在的文档。

原则：当前仓库是 source of truth；不依赖或同步个人 cache；只有影响项目独立使用或具备长期通用价值的资料才放入本目录。

## 当前本地 reference

### 运行、监控、恢复分析流程

- `analysis-runbook.md` — 入口、账户前置、workspace 产物、监控和 summary refresh 恢复。
- `empty-data-and-fix-mapping-closure.md` — 空数据、package/project 分离、AI report import 自愈、closure 失败恢复。
- `auto-fix-overview.md` — workspace 级 auto-fix 汇总、真实代码修复 vs 分析报告分类。
- `unique-crash-baseline.md` — 唯一崩溃 baseline、new_crashes_overview 和周期增量比较。

### package/project 映射与下载正确性

- `download-by-package-not-project.md` — Metabase 下载必须使用 package 名；`--package` / `--project` 边界见 `empty-data-and-fix-mapping-closure.md`。

### 增强分析和分析深度

- `enhanced-analysis.md` — addr2line、source context、objdump、git blame、DWARF 损坏降级。
- `automatic-deep-dive-policy.md` — 自动二次深挖触发条件、默认帧数、报告字段。
- `analysis-depth-pitfalls.md` — “停一半”的常见原因：硬限制、静默降级、保守 source handling。
- `source-graph-context.md` — CodeGraph 可选源码图上下文；必须保持 optional。

### 自动修复、重试分类和 Gerrit

- `fixer-architecture.md` — cluster/spec 路径、fallback、fixer 覆盖和扩展方向。
- `auto-fix-branch-and-retry-handling.md` — target branch 归一化、目标分支缺失结构化处理、retry suppression。
- `gerrit-submission-triage.md` — 真实源码修复 vs 分析报告；Gerrit `no new changes` Change-Id 复验。

### 包级/仓库归属专项 triage

- `deepin-update-ui-updater-watcher-triage.md` — dde-control-center updater watcher 崩溃映射到 deepin-update-ui。

### 索引与维护

- `README.md` — 本地 reference 索引和维护原则。

## 外部 cache 文档

个人 Hermes cache 中可能有历史 reference。除非当前项目 `SKILL.md`/脚本依赖它，或该资料清理后对其他用户有长期价值，否则不要迁回。不得迁回个人路径、过期 cron/job/workspace、一次性排查记录或只服务旧 cache 同步流程的文档。

## 维护建议

1. 新增专题前先尝试并入现有 reference。
2. 修改主流程、默认值、触发条件后同步相关 reference。
3. 根 `SKILL.md` 只保留结论和路由，不展开历史案例。
4. `## 当前本地 reference` 是受管 reference 清单的唯一来源；新增/删除文件时同步根 `SKILL.md` 路由。
5. 修改 repo-managed docs 后运行 `python3 check_skill_sync.py`。
6. `sync_skill_to_hermes.sh` 已禁用；不要把当前 skill 同步到个人 cache 路径。
