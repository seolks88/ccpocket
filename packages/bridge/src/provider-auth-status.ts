import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

import type { Provider } from "./parser.js";

const execFileAsync = promisify(execFile);
const COMMAND_TIMEOUT_MS = 3000;
const CACHE_TTL_MS = 30_000;

export interface ProviderAuthStatus {
  provider: Provider;
  installed: boolean;
  authenticated: boolean;
  authMethod?: string;
  subscriptionType?: string;
  version?: string;
  error?: string;
  checkedAt: string;
}

let cached:
  | {
      expiresAt: number;
      value: ProviderAuthStatus[];
      pending?: Promise<ProviderAuthStatus[]>;
    }
  | undefined;

function cliEnv(): NodeJS.ProcessEnv {
  const env = { ...process.env };
  delete env.ANTHROPIC_API_KEY;
  delete env.ANTHROPIC_AUTH_TOKEN;
  const localBins = [
    join(homedir(), ".local", "bin"),
    "/opt/homebrew/bin",
    "/usr/local/bin",
  ];
  env.PATH = [...localBins, env.PATH ?? ""].filter(Boolean).join(":");
  return env;
}

async function execCli(command: string, args: string[]): Promise<string> {
  const { stdout, stderr } = await execFileAsync(command, args, {
    env: cliEnv(),
    timeout: COMMAND_TIMEOUT_MS,
  });
  return `${stdout ?? ""}${stderr ?? ""}`.trim();
}

function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

function isMissingCommand(err: unknown): boolean {
  return (
    err instanceof Error &&
    ("code" in err || "errno" in err) &&
    ((err as NodeJS.ErrnoException).code === "ENOENT" ||
      (err as NodeJS.ErrnoException).code === "EACCES")
  );
}

export function parseClaudeAuthStatusOutput(output: string): {
  authenticated: boolean;
  authMethod?: string;
  subscriptionType?: string;
} {
  const trimmed = output.trim();
  if (!trimmed) return { authenticated: false };

  try {
    const parsed = JSON.parse(trimmed) as Record<string, unknown>;
    return {
      authenticated: parsed.loggedIn === true || parsed.authenticated === true,
      authMethod:
        typeof parsed.authMethod === "string" ? parsed.authMethod : undefined,
      subscriptionType:
        typeof parsed.subscriptionType === "string"
          ? parsed.subscriptionType
          : undefined,
    };
  } catch {
    const lower = trimmed.toLowerCase();
    if (
      lower.includes("not logged in") ||
      lower.includes("unauthenticated") ||
      lower.includes("not authenticated")
    ) {
      return { authenticated: false };
    }
    return { authenticated: true };
  }
}

async function fetchClaudeStatus(
  checkedAt: string,
): Promise<ProviderAuthStatus> {
  let version: string | undefined;
  try {
    version = await execCli("claude", ["--version"]);
  } catch (err) {
    return {
      provider: "claude",
      installed: false,
      authenticated: false,
      error: isMissingCommand(err)
        ? "Claude Code CLI not found"
        : errorMessage(err),
      checkedAt,
    };
  }

  try {
    const out = await execCli("claude", ["auth", "status", "--json"]);
    const parsed = parseClaudeAuthStatusOutput(out);
    return {
      provider: "claude",
      installed: true,
      version,
      ...parsed,
      checkedAt,
    };
  } catch {
    try {
      const out = await execCli("claude", ["auth", "status"]);
      const parsed = parseClaudeAuthStatusOutput(out);
      return {
        provider: "claude",
        installed: true,
        version,
        ...parsed,
        checkedAt,
      };
    } catch (err) {
      return {
        provider: "claude",
        installed: true,
        version,
        authenticated: false,
        error: errorMessage(err),
        checkedAt,
      };
    }
  }
}

async function fetchCodexStatus(
  checkedAt: string,
): Promise<ProviderAuthStatus> {
  let version: string | undefined;
  try {
    version = await execCli("codex", ["--version"]);
  } catch (err) {
    return {
      provider: "codex",
      installed: false,
      authenticated: false,
      error: isMissingCommand(err) ? "Codex CLI not found" : errorMessage(err),
      checkedAt,
    };
  }

  const hasApiKey = Boolean(process.env.OPENAI_API_KEY?.trim());
  const hasAuthFile = existsSync(join(homedir(), ".codex", "auth.json"));
  return {
    provider: "codex",
    installed: true,
    authenticated: hasApiKey || hasAuthFile,
    authMethod: hasApiKey ? "api_key" : hasAuthFile ? "codex_auth" : undefined,
    version,
    checkedAt,
  };
}

export async function fetchProviderAuthStatuses(options?: {
  force?: boolean;
}): Promise<ProviderAuthStatus[]> {
  const now = Date.now();
  if (!options?.force && cached && cached.expiresAt > now) {
    if (cached.pending) return cached.pending;
    return cached.value;
  }

  const pending = (async () => {
    const checkedAt = new Date().toISOString();
    const value = await Promise.all([
      fetchClaudeStatus(checkedAt),
      fetchCodexStatus(checkedAt),
    ]);
    cached = { value, expiresAt: Date.now() + CACHE_TTL_MS };
    return value;
  })();

  cached = {
    value: cached?.value ?? [],
    expiresAt: now + CACHE_TTL_MS,
    pending,
  };
  return pending;
}
