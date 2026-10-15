import assert from "node:assert/strict";
import { test } from "node:test";
import { safeInternalPath } from "./auth-redirect.ts";

test("auth return targets keep reminder links on the app origin", () => {
  const reminderPath = "/r/10000000-0000-4000-8000-000000000001";
  assert.equal(safeInternalPath(reminderPath), reminderPath);
  assert.equal(safeInternalPath("/?open=abc#details"), "/?open=abc#details");
  for (const unsafe of [null, undefined, "", "https://other.example", "//other.example", "/\\other.example", "/\n/other.example", "javascript:alert(1)"]) {
    assert.equal(safeInternalPath(unsafe), "/", `Reject ${JSON.stringify(unsafe)}`);
  }
  // Dot-segment normalization must not create a protocol-relative target.
  assert.equal(safeInternalPath("/safe/..//other.example"), "/");
});
