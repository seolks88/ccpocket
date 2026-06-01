import { describe, expect, it, vi } from "vitest";
import {
  compactPastHistoryMessageForClient,
  compactServerMessageForClient,
} from "./history-compaction.js";

describe("history compaction", () => {
  it("compacts large tool_result messages without mutating the original", () => {
    const content = `head\n${"x".repeat(1024)}\ntail`;
    const registerFullContent = vi.fn();
    const original = {
      type: "tool_result" as const,
      toolUseId: "tool-1",
      toolName: "Bash",
      content,
      historySeq: 7,
    };

    const compacted = compactServerMessageForClient(original, {
      sessionId: "s1",
      inlineLimitBytes: 24,
      headBytes: 8,
      tailBytes: 8,
      registerFullContent,
    });

    expect(original.content).toBe(content);
    expect(compacted).not.toBe(original);
    expect(compacted.content).toContain("Output truncated by Bridge");
    expect(compacted.content).toContain("head");
    expect(compacted.content).toContain("tail");
    expect(compacted.isTruncated).toBe(true);
    expect(compacted.truncation).toMatchObject({
      version: 1,
      kind: "tool_result_content",
      strategy: "head_tail",
      originalBytes: Buffer.byteLength(content, "utf8"),
      fullContentAvailable: true,
    });
    expect(compacted.truncation?.contentRef).toMatch(/^tr_[a-f0-9]{24}$/);
    expect(registerFullContent).toHaveBeenCalledWith(
      expect.objectContaining({
        sessionId: "s1",
        contentRef: compacted.truncation?.contentRef,
        content,
        contentBytes: Buffer.byteLength(content, "utf8"),
      }),
    );
  });

  it("leaves small tool_result messages unchanged", () => {
    const message = {
      type: "tool_result" as const,
      toolUseId: "tool-1",
      content: "ok",
    };

    expect(
      compactServerMessageForClient(message, {
        sessionId: "s1",
        inlineLimitBytes: 24,
      }),
    ).toBe(message);
  });

  it("does not compact when the preview would be larger than the original", () => {
    const registerFullContent = vi.fn();
    const message = {
      type: "tool_result" as const,
      toolUseId: "tool-1",
      content: "x".repeat(25),
    };

    expect(
      compactServerMessageForClient(message, {
        sessionId: "s1",
        inlineLimitBytes: 24,
        headBytes: 16,
        tailBytes: 8,
        registerFullContent,
      }),
    ).toBe(message);
    expect(registerFullContent).not.toHaveBeenCalled();
  });

  it("preserves unicode boundaries in head and tail previews", () => {
    const content = `가나다🙂${"x".repeat(32)}끝🙂`;
    const compacted = compactServerMessageForClient(
      { type: "tool_result", toolUseId: "tool-1", content },
      {
        sessionId: "s1",
        inlineLimitBytes: 16,
        headBytes: 10,
        tailBytes: 10,
      },
    );

    expect(compacted.content).not.toContain("\uFFFD");
    expect(compacted.content).toContain("가나다");
    expect(compacted.content).toContain("끝🙂");
  });

  it("compacts past history tool_result messages", () => {
    const content = "a".repeat(1024);
    const compacted = compactPastHistoryMessageForClient(
      {
        role: "tool_result",
        toolUseId: "tool-1",
        toolName: "Bash",
        content,
      },
      {
        sessionId: "s1",
        inlineLimitBytes: 24,
        headBytes: 8,
        tailBytes: 8,
      },
    );

    expect(compacted.content).toContain("Output truncated by Bridge");
    expect(compacted.isTruncated).toBe(true);
    expect(compacted.truncation?.originalBytes).toBe(1024);
  });
});
