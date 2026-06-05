# Auto-Fix Pipeline Architecture & Coverage

Use this reference when changing or interpreting `auto_fix_submit.py`, cluster fixers, spec fixers, analysis-report fallback, or Gerrit auto-fix metrics.

## Dispatcher model

`auto_fix_submit.py` has two mutually exclusive normal paths:

1. Cluster path: package has both `build_fix_plan_for_cluster` and `apply_fix_plan` in `fixers/<pkg>.py`.
   - `cluster_crashes(package, crashes)` creates cluster buckets.
   - `build_fix_plan_for_cluster(cluster)` returns a `FixPlan`.
   - `apply_fix_plan(code_dir, plan)` may create a deterministic source edit, skip if already fixed, or record conservative analysis-only.
   - If any cluster creates code changes, commits are pushed to Gerrit.
   - If no safe code edit exists but fixable clusters remain, analysis-report fallback may create/push `coredump-analysis-report.md`.
   - After cluster handling, `main()` returns; the spec path is not run for that package in the same invocation.

2. Spec path: package has no cluster fixer entrypoints and relies on `get_fix_specs()`.
   - Matched specs may mark already-fixed crashes, queue `cherry_pick_known_fix`, or require manual work.
   - If no code edit/cherry-pick is applied but fixable crashes remain, analysis-report fallback may create/push `coredump-analysis-report.md`.

Important consequence: for packages with cluster fixers, any existing `get_fix_specs()` metadata is normally bypassed by the dispatcher.

## Current effective coverage

`cluster_crashes.py` currently defines **24 deterministic cluster rules**. Coverage families include D-Bus lifecycle, Qt object lifetime/event-loop, X11/XCB, updater watcher cleanup, qsocketnotifier/qscroller/qmenu/qhash/pixmap-cache, atspi/native-event-filter, and deepin platform plugin crashes.

Current cluster-fixer packages:

| Package | Effective behavior |
|---------|--------------------|
| `dde-dock` | 6 concrete code-changing cluster fix plans + conservative fallback |
| `dde-launcher` | cluster path is conservative analysis-only; large `get_fix_specs()` table exists but is bypassed while cluster entrypoints exist |
| `dde-control-center` | 2 explicit updater watcher code-changing entries converging to one edit action + conservative fallback |
| `dde-clipboard` | conservative analysis-only |
| `dde-polkit-agent` | conservative analysis-only |
| `startdde` | conservative analysis-only |
| other packages | no cluster fixer; depend on package-specific spec rules, usually narrow/absent |

Nuances:
- `dde_dock.py` maps 6 cluster keys to edits: appitem DBus property read, pluginlistview qscroller dtor, dock context menu qwindow dtor, xrecord X11 IO error, dock application notify cast, and speed plugin update tip.
- `dde_control_center.py` has explicit updater watcher keys for code-changing cleanup plus conservative dmainwindow/dbus/wallpaper entries.
- `cluster_crashes.py` also has `updater-dbus-pending-watchers-wide`; it needs an explicit fixer mapping before it reuses updater watcher cleanup.
- `dde_launcher.py` has substantial spec knowledge, but normal runs use conservative cluster analysis while cluster entrypoints remain present.

## Gerrit interpretation rules

All crash-analysis-related Gerrit commit subjects should include `[coredump-analysis]`.

Do not treat every Gerrit submission as a real crash fix:

- real code fix = commit changes package source files or cherry-picks a known source-code fix
- analysis-report fallback = `coredump-analysis-report.md` traceability artifact for human follow-up
- Markdown-only `auto-fix/*` branch = not a real source-code fix candidate

When reporting solved crashes or fix coverage, separate:
- code edits applied
- cherry-picks applied
- analysis-report fallback submissions
- analysis-only / manual-only local results

## Why "fixable" may not become "auto_fixed"

Common causes:

1. crash matched a cluster rule whose package fixer is conservative-only
2. package has cluster entrypoints, so `get_fix_specs()` is bypassed
3. package reaches spec path but has no useful `get_fix_specs()`
4. spec exists but has no supported auto fixer
5. cherry-pick candidate is missing, already applied, or conflicts
6. root cause is actionable, but no safe deterministic source edit is known

Interpretation: `fixable` means likely actionable root cause; `auto_fixed` means safe deterministic code edit or successful cherry-pick actually happened.

## Coverage gap snapshot

A recent audit found **127 matched / 866 unmatched** crash records under the current deterministic rule set. Treat this as directional, not permanent; rerun the audit after changing `KNOWN_CLUSTER_RULES` or package fixers.

Highest-value expansion directions:

1. decide whether cluster-fixer packages such as `dde-launcher` should also consume spec rules after conservative cluster handling
2. add an explicit mapping for `updater-dbus-pending-watchers-wide` if it should reuse updater watcher cleanup
3. add package-specific spec rules for packages with neither cluster fixers nor useful specs
4. convert repeated conservative cluster families into safe mechanical fixers only after source ownership/edit points are verified
5. keep metrics split by code edits, cherry-picks, analysis-report fallback, and analysis/manual-only results

## Detection commands

```bash
# Count cluster rules
python3 - <<'PY'
import ast, pathlib
p = pathlib.Path('coredump-full-analysis/scripts/cluster_crashes.py')
mod = ast.parse(p.read_text(encoding='utf-8'))
for node in mod.body:
    if isinstance(node, ast.Assign):
        for t in node.targets:
            if getattr(t, 'id', None) == 'KNOWN_CLUSTER_RULES':
                print(len(node.value.elts))
PY

# Inspect package fixer entrypoints
python3 - <<'PY'
from pathlib import Path
for p in sorted(Path('coredump-full-analysis/scripts/fixers').glob('*.py')):
    text = p.read_text(encoding='utf-8')
    hits = [name for name in ['build_fix_plan_for_cluster', 'apply_fix_plan', 'get_fix_specs'] if name in text]
    if hits:
        print(p.name, ','.join(hits))
PY

# Check fallback/report subject references
python3 - <<'PY'
from pathlib import Path
for p in [Path('coredump-full-analysis/scripts/auto_fix_submit.py'), Path('coredump-full-analysis/scripts/deep_auto_fix.py')]:
    text = p.read_text(encoding='utf-8', errors='replace')
    for token in ['coredump-analysis-report', 'analysis_report', '[coredump-analysis]']:
        if token in text:
            print(p, token)
PY
```
