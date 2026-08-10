import { test } from "node:test";
import assert from "node:assert/strict";
import { X509Certificate } from "node:crypto";
import { APPLE_APP_ATTEST_ROOT_PEM } from "../src/appleRoot.js";

test("the vendored root parses and is a self-signed CA", () => {
  const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_PEM);
  assert.equal(root.subject, root.issuer);
  assert.ok(root.ca, "the vendored certificate is not a CA certificate");
});

// **The assertion that does the work.** "It parses" is true of every certificate
// ever issued, including one substituted in a pull request, so a suite made only
// of the test above would accept an attacker's root as readily as Apple's.
test("the vendored root is the exact certificate Apple publishes", () => {
  const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_PEM);
  assert.equal(
    root.fingerprint256,
    "1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32"
  );
});

test("the vendored root has not expired", () => {
  const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_PEM);
  const now = new Date();
  assert.ok(now >= root.validFromDate && now <= root.validToDate, `root is outside ${root.validFrom}..${root.validTo}`);
});
