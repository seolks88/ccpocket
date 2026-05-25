import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("loadEnvFiles", () => {
  const originalEnv = process.env;
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), "ccpocket-env-"));
    process.env = { ...originalEnv };
    delete process.env.OPENAI_API_KEY;
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    rmSync(tempDir, { recursive: true, force: true });
  });

  it("loads .env.local values without overwriting existing environment", async () => {
    const bridgeRoot = join(tempDir, "packages", "bridge");
    vi.doMock("node:url", async () => {
      const actual = await vi.importActual<typeof import("node:url")>(
        "node:url",
      );
      return {
        ...actual,
        fileURLToPath: () => join(bridgeRoot, "src", "env-file.ts"),
      };
    });
    writeFileSync(
      join(tempDir, ".env.local"),
      [
        "# comment",
        "OPENAI_API_KEY=sk-proj-from-file",
        "export BRIDGE_PORT=9876",
        "",
      ].join("\n"),
    );
    process.env.BRIDGE_PORT = "8765";

    const { loadEnvFiles } = await import("./env-file.js");

    expect(loadEnvFiles()).toContain(join(tempDir, ".env.local"));
    expect(process.env.OPENAI_API_KEY).toBe("sk-proj-from-file");
    expect(process.env.BRIDGE_PORT).toBe("8765");
  });
});
