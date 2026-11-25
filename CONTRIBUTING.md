# Contributing to kaju

Thank you for helping. The most useful contributions are new terminal adapters, fixes from testing in your terminal, and clear bug reports.

## Building and testing

```sh
swift build
swift test          # unit tests for KajuCore
make app            # build/kaju.app, signed ad hoc
open build/kaju.app
```

When you run kaju from a terminal or with `open` during development, macOS may attribute permission prompts to that terminal instead of to kaju. Test permission behaviour with `make install`, which starts kaju through launchd.

Set `KAJU_RESOURCES` to the repository's `Resources` folder and `KAJU_PYTHON` to a Python with the packages in `Resources/requirements.txt` to run the executable directly with `swift run`.

## Layout

| Path | What it is |
|---|---|
| `Sources/KajuCore` | Logic without UI: messages, the liveness check, clipboard policy, review store, config, tmux. Covered by tests. |
| `Sources/kaju` | The menu-bar app: hotkey, comment input, review panel, coordinator. |
| `Sources/kaju/Adapters` | One file per terminal. |
| `Resources/kaju_iterm2_helper.py` | iTerm2 helper, spoken to over stdio. |
| `packaging/homebrew/kaju.rb` | The Homebrew formula (published in `aigeano/homebrew-tap`). |

## Writing an adapter

An adapter implements `TerminalAdapter` (`Sources/kaju/Adapters/Adapter.swift`) for one terminal app:

| Method | Answer |
|---|---|
| `target(app:)` | The front pane: a stable `key`, a label, the pane's tty if you can find it |
| `selectionAnchor` | Where the selection ends on screen, or nil |
| `visibleText` | The pane's visible text, used to reject a stale clipboard, or nil |
| `windowFrame` | The window frame, for docking the review panel |
| `isTabSelected` | Whether the pane's tab is the selected one |
| `isClaudeRunning` | Whether Claude Code is the foreground program; nil if you cannot tell |
| `activate` | Bring the pane to the front |
| `deliver` | Type the text: bracketed paste, then Return only in `.submit` mode |

### The safety rule

kaju must never type into a shell. The coordinator calls `isClaudeRunning` before every delivery and submits only when it returns `true`. Return `nil` only if your terminal truly cannot tell, in which case kaju pastes without Return. If your adapter knows the pane's tty, use `Liveness.claudeInForeground(tty:)`, which checks the foreground process group, and return its answer.

Every adapter needs a test, by hand at least, that sending a comment and a review into a pane running a shell types nothing.

### Good next adapters

| Terminal | How | User setting needed |
|---|---|---|
| kitty | `kitten @ ls`, `kitten @ send-text --match id:N` | `allow_remote_control yes` |
| WezTerm | `wezterm cli list`, `wezterm cli send-text --pane-id N` | None |

Both can report the pane's tty, so both can get full support, including sending automatically after the safety check.

## Style

- Keep source headers: `Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.`
- If you modify a file, say so in your commit; the Apache License asks that modified files carry a notice of the change.
- Do not log comment text or selections.

## Changes and releases

- Changes reach `main` through pull requests, and CI must pass before merging.
- Add a line under `## Unreleased` in `CHANGELOG.md` for anything users notice.
- To release, the maintainer renames `## Unreleased` to `## X.Y.Z - YYYY-MM-DD` (and starts a new empty `## Unreleased` above it), merges that, and pushes a tag such as `v0.2.0`. The release workflow then tests the build, creates the GitHub Release from the CHANGELOG and updates the Homebrew formula in `aigeano/homebrew-tap`.

## Reporting bugs

Please include your macOS version, terminal and version, Claude Code version and display mode (full-screen or classic), whether you use tmux, and the relevant lines of `~/Library/Logs/kaju.log`.
