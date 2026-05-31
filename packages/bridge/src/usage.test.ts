import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const osMock = vi.hoisted(() => ({
  home: "",
}));

vi.mock("node:os", async () => {
  const actual = await vi.importActual<typeof import("node:os")>("node:os");
  return {
    ...actual,
    homedir: () => osMock.home,
  };
});

import {
  clearUsageCacheForTest,
  fetchAllUsage,
  setUsageCacheTtlMsForTest,
} from "./usage.js";

function writeCodexSession(home: string, usedPercent: number): void {
  const dir = join(home, ".codex", "sessions", "2026", "05", "31");
  mkdirSync(dir, { recursive: true });
  writeFileSync(
    join(dir, "session.jsonl"),
    `${JSON.stringify({
      timestamp: new Date().toISOString(),
      type: "event_msg",
      payload: {
        type: "token_count",
        rate_limits: {
          primary: {
            used_percent: usedPercent,
            window_minutes: 300,
            resets_at: 1_800_000_000,
          },
        },
      },
    })}\n`,
  );
}

describe("usage cache", () => {
  let home: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "ccpocket-usage-"));
    osMock.home = home;
    clearUsageCacheForTest();
  });

  afterEach(() => {
    clearUsageCacheForTest();
    rmSync(home, { recursive: true, force: true });
  });

  it("reuses the same in-flight usage request", async () => {
    writeCodexSession(home, 12);

    const first = fetchAllUsage();
    const second = fetchAllUsage();

    expect(second).toBe(first);
    await expect(first).resolves.toMatchObject([
      { provider: "codex", fiveHour: { utilization: 12 } },
    ]);
  });

  it("returns cached usage inside the TTL", async () => {
    writeCodexSession(home, 12);
    await expect(fetchAllUsage()).resolves.toMatchObject([
      { provider: "codex", fiveHour: { utilization: 12 } },
    ]);

    writeCodexSession(home, 34);

    await expect(fetchAllUsage()).resolves.toMatchObject([
      { provider: "codex", fiveHour: { utilization: 12 } },
    ]);
  });

  it("refreshes usage when the cache is disabled for tests", async () => {
    setUsageCacheTtlMsForTest(0);
    writeCodexSession(home, 12);
    await expect(fetchAllUsage()).resolves.toMatchObject([
      { provider: "codex", fiveHour: { utilization: 12 } },
    ]);

    writeCodexSession(home, 34);

    await expect(fetchAllUsage()).resolves.toMatchObject([
      { provider: "codex", fiveHour: { utilization: 34 } },
    ]);
  });
});
