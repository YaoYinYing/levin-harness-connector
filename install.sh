#!/bin/sh
# Install Levin Harness for magpie from GitHub in one command, and pin the model entry
# magpie may write.
#
#   ./install.sh                  pin an existing Levin Harness model entry that goes to magpie
#   ./install.sh --create         add one first (quit Levin Harness before this)
#   ./install.sh --list           only list the entries and their ids
#
# Why a script at all: magpie runs agent plugins in moejs, with no fs and no
# process.env, so a plugin cannot look at Levin's config to find out which
# entry to write — and magpie's JSON editor only replaces key paths that
# already exist, so a wrong or missing choice destroys the whole llmConfigs
# array. This script does the one part a plugin cannot: read the config, choose
# an entry, and pin its id into the installed copy of slot.js.
#
# Everything is idempotent: running it twice re-pins and reloads, nothing else.
set -eu

SPEC=${SPEC:-github:YaoYinYing/levin-harness-connector}
NAME=levin-harness-connector
MAGPIE=${MAGPIE:-magpie}
PIN_FLAGS=""
for arg in "$@"; do
  case $arg in
    --create | --list | --dry-run) PIN_FLAGS="$PIN_FLAGS $arg" ;;
    *) echo "install.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

command -v "$MAGPIE" >/dev/null 2>&1 || die "no '$MAGPIE' on PATH — install magpie first"

# MAGPIE_CONFIG_DIR makes this testable (and helps anyone with a non-default
# location); otherwise it is magpie's own rule.
CFG=${MAGPIE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/magpie}

say "→ installing $SPEC"
"$MAGPIE" plugin add "$SPEC" </dev/null || die "magpie plugin add failed"

# The installed copy, not the clone: magpie loads plugins from its own folder,
# so that is the slot.js magpie reads.
PLUGIN_DIR=$(node -e '
const { readdirSync, statSync, readFileSync } = require("node:fs");
const { join } = require("node:path");
const root = process.argv[1];
const wanted = process.argv[2];
let hits = [];
try {
  const nm = join(root, "node_modules");
  for (const name of readdirSync(nm)) {
    const p = join(nm, name, "package.json");
    try {
      if (JSON.parse(readFileSync(p, "utf8")).name === wanted) hits.push(join(nm, name));
    } catch {}
  }
} catch (err) {
  console.error(err.message);
}
process.stdout.write(hits[0] ?? "");
' "$CFG/plugins" "$NAME" 2>/dev/null) || true

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
say "Undo: pick Levin Harness's previous model in that row, or 'magpie $NAME default'."
