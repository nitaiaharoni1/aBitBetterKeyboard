// Pure request/response mapping: given an already-parsed JSON body and a
// `vertexClient` (the seam `vertexClient.js` implements for real and tests
// fake), decides what to send back. No `http` import here — `httpServer.js`
// is the only file that talks to an actual socket, which is what lets this
// file be tested with plain function calls and no server.

import { encodeResponseFields } from "./fields.js";

// Every outcome `vertexClient.call` can report, translated into exactly the
// HTTP status `BackendTransport.mapped`
// (`Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudTransport.swift`)
// already knows how to read. "use exactly these" is the contract's own
// wording; this table is where that promise is kept in one place.
const STATUS_BY_KIND = {
  ok: 200,
  refused: 200,
  blocked: 422, // provider safety block — a decision about the text, not a failure
  unauthorized: 401, // no usable credential, ours or Vertex's
  rateLimited: 429,
  unavailable: 502, // any 5xx collapses to "unavailable" on the client's side
  badRequest: 400 // surfaced verbatim; the client's default case reads the message as-is
};

function validationError(message) {
  return { status: 400, body: { error: message } };
}

// Recursive because `items` fields nest the same {name, description, items?}
// shape one level down (only `messages` does this today, but the shape
// itself is generic — see `schema.js`), and a malformed nested field is
// better rejected here than sent on to fail inside Vertex with a worse error.
function validateFields(fields, path = "fields") {
  if (!Array.isArray(fields)) return `${path} must be an array`;
  for (const [index, field] of fields.entries()) {
    const at = `${path}[${index}]`;
    if (typeof field !== "object" || field === null) return `${at} must be an object`;
    if (typeof field.name !== "string" || field.name.length === 0) return `${at}.name must be a non-empty string`;
    if (typeof field.description !== "string") return `${at}.description must be a string`;
    if (field.items !== undefined) {
      const nested = validateFields(field.items, `${at}.items`);
      if (nested) return nested;
    }
  }
  return null;
}

function validateBody(body) {
  if (typeof body !== "object" || body === null) return "request body must be a JSON object";
  if (typeof body.instructions !== "string") return "instructions must be a string";
  if (typeof body.prompt !== "string") return "prompt must be a string";
  const fieldsError = validateFields(body.fields);
  if (fieldsError) return fieldsError;
  if (body.image !== undefined) {
    if (typeof body.image !== "object" || body.image === null) return "image must be an object";
    if (typeof body.image.mimeType !== "string") return "image.mimeType must be a string";
    if (typeof body.image.data !== "string") return "image.data must be a base64 string";
  }
  return null;
}

export async function handleRequest(body, { vertexClient }) {
  const validationMessage = validateBody(body);
  if (validationMessage) return validationError(validationMessage);

  const result = await vertexClient.call({
    instructions: body.instructions,
    prompt: body.prompt,
    fields: body.fields,
    image: body.image ?? null
  });

  const status = STATUS_BY_KIND[result.kind];
  if (status === undefined) {
    // A `vertexClient` bug, not a request problem — still answer inside the
    // "5xx = unavailable" bucket rather than let an unrecognized kind reach
    // the client as something worse than a clear error.
    return { status: 502, body: { error: `unhandled result kind: ${result.kind}` } };
  }

  if (result.kind === "ok") return { status, body: { fields: encodeResponseFields(result.fields) } };
  if (result.kind === "refused") return { status, body: { refused: true } };
  return { status, body: { error: result.message ?? "unknown error" } };
}
