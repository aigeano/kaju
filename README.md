# kaju

**kaju: annotate, comment and collaborate with Claude Code.**

Select some of Claude Code's output in your terminal, press a hotkey, type a comment. kaju sends the quoted text and your comment straight back to Claude Code, which answers right away. For longer reviews of a plan, a document or an explainer, collect comments in a side panel and send them all at once.

kaju is named after a ginger cat who appears to run on a single brain cell but is exceptionally good at one thing: eating. kaju the tool is similar. It does not do much, but it is very good at one thing: comments.

## How it works

1. Select text in Claude Code's output. Claude Code copies your selection to the clipboard.
2. Press **⌃⌥K** (or, in iTerm2, right-click › **Comment with kaju**).
3. A small input opens next to the selection, showing the quote it captured. Type your comment.
4. Press **⏎**. kaju checks that Claude Code is running in that pane, then delivers:

   ```
   > the text you selected

   your comment
   ```

### Reviews

Press **⇥** in the input to start a review. Comments then collect in a panel docked on the side of the terminal window, one panel per pane. Send them all as one numbered message with **Send N to Claude Code** in the panel, or with **⌘⏎** in the input. Reviews are saved to disk on every change and come back after a restart.

### Keys

| Key | In the comment input |
|---|---|
| ⏎ | Send the comment, or add it to the review |
| ⇧⏎ | New line |
| ⇥ | Start or cancel a review |
| ⇧⇥ | Tag: fix · question · nit |
| ⌘⏎ | Add this comment and send the whole review |
| Esc | Close and clear the comment |
| ⌘/ | Show all keys |
| Drag | Move the input by its top line |

In the review panel: click a card to show it in full, **✎** or double-click to edit, **×** to remove, drag the header to move the panel, **Discard** needs two clicks.

The input stays open until you finish or clear it. Clicking back into the terminal leaves it in place. It shows only on its own tab (where the terminal allows it) and hides while another app is in front.

## Terminal support

Your shell does not matter. Your terminal does, because terminals differ in what they let other apps see and do.

| Tier | Terminals | What you get |
|---|---|---|
| **Full** | iTerm2; tmux inside iTerm2 or Terminal.app | Exact pane, per-tab visibility, comments submitted automatically after the safety check. iTerm2 also places the input at the selection and adds a right-click item. |
| **Good** | Terminal.app | Exact tab, per-tab visibility, comments submitted automatically after the safety check. |
| **Basic** | Ghostty, Warp, Alacritty, kitty, WezTerm, Hyper and others | The comment is pasted into the front window; **you press Return**. |

kitty and WezTerm can reach the Full tier with an adapter. Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md).

### Safety

kaju types into a terminal only when it is sure Claude Code is the program in front. A message pasted into a shell instead could run as commands, because the quoted lines start with `>`.

- **Full and Good tiers:** before sending, kaju checks the foreground process of the pane's terminal. If it is not Claude Code, nothing is typed: your comment goes to the clipboard, or your review stays open.
- **Basic tier:** kaju never presses Return. It pastes the multi-line message only when the window title shows Claude Code; otherwise it pastes everything as a single line with all control characters removed, which no shell will run. It pastes only if the window you commented on is still in front.

## Install

### Homebrew

```sh
brew install aigeano/tap/kaju
brew services start kaju
```

kaju is compiled on your Mac during install, so you need the Xcode command line tools 15.3 or later (`xcode-select --install`), which Homebrew already requires. Full Xcode is not needed.

After `brew upgrade kaju`, run `brew services restart kaju`.

### From source

```sh
git clone https://github.com/aigeano/kaju.git
cd kaju
make install      # builds, installs ~/Applications/kaju.app and a login item
make uninstall    # removes them again
```

### Permissions

| Permission | Needed for | When macOS asks |
|---|---|---|
| Automation › iTerm2 | Finding and typing into iTerm2 sessions | First comment in iTerm2 |
| Automation › Terminal | Finding Terminal.app tabs | First comment in Terminal.app |
| Accessibility | Typing into Terminal.app and Basic-tier terminals | First comment there |

iTerm2 also needs its Python API: iTerm2 › Settings › General › Magic › **Enable Python API**.

kaju is built on your Mac and signed ad hoc, so macOS treats every upgrade as a new app and forgets these permissions. After an upgrade, approve them again when asked. If a permission looks enabled in System Settings but kaju cannot use it, choose **Reset permissions** in kaju's menu-bar menu.

### Claude Code display modes

kaju reads your selection from the clipboard, where Claude Code's full-screen mode puts it automatically when you select text. In the classic scrolling mode, press **⌘C** after selecting, then the hotkey.

## Configuration

kaju's menu-bar menu has **Open config file**, which opens `~/Library/Application Support/kaju/config.json`:

```json
{
  "hotkey": "ctrl+opt+k",
  "tags": ["fix", "question", "nit"],
  "tmuxPath": null,
  "tmuxSocket": null,
  "clipboardWindowSeconds": 30
}
```

Choose **Reload config** after editing. If the hotkey is taken by another app, the menu says so.

## Privacy

kaju makes no network connections. It reads the clipboard to see your selection, never quotes items that password managers mark as concealed, and in the Basic tier only uses clipboard changes made while a terminal was in front. Comments are stored on your Mac only while a review is open. The log at `~/Library/Logs/kaju.log` records events, never comment text.

## Moving from the claude-annotate prototype

If you used the earlier iTerm2 script: remove `claude-annotate` from `plugins=(...)` in `~/.zshrc`, remove the iTerm2 key binding that invoked `claude_comment`, and stop the old script (kaju's menu offers this while it is running). kaju imports any open reviews from the prototype on first launch.

## Licence

Apache License 2.0. If you redistribute or build on kaju, keep the [NOTICE](NOTICE) file, which credits the author and links to this repository.

The iTerm2 helper uses the [`iterm2`](https://pypi.org/project/iterm2/) Python package (GPL-2.0-or-later), which is installed separately on your machine and not distributed with kaju.

kaju is an independent project and is not affiliated with Anthropic.
