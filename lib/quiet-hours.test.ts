import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { isQuietNow, nextAllowedTime, type QuietHours } from "./quiet-hours.ts";

type Fixture = { name: string; timeZone: string; now: string; quietHours: QuietHours | null; isQuiet?: boolean; nextAllowed?: string };
const fixtures = JSON.parse(readFileSync(new URL("../shared/fixtures/quiet-hours.json", import.meta.url), "utf8")) as Fixture[];

test("quiet-hours helpers match shared fixtures", async (t) => {
  for (const fixture of fixtures) {
    await t.test(fixture.name, () => {
      const now = new Date(fixture.now);
      if (fixture.isQuiet !== undefined) {
        assert.equal(isQuietNow(fixture.quietHours, fixture.timeZone, now), fixture.isQuiet);
      }
      if (fixture.nextAllowed) {
        assert.ok(fixture.quietHours, "nextAllowed case must have quiet hours");
        assert.equal(nextAllowedTime(fixture.quietHours, fixture.timeZone, now).toISOString(), fixture.nextAllowed);
      }
    });
  }
});
