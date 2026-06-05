# deepin-update-ui updater watcher triage

Session outcome distilled for future crash-analysis / Gerrit triage.

## Source ownership conclusion

The `dde-control-center` fixer metadata for `updater-dbus-watchers-dtor` points at:
- `src/plugin-updater/updater/updater.cpp`

That path was absent in the checked-out `dde-control-center` repo used in this session.

Follow-up verification showed the actionable updater implementation actually lives in Gerrit repo:
- `deepin-update-ui`

Actionable file:
- `src/dcc-update-plugin/module/updatework.cpp`

Practical rule:
- if updater/plugin-updater crash families in `dde-control-center` cannot find their target file, re-check ownership in `deepin-update-ui` before downgrading to analysis-only.

## High-risk watcher sites mapped in updatework.cpp

The session mapped `updater-dbus-watchers-dtor` to these `QDBusPendingCallWatcher` paths in `updatework.cpp`:
- `GetUpdateLogs` during `activate()`
- `UpdateSource` during `checkForUpdates()`
- `PrepareDistUpgradePartly` during `startDownload()`
- `GetUpdateLogs` during `onCheckUpdateStatusChanged()`
- `DistUpgradePartly` during `doUpgrade()`

These shared the same risk profile:
- watcher parented to `this`
- lambda captures raw `watcher` and `this`
- worker teardown can race pending D-Bus callbacks

## Patch pattern that was accepted for Gerrit

Repo:
- `deepin-update-ui`

Commit pushed:
- `5446cb1bd9a5a2a896bb5494c114abfb1aafe494`

Gerrit:
- `http://gerrit.uniontech.com/c/deepin-update-ui/+/348291`

Change-Id:
- `I984ee0db67315d5d83ceaef6a0a92bcbe5ba50f7`

Patch strategy:
1. add `cleanupPendingCallWatchers()` and call it from `~UpdateWorker()`
2. enumerate `findChildren<QDBusPendingCallWatcher*>()`
3. `disconnect(this)` + `deleteLater()` during teardown
4. convert critical local watcher variables to `QPointer<QDBusPendingCallWatcher>`
5. guard each callback with `if (!watcher) return;`
6. call helper cleanup at callback exit

## Gerrit hook pitfall

Initial push failed with:
- `missing Change-Id in message footer`

Repair steps that worked:
1. install hook from Gerrit:
   - `scp -p -P 29418 ut000168@gerrit.uniontech.com:hooks/commit-msg .git/hooks/commit-msg`
2. `chmod +x .git/hooks/commit-msg`
3. `git commit --amend --no-edit`
4. confirm message now contains `Change-Id:`
5. push again

Important nuance:
- the first hook install attempt can fail if you assume the hook path exists without checking the actual `.git` directory state
- after installing, verify the footer with `git show -s --format=full HEAD`
