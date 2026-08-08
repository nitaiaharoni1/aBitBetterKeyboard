// Calls Vertex AI Gemini's `generateContent`, in the exact shape the scoring
// harnesses measure against: `Bar/ai-text/harness/VertexTransport.swift` for
// text actions, `Bar/screen-context/harness/vertex_vision.py` for screen
// reads. This is the only file in the service that makes a network call to
// Vertex, which is what lets every other file be tested without one — tests
// inject a fake `fetchImpl` here instead.
//
// The result is a discriminated object rather than a thrown error, because
// one branch (`refused`) is not a failure: `requestHandler.js` reads `kind`
// and answers the client accordingly.

import { buildResponseSchema } from "./schema.js";

// Measured, not a style choice. 0 turns thinking off entirely, and off is
// what breaks this product: the model transliterates Latin-script loanwords
// into Hebrew (`sync` becomes `סִינְק`) with no instruction able to talk it
// out of that. Unbounded thinking scored 42–45/58 on the text corpus with a
// 17–18s cloud tail; capped at 512 it scored 46 and 49 with a 4.4s tail and
// the same loanword preservation. See `VertexTransport.swift`'s comment on
// `thinkingBudget` for the full numbers this backend has to match.
const THINKING_BUDGET = 512;

function buildRequestBody({ instructions, prompt, fields, image }) {
  // Image first, prompt text second — the same order
  // `Bar/screen-context/harness/vertex_vision.py`'s `call` sends the corpus
  // through, kept for consistency rather than because the order is itself
  // measured to matter at temperature 0 with a fixed schema.
  const parts = [];
  if (image) parts.push({ inlineData: { mimeType: image.mimeType, data: image.data } });
  parts.push({ text: prompt });

  return {
    systemInstruction: { parts: [{ text: instructions }] },
    contents: [{ role: "user", parts }],
    generationConfig: {
      temperature: 0,
      responseMimeType: "application/json",
      responseSchema: buildResponseSchema(fields),
      thinkingConfig: { thinkingBudget: THINKING_BUDGET }
    }
  };
}

function classifyResponse(root) {
  // A blocked prompt comes back HTTP 200 with no candidates, so the block has
  // to be read before the content is — same order `VertexTransport.decode`
  // uses on the client side of this exact call.
  if (root.promptFeedback?.blockReason) {
    return { kind: "blocked", message: `Vertex blocked the prompt: ${root.promptFeedback.blockReason}` };
  }

  const candidate = root.candidates?.[0];
  if (!candidate) return { kind: "unavailable", message: "Vertex returned no candidates." };

  if (candidate.finishReason === "SAFETY" || candidate.finishReason === "PROHIBITED_CONTENT") {
    return { kind: "blocked", message: `Vertex blocked the response: ${candidate.finishReason}` };
  }
  // RECITATION (verbatim training-data overlap) and OTHER are declines too,
  // but neither is a safety verdict on the text, so they get the "refused"
  // shape (HTTP 200, `{"refused": true}`) instead of the 422 a safety block
  // gets — a distinction that matters to whoever reads a log, even though the
  // client (`BackendTransport.decode`) maps both to the identical
  // `AIEngineError.refused`.
  if (candidate.finishReason === "RECITATION" || candidate.finishReason === "OTHER") {
    return { kind: "refused" };
  }

  const text = candidate.content?.parts?.map((part) => part.text).find((value) => typeof value === "string");
  if (!text) return { kind: "refused" };

  let fields;
  try {
    fields = JSON.parse(text);
  } catch {
    return { kind: "unavailable", message: "Vertex returned a candidate whose text was not valid JSON." };
  }
  return { kind: "ok", fields };
}

/// `tokenProvider` and `fetchImpl` are the seams: `server.js` wires
/// `token.js`'s real provider and the global `fetch`; tests wire fakes.
export function createVertexClient({
  project,
  model,
  tokenProvider,
  fetchImpl = fetch,
  endpointBase = "https://aiplatform.googleapis.com/v1"
}) {
  const endpoint = `${endpointBase}/projects/${project}/locations/global/publishers/google/models/${model}:generateContent`;

  return {
    async call({ instructions, prompt, fields, image }) {
      let accessToken;
      try {
        accessToken = await tokenProvider.getAccessToken();
      } catch (error) {
        return { kind: "unauthorized", message: `No credential available to call Vertex: ${error.message}` };
      }

      let response;
      try {
        response = await fetchImpl(endpoint, {
          method: "POST",
          headers: { "content-type": "application/json", authorization: `Bearer ${accessToken}` },
          body: JSON.stringify(buildRequestBody({ instructions, prompt, fields, image }))
        });
      } catch (error) {
        return { kind: "unavailable", message: `Could not reach Vertex: ${error.message}` };
      }

      if (response.status === 401 || response.status === 403) {
        return { kind: "unauthorized", message: `Vertex rejected the credential (HTTP ${response.status}).` };
      }
      if (response.status === 429) {
        return { kind: "rateLimited", message: "Vertex is rate-limiting this project." };
      }
      if (response.status >= 500) {
        return { kind: "unavailable", message: `Vertex returned HTTP ${response.status}.` };
      }
      if (response.status !== 200) {
        const detail = await response.text().catch(() => "");
        return { kind: "badRequest", message: `Vertex returned HTTP ${response.status}: ${detail.slice(0, 300)}` };
      }

      let root;
      try {
        root = await response.json();
      } catch {
        return { kind: "unavailable", message: "Vertex returned a 200 that was not valid JSON." };
      }
      return classifyResponse(root);
    }
  };
}
