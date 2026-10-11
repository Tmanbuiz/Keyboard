import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "./worker.mjs";

const secret = "unit-test-token-only-not-a-live-secret-0123456789";
function environment(overrides = {}) {
  return { API_TOKEN: secret, WRITING_LIMITER: { limit: async () => ({ success: true }) },
           AI: { run: async () => ({ response: "Edited text" }) }, ...overrides };
}
function request(body = { text: "hello", action: "grammar", language: "english" }, token = secret) {
  return new Request("https://example.test/write", { method: "POST", headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` }, body: JSON.stringify(body) });
}
test("unauthorized requests cannot invoke inference", async () => {
  let called = false;
  const response = await worker.fetch(request(undefined, "wrong"), environment({ AI: { run: () => { called = true; } } }));
  assert.equal(response.status, 401); assert.equal(called, false);
});
test("misconfigured service fails closed", async () => {
  assert.equal((await worker.fetch(request(), environment({ API_TOKEN: "" }))).status, 503);
});
test("invalid action and inherited object properties are rejected", async () => {
  for (const action of ["delete", "toString", "__proto__"]) {
    assert.equal((await worker.fetch(request({ text: "hello", action, language: "english" }), environment())).status, 400);
  }
});
test("payload limit is enforced before inference", async () => {
  let called = false;
  const response = await worker.fetch(request({ text: "a".repeat(40000), action: "grammar", language: "english" }), environment({ AI: { run: () => { called = true; } } }));
  assert.equal(response.status, 400); assert.equal(called, false);
});
test("rate limit prevents inference", async () => {
  assert.equal((await worker.fetch(request(), environment({ WRITING_LIMITER: { limit: async () => ({ success: false }) } }))).status, 429);
});
test("Yoruba is transmitted intact and response is not cached", async () => {
  let input;
  const response = await worker.fetch(request({ text: "Ẹ káàárọ̀", action: "translate", language: "yoruba" }), environment({ AI: { run: async (_, payload) => { input = payload; return { response: "Good morning" }; } } }));
  assert.equal(input.messages[1].content, "Ẹ káàárọ̀");
  assert.deepEqual(await response.json(), { text: "Good morning" });
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});
test("provider errors never echo submitted text or credentials", async () => {
  const response = await worker.fetch(request(), environment({ AI: { run: async () => { throw new Error(secret); } } }));
  assert.equal(response.status, 502); assert.equal((await response.text()).includes(secret), false);
});
test("language codes from the keyboard are accepted and unknown ones rejected", async () => {
  let input;
  const ok = await worker.fetch(request({ text: "bonjour", action: "translate", language: "fr" }), environment({ AI: { run: async (_, payload) => { input = payload; return { response: "hello" }; } } }));
  assert.equal(ok.status, 200); assert.match(input.messages[0].content, /French/);
  for (const language of ["xx", "__proto__", "toString", 7]) {
    assert.equal((await worker.fetch(request({ text: "hi", action: "translate", language }), environment())).status, 400);
  }
});
