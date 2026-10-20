import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { bucketFor, relativeDue, snoozeTarget } from "./dates.ts";

type DateCase = { fn: "bucketFor" | "relativeDue" | "snoozeTarget"; due?: string | null; preset?: "1h" | "tonight" | "tomorrow" | "nextweek"; expected: string };
type DateFixture = { name: string; timeZone: string; now: string; cases: DateCase[] };
const fixtures = JSON.parse(readFileSync(new URL("../shared/fixtures/dates.json", import.meta.url), "utf8")) as DateFixture[];

test("date helpers match shared fixtures for the process timezone", async (t) => {
  const zone = process.env.TZ;
  const matching = fixtures.filter((fixture) => fixture.timeZone === zone);
  assert.ok(matching.length, `No date fixtures for TZ=${zone}`);

  for (const fixture of matching) {
    await t.test(fixture.name, async (caseT) => {
      for (const item of fixture.cases) {
        await caseT.test(`${item.fn}: ${item.due ?? item.preset ?? "null"}`, () => {
          const now = new Date(fixture.now);
          let actual: string;
          if (item.fn === "bucketFor") actual = bucketFor(item.due ? new Date(item.due) : null, now);
          else if (item.fn === "relativeDue") actual = relativeDue(item.due ? new Date(item.due) : null, now);
          else actual = snoozeTarget(item.preset!, now).toISOString();
          assert.equal(actual, item.expected);
        });
      }
    });
  }
});
