#!/usr/bin/env node
// Pin which Levin Harness model entry magpie may write, into slot.js.
//
// magpie's agent plugins can write only key paths that already exist, so this
// plugin needs the id of one entry in Levin Harness's `llmConfigs` array — an id,
// not an index, because Levin Harness keeps ids stable when models are reordered.
// This tool finds that id, checks it is really there, and writes it into
// slot.js.
//
//   node tools/pin-slot.mjs                 pin the entry that goes to magpie's gateway
//   node tools/pin-slot.mjs --id <id>       pin one entry by its id
//   node tools/pin-slot.mjs --list          list the entries and their ids
//   node tools/pin-slot.mjs --create        add such an entry first (Levin Harness closed)
//   node tools/pin-slot.mjs --config <path> read another config.json (testing)
//   node tools/pin-slot.mjs --dry-run       show what it would do
//
// Without --create it never writes Levin Harness's config.json. With --create it
// appends one entry textually — every other byte of the file stays as it was,
// and a .bak-<timestamp> copy is left beside it.
import { readFileSync, writeFileSync, copyFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const slotPath = join(here, "..", "slot.js");

const argv = process.argv.slice(2);
const flag = (name) => argv.includes(name);
const value = (name) => {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
};

const slot = await import(pathToFileURL(slotPath).href);
const CONFIG = (value("--config") ?? slot.CONFIG).replace(/^~(?=$|\/)/, homedir());
const NAME = slot.NAME;
const GATEWAY_PORT = "3425";

let raw;
try {
  raw = readFileSync(CONFIG, "utf8");
} catch (err) {
  fail(
    `cannot read ${CONFIG}: ${err.message}\n` +
      `That is macOS's file protection, not a missing file: run this from magpie's\n` +
      `folder in a terminal with Full Disk Access, or from a normal shell outside a sandbox.`,
  );
}
const config = JSON.parse(raw);
const models = config?.llmConfigs;
if (!Array.isArray(models)) fail(`${CONFIG}: llmConfigs is not an array`);
const idOf = (m, i) => String(m?.id ?? "").trim() || `(no id, index ${i})`;

if (flag("--list")) {
  models.forEach((m, i) =>
    console.log(
      `${String(i).padStart(2)}  ${idOf(m, i)}  ${(m?.name ?? "").padEnd(24)} ${m?.model ?? ""}`,
    ),
  );
  process.exit(0);
}

// goesToMagpie: the entry's base URL is magpie's gateway on this machine, the
// only thing that says an entry is magpie's before it is connected
const goesToMagpie = (m) => {
  const url = String(m?.baseUrl ?? "").trim();
  if (!url) return false;
  try {
    const u = new URL(url);
    const local = ["localhost", "127.0.0.1", "::1", "[::1]"].includes(u.hostname);
    return local && u.port === GATEWAY_PORT;
  } catch {
    return false;
  }
};

const wanted = value("--id");
const chosen = (() => {
  if (wanted) {
    const i = models.findIndex((m) => String(m?.id ?? "") === wanted);
    if (i < 0) fail(`--id ${wanted}: no such id in ${CONFIG} (try --list)`);
    return i;
  }
  for (const pick of [(m) => m?.name === NAME && goesToMagpie(m), (m) => goesToMagpie(m)]) {
    const i = models.findIndex(pick);
    if (i >= 0) return i;
  }
  return -1;
})();

if (chosen < 0) {
  if (!flag("--create")) {
    fail(
      [
        `no entry in ${CONFIG} can be magpie's.`,
        ``,
        `Easiest: run this again with --create while Levin Harness is closed. It adds one`,
        `entry named "${NAME}" pointing at http://localhost:${GATEWAY_PORT}/v1, keeping a`,
        `.bak-… copy of the file as it was.`,
        ``,
        `Or add that entry yourself in Levin Harness (Settings → Model Provider): base URL`,
        `http://localhost:${GATEWAY_PORT}/v1, any model, any key. Then run this again.`,
      ].join("\n"),
    );
  }
  const entry = {
    name: NAME,
    baseUrl: `http://localhost:${GATEWAY_PORT}/v1`,
    model: "",
    provider: "openai",
    api: "openai-responses",
    thinkingLevel: "high",
    contextWindow: 1000000,
    supportsImageInput: true,
    id: crypto.randomUUID(),
    isDefault: false,
    apiKey: "",
  };
  const out = appendToArray(raw, "llmConfigs", entry);
  JSON.parse(out); // never write a file Levin Harness cannot read back
  if (flag("--dry-run")) {
    console.log(`would add "${NAME}" (id ${entry.id}) at llmConfigs[${models.length}] in ${CONFIG}`);
    console.log(`would pin ${entry.id} in ${basename(slotPath)}`);
    process.exit(0);
  }
  backup(CONFIG);
  writeFileSync(CONFIG, out);
  console.log(`added "${NAME}" (id ${entry.id}) at llmConfigs[${models.length}] in ${CONFIG}`);
  writeSlot(entry.id, models.length);
  process.exit(0);
}

const entry = models[chosen];
const id = String(entry?.id ?? "").trim();
if (!id) fail(`llmConfigs[${chosen}] has no id — give it one in Levin Harness, then run this again`);
if (!goesToMagpie(entry)) {
  console.log(
    `note: llmConfigs[${chosen}] ("${entry?.name ?? ""}") does not point at magpie's gateway ` +
      `yet. magpie writes its baseUrl when it connects, so it will after that.`,
  );
}
if (value("--id") === undefined && entry?.name !== NAME) {
  console.log(`magpie will rename llmConfigs[${chosen}] to "${NAME}" while it is connected.`);
}
console.log(`pinning llmConfigs[${chosen}] — "${entry?.name ?? ""}" (${entry?.model || "no model"})`);
writeSlot(id, chosen);

function writeSlot(entryId, index) {
  const src = readFileSync(slotPath, "utf8");
  if (new RegExp(`^export const ENTRY_ID = ${JSON.stringify(entryId)};$`, "m").test(src)) {
    console.log(`${basename(slotPath)} already pins that entry`);
    return;
  }
  const out = src.replace(
    /^export const ENTRY_ID = .*;$/m,
    `export const ENTRY_ID = ${JSON.stringify(entryId)};`,
  );
  if (out === src) fail(`${slotPath}: no "export const ENTRY_ID = …;" line to rewrite`);
  if (flag("--dry-run")) {
    console.log(`would rewrite ${basename(slotPath)}: ENTRY_ID = ${entryId}`);
    return;
  }
  writeFileSync(slotPath, out);
  console.log(`${basename(slotPath)} now pins ${entryId} (llmConfigs[${index}])`);
  // The pin belongs to this machine, not to the repository: keep it out of
  // `git status` and out of `git pull`'s way. Only touches this clone.
  if (inGitWorkTree()) {
    const r = spawnSync("git", ["update-index", "--skip-worktree", slotPath], { cwd: here });
    if (r.status === 0) {
      console.log(`${basename(slotPath)} is now skip-worktree: this pin stays local, pulls leave it alone.`);
      console.log(`To share a pin on purpose: git update-index --no-skip-worktree ${basename(slotPath)}`);
    }
  }
  console.log(`In magpie: Plugins → installed → this plugin off, then on.`);
}

function backup(path) {
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..*/, "");
  const to = `${path}.bak-${stamp}`;
  copyFileSync(path, to);
  console.log(`the file before this change is at ${to}`);
}

// appendToArray puts item last in the array at key, touching nothing else: the
// array's closing bracket is found by scanning the text, so comments, key order
// and formatting elsewhere stay exactly as they were.
function appendToArray(text, key, item) {
  const at = text.indexOf(`"${key}"`);
  if (at < 0) fail(`${CONFIG}: no "${key}" key`);
  const open = text.indexOf("[", at);
  if (open < 0) fail(`${CONFIG}: ${key} is not an array`);
  const close = matchBracket(text, open);
  if (close < 0) fail(`${CONFIG}: ${key} array is not closed`);

  const lineStart = text.lastIndexOf("\n", open) + 1;
  const baseIndent = /^[ \t]*/.exec(text.slice(lineStart))[0];
  const body = text.slice(open + 1, close);
  const memberIndent = /\n([ \t]+)\S/.exec(body)?.[1] ?? baseIndent + "  ";
  const unit = memberIndent.slice(baseIndent.length) || "  ";
  const member = JSON.stringify(item, null, unit)
    .split("\n")
    .map((line, i) => (i === 0 ? line : memberIndent + line))
    .join("\n");

  const empty = body.trim().length === 0;
  // cut at the last character worth keeping, then rebuild the closing bracket's
  // own line, so the comma the new member needs never lands on a line alone
  const before = text.slice(0, close).replace(/\s+$/, "");
  const comma = empty || before.endsWith(",") ? "" : ",";
  const lead = empty ? "" : "\n";
  return `${before}${comma}${lead}${memberIndent}${member}\n${baseIndent}${text.slice(close)}`;
}

// matchBracket is the index of the bracket closing the one at open, skipping
// brackets inside strings.
function matchBracket(text, open) {
  let depth = 0;
  let inStr = false;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') inStr = true;
    else if (c === "[" || c === "{") depth++;
    else if (c === "]" || c === "}") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function inGitWorkTree() {
  const r = spawnSync("git", ["rev-parse", "--is-inside-work-tree"], { cwd: here });
  return r.status === 0 && String(r.stdout).trim() === "true";
}

function fail(message) {
  console.error(`pin-slot: ${message}`);
  process.exit(1);
}
