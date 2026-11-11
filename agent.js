// magpie agent plugin: Levin Harness as its own row on magpie's Agents page.
//
// What it does: tells magpie where Levin Harness keeps the model it uses, and
// what to write beside it so Levin Harness's requests reach magpie's gateway
// with a key that names it: `magpie-levin-harness`. That key is why magpie's
// usage page, request ledger and routing rules then say "Levin Harness"
// instead of "pi" — Levin Harness is built on the pi SDK, so its requests carry
// `User-Agent: pi/…` and magpie would otherwise credit them to its built-in pi
// agent.
//
// magpie runs this module in moejs inside its own process: no Node, no fs, no
// process.env; it may import only files in this folder, and it may write only
// key paths that already exist in Levin Harness's JSON. slot.js says which entry
// that is, and why it is named by id rather than by index.
import { ENTRY_ID, CONFIG, NAME } from "./slot.js";
import { ICON } from "./icon-data.js";

if (!ENTRY_ID) {
  throw new Error(
    "Levin Harness: no model entry pinned yet — in this plugin's folder run " +
      "`node tools/pin-slot.mjs --create` once (Levin Harness closed). It adds a " +
      'model entry named "Levin Harness" and pins its id here. Nothing is written until then.',
  );
}

// Levin Harness keeps its models in an array and magpie writes gjson key paths,
// so every key below names the entry by its own id: an id Levin Harness keeps
// stable when models are reordered, and pinned only after tools/pin-slot.mjs has
// seen it in config.json.
const at = (key) => `llmConfigs.#(id=="${ENTRY_ID}").${key}`;

export const agent = {
  id: "levin-harness",
  name: "Levin Harness",
  config: CONFIG,
  model: at("model"),
  icon: ICON,
  // Levin Harness's own User-Agent, for a call that skips the key magpie wrote
  ua: ["levin", "levin-harness"],
  dir: "~/Library/Application Support/Levin Harness",
  notice:
    "Levin Harness reads the model when a chat starts: send the next message, or open a new chat.",
};

// connect is called with the model magpie picked, or without one. What it
// returns is written beside the model key; magpie keeps what each key held
// before and puts everything back when it disconnects.
export function connect({ gateway, model }) {
  const out = {
    [at("name")]: NAME,
    [at("api")]: "openai-responses",
    [at("baseUrl")]: gateway.v1,
    [at("apiKey")]: gateway.key,
  };
  // what /v1/models says of the model, when magpie knows it: Levin Harness shows
  // the context size in its picker and decides whether it may send images by it
  if (model && model.context > 0) out[at("contextWindow")] = model.context;
  if (model && model.output > 0) out[at("maxTokens")] = model.output;
  if (model && typeof model.images === "boolean") out[at("supportsImageInput")] = model.images;
  return out;
}
