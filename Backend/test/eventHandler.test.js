import assert from "node:assert/strict";
import test from "node:test";
import { handleEvent } from "../src/eventHandler.js";

// Nothing here writes to the log: every case passes its own `record`, so the
// suite also asserts *what would have been stored*, which is the half that makes
// the policy's "no event carries anything typed" checkable rather than merely
// stated.

function collector() {
  const stored = [];
  return { stored, record: (event) => stored.push(event) };
}

const envelope = {
  install_id: "8B0F0A5E-2C4D-4E1A-9F3B-7A6C5D4E3F21",
  app_version: "0.1 (46)",
  os_version: "26.2",
  sent_at: "2026-08-18T09:14:02Z"
};

// One valid body per event, exactly as `Analytics.envelope` builds it: the
// envelope, plus the event's own properties, flat.
const validEvents = {
  onboarding_step_advanced: { step_index: 4, step_name: "full_access", via: "skip" },
  onboarding_completed: { skipped_step_count: 3 },
  full_access_confirmed: {},
  keyboard_added_confirmed: {},
  app_session_started: { days_since_install: 12 },
  screen_context_session_started: {}
};

for (const [name, properties] of Object.entries(validEvents)) {
  test(`${name} is accepted and stored with its declared properties`, () => {
    const { stored, record } = collector();
    const { status, body } = handleEvent({ event: name, ...envelope, ...properties }, { record });

    assert.equal(status, 200);
    assert.deepEqual(body, { recorded: true });
    assert.equal(stored.length, 1);

    const { received_at: receivedAt, ...rest } = stored[0];
    assert.deepEqual(rest, { event: name, ...envelope, ...properties });
    // Server time, so a client with a wrong clock cannot decide when its own
    // event happened.
    assert.match(receivedAt, /^\d{4}-\d{2}-\d{2}T/);
  });
}

test("the ten step names and three advance reasons are the whole vocabulary", () => {
  const steps = [
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
  ];
  for (const [index, step] of steps.entries()) {
    for (const via of ["continue", "skip", "switch_confirmed"]) {
      const { status } = handleEvent(
        { event: "onboarding_step_advanced", ...envelope, step_index: index, step_name: step, via },
        { record: () => {} }
      );
      assert.equal(status, 200, `${step} via ${via}`);
    }
  }
});

// Every way in, and each one has to be a 400 that stored nothing. The last two
// are the ones this endpoint exists for: a sentence can only reach the log
// through a key nobody declared or through a declared key that stopped being
// checked for shape.
const refusals = [
  ["an unknown event name", { event: "keystroke_recorded", ...envelope }],
  ["an event name that is not a string", { event: 7, ...envelope }],
  ["a missing event name", { ...envelope }],
  ["an unknown property key", { event: "full_access_confirmed", ...envelope, note: "hello" }],
  [
    "a property belonging to a different event",
    { event: "onboarding_completed", ...envelope, skipped_step_count: 1, days_since_install: 4 }
  ],
  ["a missing declared property", { event: "app_session_started", ...envelope }],
  ["a missing envelope key", { event: "full_access_confirmed", install_id: envelope.install_id }],
  [
    "an integer sent as a string",
    { event: "app_session_started", ...envelope, days_since_install: "12" }
  ],
  [
    "an integer out of range",
    { event: "onboarding_step_advanced", ...envelope, step_index: 40, step_name: "welcome", via: "skip" }
  ],
  [
    "a step name outside the closed list",
    {
      event: "onboarding_step_advanced",
      ...envelope,
      step_index: 0,
      step_name: "practice_writing_but_longer",
      via: "skip"
    }
  ],
  [
    "free text in the install identifier",
    {
      event: "app_session_started",
      ...envelope,
      install_id: "meet me at the usual place at six",
      days_since_install: 1
    }
  ],
  [
    "free text in the app version",
    { event: "full_access_confirmed", ...envelope, app_version: "sorry I'm late (running behind)" }
  ],
  [
    "free text in the OS version",
    { event: "full_access_confirmed", ...envelope, os_version: "the message they typed" }
  ],
  ["free text in the timestamp", { event: "full_access_confirmed", ...envelope, sent_at: "just now" }],
  ["a body that is not an object", "full_access_confirmed"],
  ["a body that is an array", [{ event: "full_access_confirmed", ...envelope }]],
  ["a null body", null]
];

for (const [description, body] of refusals) {
  test(`${description} is a 400 and stores nothing`, () => {
    const { stored, record } = collector();
    const result = handleEvent(body, { record });

    assert.equal(result.status, 400, description);
    assert.equal(typeof result.body.error, "string");
    assert.equal(stored.length, 0);
  });
}

test("a refusal never quotes what the caller sent back at them", () => {
  const secret = "the sentence somebody typed into WhatsApp";
  const { body } = handleEvent(
    { event: "full_access_confirmed", ...envelope, note: secret },
    { record: () => {} }
  );
  assert.ok(!body.error.includes(secret));
  assert.ok(!body.error.includes("note"));
});
