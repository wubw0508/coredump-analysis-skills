# Unique Crash Baseline and Weekly Delta

Use this when maintaining a long-lived baseline of deduplicated unique crashes or reporting whether a later full run introduced new crash cases.

## Identity rule

Current unique-crash key includes version:

```text
UniqueKey = Exe|Sig|Version|StackSignature
```

The same crash pattern in a different version intentionally counts as a new unique crash for weekly/regression tracking.

## Persistent layout

Default root: `~/coredump-baseline/`

- `current/` — active per-package baseline
- `history/<timestamp>/` — snapshots after updates
- `reports/` — human-readable diff summaries

Per-package active files:

- `current/<package>_unique_crashes.csv`
- `current/<package>_unique_crashes.json`

## Package-level flow

Implemented in `coredump-full-analysis/scripts/reporting/update_unique_crash_baseline.py` and called from `coredump-full-analysis/scripts/step2_filter.sh` after `filtered_<package>_crash_data.csv` is generated.

Workspace outputs under `2.数据筛选/`:

- `<package>_crash_baseline_diff.json`
- `<package>_new_crashes.csv`

Behavior:

1. read current filtered unique-crash CSV
2. read existing baseline CSV/JSON if present
3. compare by `UniqueKey`
4. classify rows as `known`, `newly_detected`, or `baseline_only`
5. append only newly detected rows to the persistent baseline
6. never delete historical baseline-only entries

The baseline is therefore the historical union of unique crashes seen for that package.

## Workspace rollup

`generate_workspace_summary.py` reads package diff JSON files and emits:

- `6.总结报告/new_crashes_overview.json`
- `6.总结报告/new_crashes_overview.md`

Expected summary: packages scanned, packages with new crashes, total new unique crashes, per-package counts, and detailed new rows.

## Reporting rule

Recurring/weekly summaries should prefer existing rollups instead of rescanning raw CSV:

1. `new_crashes_overview.json`
2. `new_crashes_overview.md`
3. `run_manifest.json`
4. `retry_summary.md`

Before launching a new full run, check whether `run_analysis_agent.sh` or `analyze_crash_complete.sh` is already running. Do not start overlapping full runs because baseline updates can race and confuse deltas.

## Verification checklist

- package-level diff JSON exists
- new-crash CSV exists when new rows are found
- workspace `new_crashes_overview.*` is generated after summary refresh
- totals are reflected in run manifest / package summaries
- cron jobs that report weekly deltas load `skills: ["coredump-analysis"]`
