# reporting 目录说明

本目录存放 workspace 级与包级的报告/汇总生成脚本。

定位
- INTERNAL TOOLING，不作为主要人工入口
- 由 `run_analysis_agent.sh`、`analyze_crash_complete.sh`、`step5_analyze.sh`、`validate_workspace.sh` 编排调用
- 产物主要写入 `5.崩溃分析/<package>/` 或 `6.总结报告/`

当前脚本

| 脚本 | 主要产物 | 典型调用方 |
|------|----------|-----------|
| `generate_workspace_summary.py` | `run_manifest.*` `all_packages_summary.*` `root_cause_clusters.*` `retry_*` `auto_fix_overview.*` `new_crashes_overview.*` | `run_analysis_agent.sh` `validate_workspace.sh` |
| `generate_gerrit_web_report.py` | `gerrit-web-report/index.html` | `run_analysis_agent.sh` |
| `generate_version_list.py` | `version_list.txt` | `step5_analyze.sh` |
| `generate_full_report.py` | `full_analysis_report.md` | `analyze_crash_complete.sh` |
| `generate_final_report.py` | 最终版本级汇总报告 | `analyze_crash_complete.sh` |
| `generate_ai_report.py` | `AI_analysis_report.md` | `analyze_crash_complete.sh` |
| `generate_issue_doc.py` | 问题明细文档 | 手工补充分析 |

使用规则
- 人工如果只是要跑分析，不应直接从这里选脚本；优先使用上层入口：
  - `bash run_analysis_agent.sh`
  - `bash coredump-full-analysis/scripts/analyze_crash_complete.sh`
  - `bash coredump-full-analysis/scripts/validate_workspace.sh`
- 新增 workspace 级产物时，优先接入 `generate_workspace_summary.py`
- 新增包级 Markdown/JSON 报告时，优先放在本目录，而不是重新把 reporting 逻辑塞回 scripts 顶层
- 新增“历史基线/周增量”类汇总时，统一复用 `2.数据筛选/*_crash_baseline_diff.json` 作为 workspace 汇总输入

维护要求
- 修改产物路径后，要同步检查：
  - `run_analysis_agent.sh`
  - `validate_workspace.sh`
  - `tests/coredump_full_analysis/test_workspace_summary_and_retry.py`
  - `tests/coredump_full_analysis/test_generate_gerrit_web_report.py`
  - `coredump-full-analysis/SKILL.md`
  - `coredump-full-analysis/scripts/README.md`
- 修改 repo 文档后，执行：
  - `python3 check_docs_consistency.py`
  - `python3 check_skill_sync.py`

快速验证
```bash
python3 -m py_compile coredump-full-analysis/scripts/reporting/*.py
python3 -m unittest \
  tests.coredump_full_analysis.test_workspace_summary_and_retry \
  tests.coredump_full_analysis.test_generate_gerrit_web_report
```
