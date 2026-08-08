// The wire contract requires every value in the response `fields` object to be
// a string. `BackendTransport.decode` (`CloudTransport.swift`) does
// `fields.compactMapValues { $0 as? String }`, which silently drops any key
// whose value isn't one — a nested array or number just vanishes, with no
// error the caller can see. A field built from `items` (only `messages`, from
// the screen reader) comes back from Vertex as an array of objects, and
// forwarding that array as-is would hit exactly that silent drop. This file is
// the one place that guarantee is kept.

export function encodeResponseFields(rawFields) {
  const encoded = {};
  for (const [name, value] of Object.entries(rawFields ?? {})) {
    // A model-reported null means "nothing to fill" — Reply's addressee, the
    // screen reader's sender when there is no message worth replying to.
    // Dropping the key has the same effect once decoded as sending the
    // literal `null` would: `compactMapValues` drops a JSON null exactly as
    // it drops a missing key. So this is a no-op for every caller, not a new
    // behavior — it just avoids an all-null response body for a refusal that
    // the caller reads as `.empty` either way.
    if (value === null || value === undefined) continue;
    encoded[name] = typeof value === "string" ? value : JSON.stringify(value);
  }
  return encoded;
}
