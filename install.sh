#!/bin/sh
# Install Levin Harness for magpie from GitHub in one command, and pin the model entry
# magpie may write.
#
#   sh install.sh                  pin an existing Levin Harness model entry that goes to magpie
#   sh install.sh --create         add one first (quit Levin Harness before this)
#   sh install.sh --list           only list the entries and their ids
#   sh install.sh --link           also put a `magpie` command on PATH (~/.local/bin/magpie)
#
# macOS, Linux and WSL. On Windows run install.ps1 instead.
#
# Why a script at all: magpie runs agent plugins in moejs, with no fs and no
# process.env, so a plugin cannot look at Levin's config to find out which entry
# to write — and magpie's JSON editor only replaces key paths that already
# exist, so a wrong or missing choice destroys the whole llmConfigs array. This
# script does the one part a plugin cannot: read the config, choose an entry,
# and pin its id into the installed copy of slot.js.
#
# Everything is idempotent: running it twice re-pins and reloads, nothing else.
set -eu

SPEC=${SPEC:-github:YaoYinYing/levin-harness-connector}
NAME=levin-harness-connector
PIN_FLAGS=""
LINK=no
for arg in "$@"; do
  case $arg in
    --create | --list | --dry-run) PIN_FLAGS="$PIN_FLAGS $arg" ;;
    --link) LINK=yes ;;
    -h | --help)
      # the usage block at the top of this file, up to its first blank comment line
      awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
      exit 0
      ;;
    *) echo "install.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

# magpie installed from a .dmg is an app, and its command line lives inside the
# bundle: `magpie` is often not on PATH at all. Look where it can be.
resolve_magpie() {
  if [ -n "${MAGPIE:-}" ]; then
    [ -x "$MAGPIE" ] || die "MAGPIE=$MAGPIE is not executable"
    printf '%s' "$MAGPIE"
    return
  fi
  for cmd in magpie magpie-cli; do
    if command -v "$cmd" >/dev/null 2>&1; then
      command -v "$cmd"
      return
    fi
  done
  for app in "$HOME/Applications/magpie.app" /Applications/magpie.app \
    /Applications/Magpie.app "$HOME/Applications/Magpie.app" \
    /Applications/Utilities/magpie.app /opt/homebrew/bin/magpie /usr/local/bin/magpie \
    "$HOME/.local/bin/magpie" "$HOME/.local/bin/magpie-cli"; do
    if [ -x "$app/Contents/MacOS/magpie" ]; then
      printf '%s' "$app/Contents/MacOS/magpie"
      return
    fi
    if [ -f "$app" ] && [ -x "$app" ]; then
      printf '%s' "$app"
      return
    fi
  done
  return 1
}

command -v node >/dev/null 2>&1 || die "node is not on PATH — install Node.js 18 or newer, then run this again"

if ! MAGPIE=$(resolve_magpie); then
  die "no magpie found. Looked on PATH, then in /Applications/magpie.app and
  ~/Applications/magpie.app. If it lives elsewhere:
      MAGPIE=/path/to/magpie.app/Contents/MacOS/magpie sh install.sh"
fi
say "→ magpie: $MAGPIE"

if [ "$LINK" = yes ]; then
  # A symlink, not a copy: the app keeps updating its own binary.
  BIN_DIR=${MAGPIE_BIN_DIR:-$HOME/.local/bin}
  mkdir -p "$BIN_DIR"
  ln -sf "$MAGPIE" "$BIN_DIR/magpie"
  say "→ linked $BIN_DIR/magpie → $MAGPIE"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) say "  note: $BIN_DIR is not on PATH in this shell; add it to use plain 'magpie'" ;;
  esac
fi

say "→ installing $SPEC"
"$MAGPIE" plugin add "$SPEC" </dev/null || die "magpie plugin add failed"

# The installed copy, not the clone: magpie loads plugins from its own folder,
# so that is the slot.js magpie reads.
CFG=${MAGPIE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/magpie}
PLUGIN_DIR=$(node -e '
const { readdirSync, readFileSync } = require("node:fs");
const { join } = require("node:path");
const [root, wanted] = process.argv.slice(1);
const hits = [];
try {
  const nm = join(root, "plugins", "node_modules");
  for (const name of readdirSync(nm)) {
    try {
      const pkg = JSON.parse(readFileSync(join(nm, name, "package.json"), "utf8"));
      if (pkg.name === wanted) hits.push(join(nm, name));
    } catch {}
  }
} catch {}
process.stdout.write(hits[0] ?? "");
' "$CFG" "$NAME" 2>/dev/null) || true

[ -n "$PLUGIN_DIR" ] && [ -d "$PLUGIN_DIR" ] || die "could not find the installed $NAME under $CFG/plugins/node_modules"

say "→ plugin lives at $PLUGIN_DIR"
say "→ pinning the Levin Harness model entry magpie may write"
node "$PLUGIN_DIR/tools/pin-slot.mjs" $PIN_FLAGS || die "pinning failed (see above)"

case " $PIN_FLAGS " in
  *" --list "* | *" --dry-run "*) exit 0 ;;
esac

# A plugin's agent module is compiled when magpie starts, so a new pin is only
# read after the plugin is loaded again.
"$MAGPIE" plugin off "$NAME" </dev/null >/dev/null 2>&1 || true
"$MAGPIE" plugin on "$NAME" </dev/null >/dev/null 2>&1 || true

say ""
say "Done. In magpie → Agents → the Levin Harness row, pick a model."
say "Levin Harness reads its model when a chat starts: send the next message or open a new chat."
say "Undo: pick Levin Harness's previous model in that row, or '$MAGPIE' $NAME default."
