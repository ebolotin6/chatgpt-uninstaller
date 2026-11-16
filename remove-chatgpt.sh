#!/usr/bin/env bash
# chatgpt-uninstaller: removes the ChatGPT desktop app (and its bundled Codex) from a Mac,
# with everything it leaves behind: processes, chats/memory, caches, settings, keychain items,
# Dock icon, VS Code extensions, the codex CLI, temp files, and ChatGPT data in Chrome,
# Firefox and Safari (via clear-chatgpt-browsers.py).
#
# Usage: ./remove-chatgpt.sh          preview: lists what would be removed, changes nothing
#        ./remove-chatgpt.sh --yes    removes it (asks for your Mac password for system files)
set -u
shopt -s nullglob dotglob
DO=0; [[ "${1:-}" == "--yes" ]] && DO=1
HERE="$(cd "$(dirname "$0")" && pwd)"
PY=/usr/bin/python3

# ---- look & feel (animations only when output is a real terminal) -----------------------
if [[ -t 1 ]]; then TTY=1; B=$'\e[1m'; DIM=$'\e[2m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; R=$'\e[31m'; N=$'\e[0m'
else TTY=0; B=; DIM=; G=; Y=; C=; R=; N=; fi

type_out() {  # typewriter effect
  local s="$1" i
  if (( TTY )); then for (( i=0; i<${#s}; i++ )); do printf '%s' "${s:i:1}"; sleep 0.012; done; echo
  else echo "$s"; fi
}
section() { echo; echo "${B}${C}▸ $*${N}"; }
item() { echo "  ${DIM}•${N} $*"; }
spin() {  # spin "label" cmd...  - runs cmd with a spinner
  local label="$1"; shift
  if (( ! TTY )); then "$@"; return; fi
  "$@" & local pid=$! i=0 f='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while kill -0 "$pid" 2>/dev/null; do printf '\r  %s %s' "${C}${f:i++%10:1}${N}" "$label"; sleep 0.08; done
  wait "$pid"; local rc=$?
  printf '\r\e[K'; return $rc
}
bar() {  # bar done total
  (( TTY )) || return 0
  local w=30 d=$(( $1 * 30 / ($2 ? $2 : 1) ))
  printf '\r  [%s%s] %d/%d' "${G}$(printf '█%.0s' $(seq 1 $d))${N}" "$(printf '░%.0s' $(seq 1 $(( w - d ))))" "$1" "$2"
  (( $1 == $2 )) && printf '\r\e[K'
  return 0
}
run() { item "$*"; (( DO )) && "$@"; return 0; }

echo
type_out "${B}ChatGPT uninstaller${N} ${DIM}— $( (( DO )) && echo 'removing' || echo 'preview, nothing will be changed')${N}"

# ---- processes ---------------------------------------------------------------------------
# Patterns chosen so they never match this script's own name.
PROC='chatgpt\.app|chatgpthelper|openai|/codex'
# Match the visible command line (pgrep -f also sees hidden original args and over-matches).
procs() { ps -axo pid=,command= | grep -i -E "$PROC" | grep -v -E 'grep|remove-chatgpt|clear-chatgpt'; }

section "Running ChatGPT processes"
procs | cut -c1-120 | while read -r line; do item "stop $line"; done
stop_all() {
  osascript -e 'quit app "ChatGPT"' >/dev/null 2>&1; sleep 2
  for sig in TERM KILL; do
    for pid in $(procs | awk '{print $1}'); do kill -$sig "$pid" 2>/dev/null; done; sleep 1
  done
}
(( DO )) && spin "Stopping ChatGPT" stop_all

# ---- browsers ----------------------------------------------------------------------------
section "Browser data (history, cookies, logins, site data)"
if ! "$PY" -c 'import sqlite3' >/dev/null 2>&1; then
  echo "  ${Y}Skipped: needs Python 3 (run: xcode-select --install)${N}"
elif (( DO )); then
  "$PY" "$HERE/clear-chatgpt-browsers.py" --yes && rm -rf ~/Library/Application\ Support/chatgpt-browser-backup-*
else
  "$PY" "$HERE/clear-chatgpt-browsers.py"
fi

section "Cached ChatGPT pages in browsers"
CACHES=(~/Library/Caches/Google/Chrome/*/{Cache,"Code Cache"} ~/Library/Caches/Firefox/Profiles/*/cache2)
LIST=$(mktemp)
scan_caches() { grep -l -a -i -E 'chatgpt\.com|openai\.com|oaistatic\.com|oaiusercontent\.com' -r "${CACHES[@]}" >"$LIST" 2>/dev/null; true; }
(( ${#CACHES[@]} )) && spin "Scanning browser caches" scan_caches
item "$(grep -c . "$LIST") cached pages"
if (( DO )) && [[ -s "$LIST" ]] && ! pgrep -x -q "Google Chrome|firefox"; then tr '\n' '\0' <"$LIST" | xargs -0 rm -f; fi
rm -f "$LIST"

# ---- documents ---------------------------------------------------------------------------
section "ChatGPT / Codex folders in Documents (moved to Trash, not deleted)"
for p in ~/Documents/ChatGPT ~/Documents/Codex; do
  [[ -e "$p" ]] || continue
  item "trash $p"
  (( DO )) && osascript -e "tell application \"Finder\" to delete POSIX file \"$p\"" >/dev/null
done

# ---- editors, CLIs, Homebrew -------------------------------------------------------------
section "VS Code / Cursor extensions"
for d in ~/.vscode/extensions/openai.* ~/.cursor/extensions/openai.*; do
  id=$(basename "$d" | sed -E 's/-[0-9][0-9.]*(-.*)?$//')
  cli=code; [[ "$d" == *cursor* ]] && cli=cursor
  (( DO )) && command -v "$cli" >/dev/null && "$cli" --uninstall-extension "$id" >/dev/null 2>&1
  run rm -rf "$d"
done

section "Command-line tools and Homebrew"
for m in /opt/homebrew/lib/node_modules/@openai/codex /usr/local/lib/node_modules/@openai/codex; do
  [[ -e "$m" ]] && command -v npm >/dev/null && run npm uninstall -g @openai/codex && break
done
if command -v brew >/dev/null; then
  for c in chatgpt codex codex-app; do brew list --cask "$c" >/dev/null 2>&1 && run brew uninstall --cask --zap "$c"; done
  brew list --formula codex >/dev/null 2>&1 && run brew uninstall --formula codex
fi

# ---- keychain, Dock, settings ------------------------------------------------------------
section "Keychain"
for svc in "Codex Safe Storage" "ChatGPT Safe Storage" "ChatGPT" "com.openai.chat" "com.openai.codex"; do
  while security find-generic-password -s "$svc" >/dev/null 2>&1; do
    item "delete keychain item: $svc"; (( DO )) || break
    security delete-generic-password -s "$svc" >/dev/null || break
  done
done

section "Dock"
"$PY" - ~/Library/Preferences/com.apple.dock.plist "$DO" <<'PY' 2>/dev/null
import plistlib, re, subprocess, sys
path, do = sys.argv[1], sys.argv[2] == "1"
d = plistlib.load(open(path, "rb"))
hit = lambda t: re.search(r"chatgpt|codex|openai", str(t.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")), re.I)
gone = [t for k in ("persistent-apps", "recent-apps") for t in d.get(k, []) if hit(t)]
for t in gone: print("  • remove Dock icon:", t["tile-data"].get("file-label"))
if do and gone:
    for k in ("persistent-apps", "recent-apps"): d[k] = [t for t in d.get(k, []) if not hit(t)]
    subprocess.run(["defaults", "import", "com.apple.dock", "-"], input=plistlib.dumps(d), check=True)
    subprocess.run(["killall", "Dock"])
PY

section "Settings"
for p in ~/Library/Preferences/com.openai.*.plist ~/Library/Preferences/ChatGPT*.plist; do
  run defaults delete "$(basename "$p" .plist)" 2>/dev/null
done
for a in /Applications/ChatGPT*.app; do  # forget the app so macOS stops listing it
  (( DO )) && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$a" 2>/dev/null
done

# ---- files -------------------------------------------------------------------------------
section "App, chats, memory, caches and other files"
L=~/Library; AS="$L/Application Support"
FILES=()
for p in \
  /Applications/ChatGPT*.app /Applications/Codex*.app ~/Applications/ChatGPT*.app ~/Applications/Codex*.app \
  ~/.codex ~/.chatgpt ~/.cache/codex-runtimes \
  "$AS"/ChatGPT "$AS"/OpenAI "$AS"/Codex "$AS"/com.openai.* "$AS"/CrashReporter/ChatGPT_* \
  "$AS"/*/NativeMessagingHosts/com.openai.* "$AS"/*/*/NativeMessagingHosts/com.openai.* \
  "$AS"/Code/CachedExtensionVSIXs/openai.* "$AS"/Code/logs/*/*/exthost/openai.* \
  "$AS"/Cursor/CachedExtensionVSIXs/openai.* \
  "$L"/Application\ Scripts/*com.openai.* "$L"/Group\ Containers/*com.openai.* "$L"/Containers/com.openai.* \
  "$L"/Caches/Codex "$L"/Caches/ChatGPT* "$L"/Caches/com.openai.* \
  "$L"/HTTPStorages/com.openai.* "$L"/HTTPStorages/ChatGPT* "$L"/WebKit/com.openai.* \
  "$L"/Logs/com.openai.* "$L"/Logs/ChatGPT* "$L"/Logs/Codex* \
  "$L"/Logs/DiagnosticReports/ChatGPT* "$L"/Logs/DiagnosticReports/Codex* \
  "$L"/Preferences/com.openai.* "$L"/Preferences/ChatGPT* \
  "$L"/Saved\ Application\ State/com.openai.* "$L"/LaunchAgents/com.openai.* \
  "$L"/Sounds/codex-* \
  /opt/homebrew/bin/codex /opt/homebrew/lib/node_modules/@openai/codex
do
  [[ -e "$p" || -L "$p" ]] && FILES+=("$p") && item "$p"
done
if (( DO )); then
  i=0; for p in "${FILES[@]}"; do rm -rf "$p" 2>/dev/null; bar $(( ++i )) ${#FILES[@]}; done
fi

TMPS=("${TMPDIR%/}"/com.openai.* "${TMPDIR%/}"/.com.openai.*)
section "Temp files"
item "${#TMPS[@]} temp folders"
(( DO && ${#TMPS[@]} )) && spin "Deleting temp files" rm -rf "${TMPS[@]}"

# ---- system files (need admin password) --------------------------------------------------
section "System files (needs your Mac password)"
SYS=()
for p in "/Library/Application Support/OpenAI" /Library/LaunchAgents/com.openai.* /Library/LaunchDaemons/com.openai.* \
         /Library/PrivilegedHelperTools/com.openai.* /private/var/db/receipts/com.openai.*; do
  [[ -e "$p" ]] && SYS+=("$p") && item "$p"
done
PKGS=$(pkgutil --pkgs | grep -i -E 'openai|chatgpt')
for k in $PKGS; do item "installer record $k"; done
if (( DO )) && { (( ${#SYS[@]} )) || [[ -n "$PKGS" ]]; }; then
  for k in $PKGS; do sudo pkgutil --forget "$k" >/dev/null; done
  (( ${#SYS[@]} )) && sudo rm -rf "${SYS[@]}"
fi

# ---- summary -----------------------------------------------------------------------------
echo
if (( DO )); then
  LEFT=$(procs; ls -d /Applications/ChatGPT*.app ~/.codex "$AS"/com.openai.* "$AS"/Codex "$L"/Group\ Containers/*com.openai.* 2>/dev/null)
  if [[ -z "$LEFT" ]]; then type_out "${G}${B}✔ ChatGPT is gone.${N}"
  else
    echo "${Y}Some items could not be removed:${N}"; echo "$LEFT" | sed 's/^/  /'
    echo "${DIM}Give your terminal app Full Disk Access (System Settings › Privacy & Security), reopen it, and run again.${N}"
  fi
else
  type_out "${B}Preview only.${N} Run ${C}./remove-chatgpt.sh --yes${N} to remove everything listed above."
fi
