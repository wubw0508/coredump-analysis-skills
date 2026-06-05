# Enhanced Analysis

Use this reference when maintaining `coredump-full-analysis/scripts/enhanced_analysis.py` or interpreting shallow/partial enhanced-analysis output.

## Core behavior

Enhanced analysis enriches base GDB stack results with:

- addr2line / demangling
- source-file lookup and surrounding source context
- git blame/log for resolved source frames
- objdump around the crash instruction when a key frame is known
- optional debuginfod lookup for system-library build-ids
- optional LLM stack reasoning after deterministic passes

It should degrade visibly, not silently. When a stage cannot run, record a structured reason and keep the base crash analysis usable.

## UOS addr2line reality

UOS dbgsym packages often have corrupted DWARF sections. Typical error:

```text
addr2line: DWARF error: section .debug_info is larger than its filesize!
```

Practical effect:

- addr2line may demangle function names but return `??:?`
- Chinese locale may output `于 ??:?`; parsers must handle both `at` and `于`
- `partial_with_source` is valuable and should not be treated as total failure

Fallback strategy:

1. demangle and prefer qualified names such as `PluginListView::rowsInserted`
2. search source by qualified name before simple method name
3. prefer `.cpp` definitions over `.h` declarations
4. read source context around the match
5. allow source-based fixability heuristics to run on `partial_with_source`

Set `LC_ALL=C` for `find`/shell source scans to avoid garbled UOS locale errors.

## Binary and frame resolution

Binary lookup order:

1. exact stack-frame path
2. standard library paths such as `/usr/lib/` and `/usr/lib/x86_64-linux-gnu/`
3. DDE plugin directories such as `/usr/lib/dde-dock/plugins/`, `/usr/lib/dde-control-center/plugins/`, `/usr/lib/dde-launcher/plugins/`
4. build-id debug files under `/usr/lib/debug/.build-id/xx/yyyy.debug`
5. debuginfod if a build-id exists

Stack frame parser expects shapes like:

```text
#0 0x7f8a1b2c3d4e symbol_name (libname.so + 0xOFFSET)
```

Offset drives addr2line: `addr2line -e <binary> -C -f <hex_offset>`.

## Deep-stack policy

Enhanced addr2line is configurable with `--addr2line-max-frames`; current default is `300`. Automatic deep dive expands to at least `600` frames.

Use wider windows when app-layer frames are buried below Qt/GLib/signal/event-loop wrappers, or when the first frames are all framework/system code.

Automatic second-pass deep dive should run when any of these are true:

- `fixable == uncertain`
- app-layer signal exists (`app_layer_symbol`, package-owned key-frame symbol, or package-owned key-frame library)
- crash count is high enough, currently `count >= 3`

## Degradation reasons to surface

Reports should show why analysis stopped getting deeper. Durable reason names include:

- `no_parsed_frames`
- `no_addr2line_results`
- `library_not_found`
- `missing_frame_offset`
- `addr2line_timeout`
- `addr2line_error`
- `addr2line_unresolved`
- `source_context_unavailable`
- `no_resolved_source_frames`
- `objdump_not_available`
- `git_analysis_unavailable`
- `debuginfod_unavailable`
- `llm_analysis_unavailable`
- `deep_dive_exhausted`
- `deep_dive_no_gain`

Check these first when a report looks shallow.

## Git / objdump / debuginfod / LLM notes

- Run git blame/log on fully resolved `ok` frames and `partial_with_source` frames after locating the likely definition line.
- Run objdump only when a `key_frame` identifies the likely crash point; otherwise disassembly is noisy.
- Debuginfod is optional and mostly useful for Debian/Ubuntu/system libraries; UOS package build-ids often 404 on public servers.
- LLM stack analysis is a late-stage optional aid. It may upgrade fixability only when confidence is high; deterministic evidence remains preferred.

## Fixability improvement

Enhanced analysis may upgrade:

| Before | After | Trigger |
|--------|-------|---------|
| `uncertain` | `fixable` / `null_deref` | source context shows null pointer access |
| `uncertain` | `fixable` / `use_after_free` | source context shows dangling pointer use |
| `uncertain` | `manual_required` | evidence is useful but not safe for automation |

Do not require full `file:line` resolution before source heuristics. `partial_with_source` is often the best available evidence on UOS.
