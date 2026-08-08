import assert from "node:assert/strict";
import test from "node:test";
import { createTokenProvider } from "../src/token.js";

test("prefers the metadata server when it answers", async () => {
  let requestedUrl;
  const fetchImpl = async (url, init) => {
    requestedUrl = url;
    assert.equal(init.headers["Metadata-Flavor"], "Google");
    return new Response(JSON.stringify({ access_token: "meta-token", expires_in: 3600 }), { status: 200 });
  };
  const execFileImpl = async () => {
    throw new Error("gcloud must not be called");
  };
  const provider = createTokenProvider({ fetchImpl, execFileImpl });
  const token = await provider.getAccessToken();
  assert.equal(token, "meta-token");
  assert.ok(requestedUrl.startsWith("http://metadata.google.internal/"));
});

test("falls back to gcloud when the metadata server is unreachable", async () => {
  const fetchImpl = async () => {
    throw new Error("ENETUNREACH");
  };
  const execFileImpl = async (file, args) => {
    assert.equal(file, "gcloud");
    assert.deepEqual(args, ["auth", "print-access-token"]);
    return { stdout: "gcloud-token\n", stderr: "" };
  };
  const provider = createTokenProvider({ fetchImpl, execFileImpl });
  const token = await provider.getAccessToken();
  assert.equal(token, "gcloud-token");
});

test("falls back to gcloud when the metadata server answers but not ok", async () => {
  const fetchImpl = async () => new Response("not found", { status: 404 });
  const execFileImpl = async () => ({ stdout: "gcloud-token", stderr: "" });
  const provider = createTokenProvider({ fetchImpl, execFileImpl });
  assert.equal(await provider.getAccessToken(), "gcloud-token");
});

test("caches the token and does not re-fetch before it is close to expiring", async () => {
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    return new Response(JSON.stringify({ access_token: "t1", expires_in: 3600 }), { status: 200 });
  };
  let now = 1_000_000;
  const provider = createTokenProvider({ fetchImpl, execFileImpl: async () => ({ stdout: "" }), now: () => now });
  assert.equal(await provider.getAccessToken(), "t1");
  now += 1000; // well inside the hour
  assert.equal(await provider.getAccessToken(), "t1");
  assert.equal(calls, 1);
});

test("refreshes once the cached token is within the safety margin of expiring", async () => {
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    return new Response(JSON.stringify({ access_token: `t${calls}`, expires_in: 3600 }), { status: 200 });
  };
  let now = 1_000_000;
  const provider = createTokenProvider({ fetchImpl, execFileImpl: async () => ({ stdout: "" }), now: () => now });
  assert.equal(await provider.getAccessToken(), "t1");
  now += 3600 * 1000 - 1000; // inside the 60s refresh margin
  assert.equal(await provider.getAccessToken(), "t2");
  assert.equal(calls, 2);
});

test("throws when neither the metadata server nor gcloud can produce a token", async () => {
  const fetchImpl = async () => {
    throw new Error("no metadata server");
  };
  const execFileImpl = async () => {
    throw new Error("gcloud: command not found");
  };
  const provider = createTokenProvider({ fetchImpl, execFileImpl });
  await assert.rejects(() => provider.getAccessToken());
});
