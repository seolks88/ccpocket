import { describe, expect, it } from "vitest";

import { parseClaudeAuthStatusOutput } from "./provider-auth-status.js";

describe("provider auth status", () => {
  it("parses Claude Code subscription login JSON", () => {
    expect(
      parseClaudeAuthStatusOutput(
        JSON.stringify({
          loggedIn: true,
          authMethod: "claude.ai",
          subscriptionType: "max",
        }),
      ),
    ).toEqual({
      authenticated: true,
      authMethod: "claude.ai",
      subscriptionType: "max",
    });
  });

  it("treats not logged in text as unauthenticated", () => {
    expect(parseClaudeAuthStatusOutput("Not logged in")).toEqual({
      authenticated: false,
    });
  });
});
