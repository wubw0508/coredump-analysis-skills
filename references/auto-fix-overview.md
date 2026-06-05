# Auto-fix Overview Workspace Artifacts

Use this when auditing full-run auto-fix effectiveness at workspace level.

## Generated files

`coredump-full-analysis/scripts/reporting/generate_workspace_summary.py` emits:

- `6.总结报告/auto_fix_overview.json`
- `6.总结报告/auto_fix_overview.md`

These summarize per-version auto-fix outputs across the workspace and should be the first stop for cron/reporting questions.

## Input precedence

For each `5.崩溃分析/<package>/version_*/` directory:

1. prefer `auto_fix_clusters_result.json`
2. otherwise use `auto_fix_result.json`
3. skip the version if neither file exists

This mirrors dispatcher behavior: cluster-fixer packages write cluster results; spec/manual packages write spec results.

## Category mapping

Each version result should map to one primary category:

- `source_repo_missing`: skipped because source repository is unavailable
- `code_fix_submitted`: `auto_fixed` exists and Gerrit submission succeeded
- `code_fix_generated`: `auto_fixed` exists but was not submitted
- `analysis_report_submitted`: no code fix, but analysis report was submitted
- `analysis_report_only`: analysis-only output exists without report submission
- `manual_required`: manual output exists and no higher-priority state matched
- `no_fix_output`: fallback when no useful auto-fix output exists

Priority matters: code fix categories win over report/manual categories.

## How to use

For questions like “多少真实修复提交 / 哪些只是分析报告 / 哪些包 fixable 但未出代码”:

1. read `6.总结报告/auto_fix_overview.json`
2. use `auto_fix_overview.md` for human-readable summary
3. drill into per-version `auto_fix_*result.json` only for disputed or high-priority cases

Do not count `analysis_report_submitted` or Markdown-only output as real source-code crash fixes.

## Maintenance note

If category logic changes, update tests in `tests/coredump_full_analysis/test_workspace_summary_and_retry.py` with the same change.
