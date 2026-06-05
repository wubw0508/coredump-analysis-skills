# Source Graph Context with CodeGraph

Use this when evaluating optional source-graph enrichment for enhanced crash analysis or auto-fix triage. CodeGraph must stay optional.

## Purpose

CodeGraph indexes a source tree into a local SQLite knowledge graph. In this project it is only source-context enrichment around crash symbols:

- find definitions when addr2line only returns a function name
- collect bounded caller/callee/impact context
- reduce repeated grep/read loops in large C++/Qt trees
- help judge whether a candidate patch touches the crash path

## Integration boundary

Do not make CodeGraph a hard dependency. Order of evidence:

1. addr2line file:line when available
2. CodeGraph only when explicitly enabled and indexed
3. existing qualified-name grep fallback when CodeGraph is unavailable, slow, or inconclusive
4. never fail crash analysis solely because CodeGraph failed

Recommended defaults:

```bash
ENABLE_CODEGRAPH_CONTEXT=0
CODEGRAPH_AUTO_INDEX=0
CODEGRAPH_BIN=codegraph
CODEGRAPH_TIMEOUT=60
CODEGRAPH_MAX_CALLERS=20
CODEGRAPH_MAX_CALLEES=20
CODEGRAPH_MAX_IMPACT_DEPTH=2
CODEGRAPH_MAX_OUTPUT_CHARS=50000
```

Do not run `codegraph install` from project automation because it can modify user agent/MCP configuration. Prefer bounded CLI JSON output; do not require MCP.

## Trial result and limitations

A dde-dock trial with `npx -y @colbymchenry/codegraph` indexed 653 files, 6,796 nodes, and 16,384 edges in about 50.6 seconds.

Useful results:

- `DockApplication::notify` resolved to `frame/util/dockapplication.cpp:16-37`
- `MainWindow::eventFilter` returned normal intra-project callers

Limitations:

- tested CLI lacked the advertised `codegraph context` command; use `query`, `callers`, `callees`, `impact`, `files`, or MCP only after revalidation
- static graph is incomplete for Qt virtual dispatch, signal/slot runtime dispatch, macros, generated moc code, and dynamic callbacks
- caller/callee output may be empty for framework-dispatched overrides
- indexing is non-trivial; cache per source repo and never rebuild per crash/version

## Output and degradation

If integrated, write bounded per-crash/per-version `source_graph_context.json` and optionally `.md`.

When unavailable, write a structured skip reason instead of failing:

```json
{"enabled": false, "available": false, "degradation_reasons": ["disabled"]}
```

Common reasons: `codegraph_not_found`, `not_initialized`, `auto_index_disabled`, `index_timeout`, `query_timeout`, `query_failed`, `no_symbol_match`, `output_too_large`.

## Implementation path

1. Add standalone helper first, e.g. `coredump-full-analysis/scripts/source_graph_context.py`.
2. Helper should detect tools only when allowed, check status, optionally index only with `CODEGRAPH_AUTO_INDEX=1`, run bounded symbol/caller/callee/impact queries, cap output, write JSON/Markdown, and return success for expected optional-tool unavailability.
3. Call helper from enhanced analysis only when `ENABLE_CODEGRAPH_CONTEXT=1`.
4. Use source graph for auto-fix ranking only after enough DDE C++/Qt package trials prove accuracy.

Useful candidate areas: QObject lifetime, `deleteLater`, signal/slot ownership, DBus callbacks, event filters, model/view updates, and patch-impact verification.

Existing addr2line/source-grep/git-blame behavior remains authoritative.
