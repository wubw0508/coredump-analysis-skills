# Analysis Depth Pitfalls

Use this when reports look like they stopped halfway, stayed shallow, or did not produce patchable root-cause evidence.

## Current depth rules to remember

- `analyze_crash_complete.sh` should default to analyzing all deduplicated crashes (`--max-crashes 0`) unless a caller intentionally requests preview mode.
- Enhanced addr2line currently defaults to a wide frame window (`--addr2line-max-frames 300`); automatic deep dive expands to at least `600` frames.
- `partial_with_source` is actionable on UOS because corrupted DWARF often prevents full `file:line` resolution.
- Enhanced-analysis degradation must be visible in JSON/Markdown, not silently hidden behind base analysis.

## Pitfall 1: hidden crash caps

If a version contains many deduplicated signatures but reports cover only an early subset, check for a caller passing a nonzero `--max-crashes`.

Optimization rule: reserve caps for quick-preview mode; full analysis should use `0` for all deduplicated crashes.

## Pitfall 2: enhanced analysis silently unavailable

If `enhanced_analysis` import or prerequisites fail, base analysis may continue without addr2line/source/git/objdump/LLM enrichment.

Required behavior:

- record import/prerequisite failure in `analysis.json`
- emit visible Markdown warnings
- include fields such as `enhanced_diagnostics.import_status` or degradation reasons

## Pitfall 3: partial source hits treated too conservatively

UOS often yields function names but not file:line. If source search finds a qualified-name match, treat `partial_with_source` as usable evidence.

Required behavior:

- let source-context heuristics run even without full `ok` frames
- distinguish `fully_resolved_count` from `source_recovered_count`
- do not leave crashes `uncertain` only because DWARF blocked exact line resolution

## Pitfall 4: app frame buried deep in framework stack

Symptoms:

- Qt/GLib/signal/event-loop frames dominate the first frames
- app-owned symbol appears much deeper
- report identifies wrappers but not the package source path

Required behavior:

- inspect key frame, first app-layer frame, and first non-system frame
- use the wider addr2line window
- trigger automatic second-pass deep dive for uncertain, app-layer, or high-frequency crashes

## Pitfall 5: missing deb/dbgsym creates shallow fallback

When deb/dbgsym cannot be downloaded or installed, the pipeline may still produce rule-based or AI-only output.

Required behavior:

- surface package/debug-symbol absence explicitly
- count crashes analyzed without matching deb/dbgsym
- record structured reasons such as `library_not_found`, `debug_file_not_found`, `addr2line_timeout`, or `source_search_miss`

## Recommended checks

1. Confirm actual `--max-crashes` used by the entrypoint.
2. Check enhanced diagnostics / degradation reasons before assuming analysis logic is weak.
3. Look for `partial_with_source` frames and source-recovered counts.
4. Check whether app-layer frames are below the default scan window.
5. Verify deb/dbgsym availability before blaming root-cause classification.
