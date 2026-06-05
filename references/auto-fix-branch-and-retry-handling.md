# Auto-fix Branch Normalization and Retry Handling

Use this when version-level auto-fix/report submission is classified as `auto fix submit check failed`, especially when the real cause may be target-branch resolution or stale retry classification.

## Problem classes

1. Duplicated remote prefix:
   - bad input: `origin/origin/develop/eagle`
   - useful candidates: raw input, `origin/develop/eagle`, `develop/eagle`
2. Repository lacks the requested target branch:
   - example: repo exposes only `master` / `origin/master`, not `develop/eagle`
   - this is branch availability, not proof that the fixer crashed
3. Retry lists built from stale status text:
   - `version_status.tsv` can over-report retryable failures even when structured auto-fix JSON says the result is non-retryable

## Correct handling

Normalize checkout candidates before giving up:

- try raw input
- collapse repeated `origin/origin/` to `origin/`
- repeatedly strip one leading `origin/` to try local branch names

Normalize push branch separately. For `refs/for/<branch>`, use the first candidate without leading `origin/`.

If all checkout candidates fail, do not traceback. Persist structured JSON, for example:

```json
{
  "analysis_report": {
    "submitted": false,
    "reason": "target branch unavailable: origin/origin/develop/eagle",
    "checkout_error": "fatal: 'develop/eagle' ..."
  }
}
```

This keeps the version machine-readable and prevents false generic submit-check failures.

## Retry classification source of truth

Retry generation should read structured per-version result JSON first:

1. `auto_fix_clusters_result.json`
2. `auto_fix_result.json`
3. legacy status text only when no structured result exists

Suppress confirmed non-retryable categories from retry target lists:

- `target_branch_unavailable`
- `analysis_report_submitted`
- `analysis_report_only`
- `manual_required`
- `source_repo_missing`
- `no_fix_output`

These categories should remain visible in overview output instead of hidden inside retry buckets.

## Verification recipe

Rerun a failing version directly:

```bash
python3 coredump-full-analysis/scripts/auto_fix_submit.py \
  --package <pkg> \
  --version <ver> \
  --workspace <workspace> \
  --target-branch <branch>
```

Expected:

- exit code `0`
- per-version JSON exists
- outcome is a normal submission/result or structured `target branch unavailable`
- no traceback

Then regenerate workspace summary and confirm non-retryable categories disappear from retry lists.

## Durable examples

- Duplicated origin prefix with a valid branch should normalize and proceed normally.
- Repos that truly lack the requested branch should produce structured `target branch unavailable`, not `submit check failed`.
