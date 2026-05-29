# validation 目录说明

本目录存放分析完成后的校验、重跑闭环和验收辅助脚本。

定位
- VALIDATION TOOLING，不是主分析入口
- 由 `validate_workspace.sh`、`generate_workspace_summary.py` 生成的重跑脚本、以及人工验收流程调用
- 目标是回答：哪些包/版本还没闭环、哪些失败步骤需要精准重跑

当前脚本

| 脚本 | 用途 | 典型调用方 |
|------|------|-----------|
| `verify_retry_targets.py` | 校验指定包/版本是否仍残留在 retry 列表 | `retry_commands.sh` `retry_versions.sh` `retry_failed_steps.sh` |
| `validate_workspace_retry_closure.py` | 校验 retry 相关产物是否齐全、状态是否自洽 | `validate_workspace.sh` |
| `run_retry_step.sh` | 对单个版本执行失败步骤级重跑，并回写 `version_status.tsv` | `retry_failed_steps.sh` |

使用规则
- 这些脚本默认面向“分析后修正/验收”，不是初次分析入口
- 如果只是重跑整个包或整个版本，应优先使用 summary 生成的脚本：
  - `6.总结报告/retry_commands.sh`
  - `6.总结报告/retry_versions.sh`
  - `6.总结报告/retry_failed_steps.sh`
- 只有在需要细粒度定位 retry 问题时，才直接调用本目录脚本

维护要求
- 调整 retry 产物格式（如 `retry_versions.tsv`）时，必须同步检查：
  - `reporting/generate_workspace_summary.py`
  - `validate_workspace.sh`
  - `tests/coredump_full_analysis/test_workspace_summary_and_retry.py`
- 新增 validation 脚本时，应保持“只做校验/重跑辅助，不承载主分析逻辑”的边界

快速验证
```bash
bash -n coredump-full-analysis/scripts/validation/run_retry_step.sh
python3 -m py_compile \
  coredump-full-analysis/scripts/validation/verify_retry_targets.py \
  coredump-full-analysis/scripts/validation/validate_workspace_retry_closure.py
python3 -m unittest tests.coredump_full_analysis.test_workspace_summary_and_retry
```
