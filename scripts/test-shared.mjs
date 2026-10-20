import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const fixtures = JSON.parse(readFileSync(resolve(root, "shared/fixtures/dates.json"), "utf8"));
const timeZones = [...new Set(fixtures.map((fixture) => fixture.timeZone))];

for (const timeZone of timeZones) {
  const result = spawnSync(process.execPath, ["--test", "lib/dates.test.ts", "lib/quiet-hours.test.ts"], {
    cwd: root,
    env: { ...process.env, TZ: timeZone, LANG: "en_US.UTF-8" },
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
