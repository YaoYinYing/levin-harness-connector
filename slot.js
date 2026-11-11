// Which Levin model entry magpie writes, by the id Levin gives it.
//
// magpie's agent plugins can write only key paths that already exist in a JSON
// file. Levin keeps its models in an array (`llmConfigs`), and writing to an
// index — or a query — that matches nothing turns the array into an object and
// takes every model in it with it. Measured on magpie 0.1.3686:
//
//   llmConfigs[4]          → llmConfigs.4        (a new index: object, array gone)
//   llmConfigs.#(id=="x")  → llmConfigs["#(id==\"x\")"]  (no match: same damage)
//
// So this plugin writes to one entry that exists, named by its own `id`, which
// Levin keeps stable when models are reordered. tools/pin-slot.mjs finds that
// id in config.json and writes it here; until it does, this plugin loads
// nothing.
//
//   node tools/pin-slot.mjs              pin the entry that goes to magpie's gateway
//   node tools/pin-slot.mjs --create     add such an entry first (Levin closed)
//   node tools/pin-slot.mjs --list       show the entries and their ids
export const ENTRY_ID = null;

// Levin's config file. magpie expands ~ and $VAR in a path.
export const CONFIG = "~/Library/Application Support/Levin Harness/config.json";

// What the entry is called in Levin's model picker while magpie's gateway is in
// it. magpie puts the original name back when it disconnects.
export const NAME = "Levin Harness";
