# Legacy 脚本说明

以下脚本已弃用，不属于当前主分析链路：

- `analyze_dde_launcher_auto.sh`
- `analyze_dde_launcher_full.sh`
- `analyze_all_versions.sh`

它们保留在仓库中的原因仅有两点：

- 兼容历史命令记录与排查旧产物来源
- 方便对照早期专项实现

## 为什么弃用

- 脚本只面向 `dde-launcher`
- 内含硬编码工作目录与缓存版本
- 内含手工维护的版本映射
- 与当前 `step1` 到 `step5` 的通用流程重复

## 当前推荐入口

完整自动化：

```bash
bash run_analysis_agent.sh --packages <package> --start-date <YYYY-MM-DD> --end-date <YYYY-MM-DD>
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
