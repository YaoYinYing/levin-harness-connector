// Where Levin keeps the model magpie writes, and which entry it is.
//
// Both are written here by tools/pin-slot.mjs (or by install.sh / install.ps1,
// which call it), because a magpie agent plugin cannot find them itself: it
// runs in moejs, with no fs and no process.env, and it may only write key paths
// that already exist in Levin's JSON. Levin keeps its models in an array
// (`llmConfigs`), and writing to an index — or a query — that matches nothing
// turns the array into an object and takes every model in it with it. Measured
// on magpie 0.1.3686:
//
//   llmConfigs[4]          → llmConfigs.4        (a new index: object, array gone)
//   llmConfigs.#(id=="x")  → llmConfigs["#(id==\"x\")"]  (no match: same damage)
//
// So this plugin writes to one entry that exists, named by its own `id`, which
// Levin keeps stable when models are reordered. Until both values are pinned,
// agent.js throws and magpie loads nothing.
//
//   node tools/pin-slot.mjs              pin the entry that goes to magpie's gateway
//   node tools/pin-slot.mjs --create     add such an entry first (Levin closed)
//   node tools/pin-slot.mjs --list       show Levin's entries and their ids

// Levin's config.json, absolute. pin-slot.mjs finds it per platform —
// ~/Library/Application Support/Levin/config.json on macOS,
// %APPDATA%\levin-harness\config.json on Windows, and
// ~/.config/levin-harness/config.json on Linux — or takes --config.
export const CONFIG = null;

// The `id` of the `llmConfigs` entry magpie may write.
export const ENTRY_ID = null;

// What the entry is called in Levin's model picker while magpie's gateway is in
// it. magpie puts the original name back when it disconnects.
export const NAME = "Levin";
