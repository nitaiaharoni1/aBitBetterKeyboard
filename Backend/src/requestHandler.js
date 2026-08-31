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

function unknownKey(value, allowed, path) {
  const key = Object.keys(value).find((candidate) => !allowed.has(candidate));
  return key === undefined ? null : `${path}.${key} is not allowed`;
}

const BODY_KEYS = new Set(["instructions", "prompt", "fields", "image", "audio"]);
const FIELD_KEYS = new Set(["name", "description", "items"]);
const MEDIA_KEYS = new Set(["mimeType", "data"]);

// Recursive because `items` fields nest the same {name, description, items?}
// shape one level down (only `messages` does this today, but the shape
// itself is generic — see `schema.js`), and a malformed nested field is
// better rejected here than sent on to fail inside Vertex with a worse error.
function validateFields(fields, path = "fields") {
  if (!Array.isArray(fields)) return `${path} must be an array`;
  for (const [index, field] of fields.entries()) {
    const at = `${path}[${index}]`;
    if (typeof field !== "object" || field === null || Array.isArray(field)) {
      return `${at} must be an object`;
    }
    const extra = unknownKey(field, FIELD_KEYS, at);
    if (extra) return extra;
    if (typeof field.name !== "string" || field.name.length === 0) return `${at}.name must be a non-empty string`;
    if (typeof field.description !== "string") return `${at}.description must be a string`;
    if (field.items !== undefined) {
      const nested = validateFields(field.items, `${at}.items`);
      if (nested) return nested;
    }
  }
  return null;
}

// `image` and `audio` are the same shape on the wire and are validated by the
// same function. They stay separate *fields* — and separate endpoints — because
// a picture of somebody's screen and a recording of their voice should be able
// to have different retention rules, and one shared field is how they quietly
// end up with one rule.
function validateMedia(value, name, expectedMimeType, hasSignature) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return `${name} must be an object`;
  }
  const extra = unknownKey(value, MEDIA_KEYS, name);
  if (extra) return extra;
  if (value.mimeType !== expectedMimeType) return `${name}.mimeType must be ${expectedMimeType}`;
  if (typeof value.data !== "string" || value.data.length === 0) {
    return `${name}.data must be non-empty base64`;
  }
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value.data)) {
    return `${name}.data must be valid base64`;
  }
  const bytes = Buffer.from(value.data, "base64");
  if (bytes.toString("base64") !== value.data || !hasSignature(bytes)) {
    return `${name}.data does not contain ${expectedMimeType} bytes`;
  }
  return null;
}

function isWAV(bytes) {
  return bytes.length >= 12
    && bytes.subarray(0, 4).toString("ascii") === "RIFF"
    && bytes.subarray(8, 12).toString("ascii") === "WAVE";
}

function isJPEG(bytes) {
  return bytes.length >= 4
    && bytes[0] === 0xff
    && bytes[1] === 0xd8
    && bytes[2] === 0xff
    && bytes[bytes.length - 2] === 0xff
    && bytes[bytes.length - 1] === 0xd9;
}

function validateBody(route, body) {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return "request body must be a JSON object";
  }
  const extra = unknownKey(body, BODY_KEYS, "body");
  if (extra) return extra;
  if (typeof body.instructions !== "string") return "instructions must be a string";
  if (typeof body.prompt !== "string") return "prompt must be a string";
  const fieldsError = validateFields(body.fields);
  if (fieldsError) return fieldsError;
  if (route === "text") {
    if (body.image !== undefined || body.audio !== undefined) {
      return "text requests cannot carry media";
    }
  } else if (route === "audio") {
    if (body.image !== undefined) return "audio requests cannot carry an image";
    const audioError = validateMedia(body.audio, "audio", "audio/wav", isWAV);
    if (audioError) return audioError;
  } else if (route === "screen") {
    if (body.audio !== undefined) return "screen requests cannot carry audio";
    const imageError = validateMedia(body.image, "image", "image/jpeg", isJPEG);
    if (imageError) return imageError;
  } else {
    return "unsupported request route";
  }
  return null;
}

export async function handleRequest(route, body, { vertexClient }) {
  const validationMessage = validateBody(route, body);
  if (validationMessage) return validationError(validationMessage);

  const result = await vertexClient.call({
    instructions: body.instructions,
    prompt: body.prompt,
    fields: body.fields,
    image: body.image ?? null,
    audio: body.audio ?? null
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
