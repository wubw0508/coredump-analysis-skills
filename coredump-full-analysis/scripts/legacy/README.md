# legacy 脚本目录说明

本目录存放已退出主链路维护范围的历史脚本。

目标：
- 避免它们继续和当前主链路脚本混放在同一层目录中
- 保留历史文件名与实现，方便排查旧 workspace、旧日志、旧命令来源
- 通过顶层 stub 明确告诉使用者这些脚本已迁移且不再维护

当前迁入本目录的脚本：
- `analyze_dde_launcher_auto.sh`
- `analyze_dde_launcher_full.sh`
- `analyze_all_versions.sh`
- `auto_analysis.sh`
- `analyze_and_fix.sh`
- `auto_analyze_and_fix.sh`

顶层兼容策略：
- `coredump-full-analysis/scripts/` 下保留同名 stub
- stub 只负责打印“已迁移到 legacy/”和推荐入口
- stub 不再继续执行旧逻辑，避免误用

推荐替代入口：
- 全量/多包编排：`bash run_analysis_agent.sh ...`
- 单包完整流程：`bash coredump-full-analysis/scripts/analyze_crash_complete.sh --package <package>`
- 分步执行：`step1_download.sh` ~ `step5_analyze.sh`
- 当前 auto-fix 主链路：在 `run_analysis_agent.sh` 或当前 workspace 流程中执行 `auto_fix_submit.py`

维护规则：
- 不再向本目录脚本引入新特性
- 新的 enhanced analysis、自动二次深挖、workspace summary、retry verifier、Gerrit report/auto-fix 逻辑只进入主链路
- 如果未来确认完全不再需要历史兼容，可再删除顶层 stub，仅保留本目录或彻底移除
