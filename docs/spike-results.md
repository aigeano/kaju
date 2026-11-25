# Feasibility checks

Results of the checks that decide what each terminal tier can do. Each row records the outcome, the method, and the versions tested. "Open" means not yet tested.

Tested on macOS 27.0 (Apple silicon), Claude Code 2.1.332, iTerm2 3.6.8, 2026-11-25.

| # | Check | Result | How |
|---|---|---|---|
| S1 | Claude Code's copy-on-select reaches the macOS clipboard in every local terminal | **Pass (by inspection)**; manual confirmation per terminal open | Claude Code's clipboard routine on macOS runs `pbcopy` locally (not only the OSC 52 terminal sequence) and, inside tmux, also `tmux load-buffer -w`. A local `pbcopy` write does not depend on the terminal, so Terminal.app and tmux receive the selection. Confirmed in practice in iTerm2. |
| S2 | Classic mode: select then ⌘C puts the text on the clipboard | Open | |
| S3 | Terminal.app delivery of a comment into Claude Code (review batch not yet tried) | **Pass** on macOS 27.0 (2026-11-25): selection captured, comment sent automatically after the liveness check, using tab selection, ⌘V and Return. Needs Automation (Terminal) and Accessibility; kaju now asks for Automation before its first AppleScript call. `do script` was not used. | Two AppleScript traps found: `tab` inside a Terminal tell block is Terminal's tab class (use `character id 9`), and `contents of t` on a loop reference returns the reference (use `contents of (contents of t)`). |
| S4 | ⌘V through CGEvent delivers multi-line text intact in Ghostty and Warp | Open (neither installed on the test Mac) | |
| S5 | A background agent can read the pasteboard without a privacy prompt | **Pass** on macOS 27.0 for reads through `pbpaste` from a background script (an earlier iTerm2-only version of kaju worked this way). kaju's in-process `NSPasteboard` read to be confirmed. | |
| S6 | tmux with mouse mode on: whether tmux takes over the selection | Open (tmux not installed on the test Mac) | |
| S7 | `tccutil reset` works for kaju's bundle id without root | **Pass** outside Homebrew: `tccutil reset Accessibility io.github.aigeano.kaju` succeeded once the app had been launched (before that, macOS does not know the bundle id). Inside Homebrew's `post_install` sandbox: open. | |
| S8 | The window title shows Claude Code reliably (Basic-tier liveness substitute) | Partial: Claude Code sets the terminal title to "✳ topic" when idle and a spinner glyph (◐ ◓ ◑ ◒) while working, as seen in iTerm2 session names. Confirmation per Basic-tier terminal open. | |
