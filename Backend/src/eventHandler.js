// The analytics endpoint, whose whole job is refusing almost everything.
//
// `.claude/docs/analytics-policy.md` promises that no event carries anything
// typed, corrected, dictated or read off a screen — "not in a property, not in a
// free-text field, not truncated, not hashed". `AnalyticsEvent`
// (`AIKeyboard/Analytics/AnalyticsEvent.swift`) keeps that promise on the client
// by being a closed enum with no slot a string could go in. This file is the same
// promise kept on the server, where somebody can *check* it by reading a hundred
// lines instead of trusting the app that posted: the two tables below are the
// complete vocabulary, every key and every value in a request is matched against
// them, and anything else is a 400 that stores nothing.
//
// **Why the server half is worth writing at all**, given the client cannot
// produce a bad event: because the promise is about what this service will
// accept, not about what today's app sends. The endpoint is unauthenticated and
// its URL ships in the app, so "the client can't do that" is a statement about
// one of the callers. A validator that let unknown keys through would make the
// promise unfalsifiable — a future call site in a hurry, or anybody who found the
// URL, could post a sentence into `note` and it would sit in the logs regardless
// of what the policy document says.
//
// Pure request/response mapping, the same shape as `requestHandler.js`: no
// `http` import, so it is tested with plain function calls and no server.

// The envelope every event carries (`Analytics.envelope`).
//
// **Matched against a pattern, not merely typed as a string.** "It is a string"
// is exactly the check that lets a sentence through. An install id that is not a
// UUID, an app version that is not `0.1 (46)`, an OS version that is not digits
// and dots, a timestamp that is not an instant: each of those is the shape of a
// field that has stopped being an identifier and started being a message.
const ENVELOPE = {
  install_id: /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/,
  app_version: /^[0-9][0-9A-Za-z.-]{0,15} \([0-9A-Za-z.-]{1,16}\)$/,
  os_version: /^[0-9]{1,3}(\.[0-9]{1,3}){0,2}$/,
  sent_at: /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/
};

// The six events of the policy's section 2 and their complete property lists.
//
// Every property is required, because the client always sends all of an event's
// properties — a missing one is a caller this service does not recognise, not a
// caller being terse. The only value shapes are a bounded integer and a closed
// list of words: there is deliberately no "string" shape here, and adding one is
// a change to the policy rather than to this file.
//
// The bounds are the policy's own: ten onboarding steps (0-9), so a `step_index`
// of 40 is a client this service should not be storing rows for either.
const EVENTS = {
  onboarding_step_advanced: {
    step_index: { integer: { min: 0, max: 9 } },
    step_name: {
      oneOf: [
        "welcome",
        "palette",
        "languages",
        "add_keyboard",
        "full_access",
        "switch_confirmation",
        "microphone",
        "practice_writing",
        "practice_everyday",
        "practice_smart_tools"
      ]
    },
    via: { oneOf: ["continue", "skip", "switch_confirmed"] }
  },
  onboarding_completed: {
    skipped_step_count: { integer: { min: 0, max: 10 } }
  },
  full_access_confirmed: {},
  keyboard_added_confirmed: {},
  app_session_started: {
    // Ten years. An install cannot predate its own app, and a number far outside
    // this is a clock the device set wrong or a caller making things up.
    days_since_install: { integer: { min: 0, max: 3650 } }
  },
  screen_context_session_started: {}
};

// **No error message ever quotes what the caller sent.** This endpoint exists so
// that nothing free-text arrives; an error that echoed the offending key or value
// would hand it straight back out again, and put it in the logs of anybody who
// ever decides to log a failed response. The messages name what was expected
// instead, which is the half a client author needs.
function validateEvent(body) {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return "request body must be a JSON object";
  }
  if (typeof body.event !== "string") return "event must be a string";

  const properties = EVENTS[body.event];
  if (properties === undefined) return "unknown event";

  const allowed = new Set(["event", ...Object.keys(ENVELOPE), ...Object.keys(properties)]);
  for (const key of Object.keys(body)) {
    if (!allowed.has(key)) return "unknown property for this event";
  }

  for (const [key, pattern] of Object.entries(ENVELOPE)) {
    const value = body[key];
    if (typeof value !== "string") return `${key} must be a string`;
    if (!pattern.test(value)) return `${key} is not in the expected format`;
  }

  for (const [key, rule] of Object.entries(properties)) {
    const value = body[key];
    if (rule.integer) {
      // `Number.isInteger` rather than `typeof === "number"`: a float is a
      // client bug and `"3"` is a client sending a different type than the one
      // this property is declared with. Both are refused rather than coerced.
      if (!Number.isInteger(value)) return `${key} must be an integer`;
      if (value < rule.integer.min || value > rule.integer.max) {
        return `${key} is out of range`;
      }
    } else if (!rule.oneOf.includes(value)) {
      return `${key} must be one of the values this event declares`;
    }
  }

  return null;
}

// Rebuilt key by key from the tables above rather than storing the body that
// arrived. Validation has already refused everything else, so this is belt and
// braces — and it is the belt that survives somebody adding a branch to the
// validator later that lets an extra key through.
function storedEvent(body) {
  const stored = { event: body.event, received_at: new Date().toISOString() };
  for (const key of Object.keys(ENVELOPE)) stored[key] = body[key];
  for (const key of Object.keys(EVENTS[body.event])) stored[key] = body[key];
  return stored;
}

// **The sink is the log, because this project has no datastore and adding one
// would be a dependency.** `Backend/` has zero runtime dependencies for its model
// path and the app it serves states the same about itself, so a database client
// would be a bigger decision than the six counters it carries. Cloud Run sends
// stdout to Cloud Logging, where a JSON line arrives as a queryable
// `jsonPayload`, which is enough to answer the policy's questions with a log
// query.
//
// The limits are worth stating rather than discovering. Retention is whatever the
// log bucket keeps (30 days by default), so a retention curve longer than that
// needs an export before the window closes. Counting means a log-based metric or
// a BigQuery sink, not a `SELECT`. There is no dedupe and no idempotency key, so
// a client that ever retried would double count — `Analytics.send` deliberately
// does not retry, and that is now load-bearing on this side too. And a log write
// is best-effort: a dropped line is a lost event with nothing to reconcile
// against. For a setup funnel that is what v1 looks like; anything that needs
// joins over months needs a real sink, which is a new decision and not a bigger
// version of this one.
function recordToLog(event) {
  console.log(JSON.stringify({ analytics: event }));
}

export function handleEvent(body, { record = recordToLog } = {}) {
  const message = validateEvent(body);
  if (message) return { status: 400, body: { error: message } };

  record(storedEvent(body));
  // The client (`Analytics.send`) discards the response entirely and never
  // retries, so this body is for whoever is holding a `curl` open, not for the
  // app.
  return { status: 200, body: { recorded: true } };
}
