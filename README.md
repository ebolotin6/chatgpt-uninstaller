# ChatGPT Uninstaller for Mac

Completely remove the ChatGPT desktop app from your Mac, along with everything it leaves behind.

Dragging ChatGPT to the Trash leaves gigabytes behind: chat history, memory, caches, settings, keychain items, a Dock icon, browser data and hundreds of temp files. This tool finds and removes all of it in one command, and shows you everything first.

<p align="center"><img src="demo.svg" alt="Animated demo of the uninstaller removing ChatGPT" width="680"></p>

## Install and run

Open **Terminal** (press `⌘ Space`, type `Terminal`, press Return) and paste:

```bash
curl -fsSL https://github.com/ebolotin6/chatgpt-uninstaller/archive/refs/heads/main.tar.gz | tar xz && cd chatgpt-uninstaller-main && ./remove-chatgpt.sh
```

That downloads the tool and shows a **preview** of what it found. Nothing is changed yet.

When you're happy with the list, remove everything:

```bash
./remove-chatgpt.sh --yes
```

You may be asked for your Mac password (for a few system files). When it finishes you'll see **✔ ChatGPT is gone.**

### Get the best result: give Terminal Full Disk Access

macOS protects Safari's data and a few app folders. To let the tool clean those too:

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Turn on **Terminal** (or the terminal app you use).
3. Quit Terminal completely (`⌘ Q`), reopen it, and run the command again.

Without this, everything else is still removed and the tool tells you what it couldn't reach.

## What it removes

| Area | Details |
|---|---|
| App | ChatGPT.app, the bundled Codex app, running ChatGPT processes |
| Your data | Chats, memory, projects and history (`~/.codex`, app support folders) |
| Leftovers | Caches, settings, cookies, logs, crash reports, widgets, sounds, temp files |
| Security | ChatGPT / Codex keychain items |
| Mac | Dock icon, app registration, installer records, system support files |
| Browsers | chatgpt.com / openai.com history, cookies, site data and cached pages in **Chrome, Firefox and Safari**, plus saved logins and bookmarks in Chrome and Firefox |
| Developer tools | ChatGPT / Codex VS Code and Cursor extensions, the `codex` command (npm or Homebrew), Homebrew casks |
| Documents | `~/Documents/ChatGPT` and `~/Documents/Codex` are **moved to the Trash**, not deleted, in case you want to keep something |

## What it does **not** touch

- Your ChatGPT **account** or chats stored online. To delete those, use ChatGPT's own settings on the web.
- The OpenAI developer libraries (`openai` for Python or Node), which other projects may use.
- Other apps that happen to mention OpenAI.

## Is it safe?

- **Preview first.** Without `--yes` it only lists what it would remove.
- **Readable.** Two short scripts, no downloads, no network calls, no tracking. Read them before running.
- **Careful with browsers.** It quits Chrome, Firefox and Safari before editing their data, makes a backup while it works, and removes only entries for ChatGPT / OpenAI sites. Everything else (your other history, cookies and logins) stays.

## Requirements

- macOS (Apple silicon or Intel)
- Python 3 for the browser step. Most Macs have it; if not, the tool skips that step and tells you how to install it (`xcode-select --install`).

## Uninstall this tool

It installs nothing. Just delete the folder:

```bash
cd .. && rm -rf chatgpt-uninstaller-main
```

## License

MIT. Not affiliated with or endorsed by OpenAI. ChatGPT is a trademark of OpenAI.
