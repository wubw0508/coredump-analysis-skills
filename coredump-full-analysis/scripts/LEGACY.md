# Legacy 脚本说明

以下脚本已弃用，不属于当前主分析链路；其历史实现现已迁入 `coredump-full-analysis/scripts/legacy/`：

- `analyze_dde_launcher_auto.sh`
- `analyze_dde_launcher_full.sh`
- `analyze_all_versions.sh`
- `auto_analysis.sh`
- `analyze_and_fix.sh`
- `auto_analyze_and_fix.sh`

顶层 `coredump-full-analysis/scripts/` 保留同名兼容 stub，只负责打印“已迁移到 legacy/”并指向当前推荐入口，不再执行旧逻辑。

请同时参见：
- `coredump-full-analysis/scripts/legacy/README.md`

它们保留在仓库中的原因仅有三点：

- 兼容历史命令记录与排查旧产物来源
- 方便对照早期专项实现
- 为迁移旧 workspace / 旧操作习惯提供参考

## 为什么弃用

- 脚本通常只面向单包或单场景（尤其是 `dde-launcher`）
- 内含历史硬编码工作目录、缓存版本或手工维护映射
- 与当前 `step1` 到 `step5` 的通用流程重复
- 无法代表当前 enhanced analysis、自动二次深挖、Gerrit Web Report、auto-fix fallback 等主链路能力

## 当前推荐入口

完整自动化：

```bash
bash run_analysis_agent.sh --packages <package> [--start-date <YYYY-MM-DD>] [--end-date <YYYY-MM-DD>]
```

直接调用完整流程：

```bash
bash coredump-full-analysis/scripts/analyze_crash_complete.sh --package <package>
```

逐步执行：

- `step1_download.sh`
- `step2_filter.sh`
- `step3_source.sh`
- `step4_packages.sh`
- `step5_analyze.sh`

## 维护规则

- 不再向 legacy 脚本继续堆积新功能
- 新的分析策略、deep dive 行为、workspace 汇总逻辑、Gerrit 提交逻辑应只进入主链路
- 如需保留 legacy 脚本，文件头必须明确打印“已弃用”并直接退出，避免误用
