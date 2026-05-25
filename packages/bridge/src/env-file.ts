import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function parseEnvLine(line: string): [string, string] | undefined {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#")) return undefined;

  const withoutExport = trimmed.startsWith("export ")
    ? trimmed.slice("export ".length).trimStart()
    : trimmed;
  const separator = withoutExport.indexOf("=");
  if (separator <= 0) return undefined;

  const key = withoutExport.slice(0, separator).trim();
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) return undefined;

  let value = withoutExport.slice(separator + 1).trim();
  const quote = value[0];
  if (
    (quote === "\"" || quote === "'") &&
    value.endsWith(quote) &&
    value.length >= 2
  ) {
    value = value.slice(1, -1);
  }
  return [key, value];
}

export function loadEnvFiles(): string[] {
  const bridgeRoot = resolve(
    dirname(fileURLToPath(import.meta.url)),
    "..",
  );
  const repoRoot = resolve(bridgeRoot, "..", "..");
  const loaded: string[] = [];

  for (const file of [
    join(repoRoot, ".env.local"),
    join(repoRoot, ".env"),
    join(bridgeRoot, ".env.local"),
    join(bridgeRoot, ".env"),
  ]) {
    if (!existsSync(file)) continue;
    const content = readFileSync(file, "utf8");
    for (const line of content.split(/\r?\n/)) {
      const parsed = parseEnvLine(line);
      if (!parsed) continue;
      const [key, value] = parsed;
      if (process.env[key] === undefined) {
        process.env[key] = value;
      }
    }
    loaded.push(file);
  }

  return loaded;
}
