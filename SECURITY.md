# Security

## What kaju does on your Mac

- **Reads the clipboard** to see the text you selected in Claude Code. Items marked concealed by password managers (`org.nspasteboard.ConcealedType`) are never quoted. In the Basic tier, only clipboard changes made while a terminal was in front, and in the last 30 seconds by default, are used.
- **Types into terminals.** In the Full and Good tiers kaju submits a comment only after checking that Claude Code is the foreground process of the pane's terminal. If the check fails, nothing is typed. In the Basic tier kaju never presses Return, and pastes multi-line text only when the window title shows Claude Code; otherwise it pastes a single line with all control characters removed.
- **Controls iTerm2 and Terminal** through their scripting interfaces (Automation permission), and posts paste and Return keystrokes (Accessibility permission) for Terminal.app and Basic-tier terminals.
- **Stores** open reviews in `~/Library/Application Support/kaju/reviews/` until they are sent or discarded, and writes an event log without comment text to `~/Library/Logs/kaju.log`.
- **Makes no network connections.**

## Reporting a vulnerability

Please report security problems privately through GitHub's "Report a vulnerability" on the repository's Security tab, rather than in a public issue.
