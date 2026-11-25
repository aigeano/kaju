# Changelog

All notable changes to kaju. Versions follow [Semantic Versioning](https://semver.org).

## Unreleased

## 0.1.0 - 2026-11-26

First release.

- Select Claude Code output in your terminal, press ⌃⌥K, and comment on it. Send one comment straight to Claude Code, or collect a review in a side panel and send it in one go.
- iTerm2 and Terminal.app: comments are sent automatically after kaju checks that Claude Code is the foreground program of the tab. iTerm2 also has a right-click item.
- tmux inside iTerm2 or Terminal.app: supported, but not yet tested. Reports are welcome.
- Other terminals: the comment is pasted as a single line and you press Return.
- Open reviews survive a restart. The hotkey and tags are set in `~/Library/Application Support/kaju/config.json`.
- Install with Homebrew (`brew install aigeano/tap/kaju`) or `make install`. kaju is built on your Mac and clears its own stale macOS permissions after an upgrade.
