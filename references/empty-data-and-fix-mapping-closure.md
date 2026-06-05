# Empty Data and Fix-Mapping Closure Pitfalls

Use this when package execution looks failed even though data/filter/analyze stages may have completed.

## Empty CSV is not necessarily wrong identifier

If download logs show a CSV was saved but later stages report zero rows or a misleading failure, first inspect the produced CSV and step-2 outputs.

Interpretation rule:

- `原始记录数: 0`, `有效记录数: 0`, `唯一崩溃数: 0` can be legitimate for the current date/system-version window
- only question package/project mismatch after confirming the produced data and filter outputs

## Keep package/project split explicit

Use identifiers by stage:

- Metabase download/filter: package name only
- source checkout / Gerrit / fix mapping: package plus optional Gerrit project context

For `project:package` mappings:

- `go-lib:golang-github-linuxdeepin-go-lib-dev` -> download `golang-github-linuxdeepin-go-lib-dev`, project context `go-lib`
- `base/lightdm:lightdm` -> download `lightdm`, project context `base/lightdm`

## AI report import closure

Failure shape:

- package has 0 filtered crashes or reaches report generation
- `generate_ai_report.py` fails with `ModuleNotFoundError: package_rules`
- package is marked failed even though core stages effectively completed

Durable fix:

- `generate_ai_report.py` should self-heal by prepending parent `scripts/` to `sys.path`
- direct invocation from `coredump-full-analysis/scripts/reporting/` must work
- expected output: `<workspace>/5.崩溃分析/<package>/AI_analysis_report.md`

## Fix-mapping `--project` compatibility

Failure shape:

- package log already shows crash analysis completed
- final fix-mapping step fails with `unrecognized arguments: --project ...`
- status remains running/failed even though core artifacts exist

Durable fix:

- `analyze_with_fix_mapping.py` should accept optional `--project`
- default project to package when omitted
- use package for crash-data paths and project for Gerrit/fix-mapper context

## Recovery pattern

For late reporting/fix-mapping failures:

1. inspect `package_status.tsv` and package logs
2. confirm existing package artifacts such as `full_analysis_report.md`, `AI_analysis_report.md`, and fix reports
3. rerun only the failed closure step when core analysis is complete
4. update/append corrected status rows if needed
5. regenerate workspace summary with `reporting/generate_workspace_summary.py`

This avoids rerunning the whole pipeline when only closure/reporting failed.
