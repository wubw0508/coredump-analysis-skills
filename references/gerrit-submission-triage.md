# Gerrit Submission Triage for Coredump Analysis

Use this when deciding whether an auto-fix result should be pushed to Gerrit, or when interpreting push outcomes such as `no new changes`.

## Core rule

Only count commits that change product source code as real crash-fix submissions.

Real fix candidates usually change `.cpp`, `.h`, `.qml`, or package/source files involved in the crash, with a plausible guard, lifecycle fix, null-check, cleanup, or cherry-pick of a known source fix.

Do not count these as repair submissions:

- branches whose only diff is `coredump-analysis-report.md`
- conservative cluster records with no source diff
- local/manual analysis records
- Markdown-only `auto-fix/*` branches

Report-only branches may be useful for traceability, but keep them separate from real fixes and do not bulk-submit them unless explicitly requested.

## Fast triage checklist

```bash
git show --stat --summary <commit>
```

Then classify:

1. only analysis artifacts changed -> analysis-only
2. product source changed with plausible crash mitigation -> Gerrit candidate
3. push returns `no new changes` -> query Gerrit by Change-Id before declaring failure

## Gerrit `no new changes`

`no new changes` usually means Gerrit already knows this patch content / Change-Id for the target branch, often because a review already exists.

Required verification:

1. read local Change-Id:
   ```bash
   git show -s --format=full <commit>
   ```
2. query Gerrit:
   ```bash
   ssh -p 29418 <user>@gerrit.uniontech.com \
     gerrit query --format=JSON change:<Change-Id> limit:5
   ```
3. check `project`, `branch`, `number`, `url`, `status`, and `open`
4. if a matching change exists, report its URL/status instead of retrying the push
5. only call submission failed if neither push nor Gerrit lookup yields a valid review

## Durable examples

Real fix patterns confirmed in prior work include source-code guards/lifecycle fixes in `dde-dock`, delayed context-menu show guarded by object lifetime checks, and camera callback shutdown race fixes.

Non-fix patterns include `coredump-analysis-report.md` only, conservative `record_conservative_analysis_only`, and manual/local records without source changes.
