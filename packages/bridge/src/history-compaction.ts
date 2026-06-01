import { createHash } from "node:crypto";
import type { ServerMessage, ToolResultTruncation } from "./parser.js";
import type { HistoryEntry } from "./session.js";
import type { SessionHistoryMessage } from "./sessions-index.js";

export const TOOL_RESULT_INLINE_LIMIT_BYTES = 24 * 1024;
export const TOOL_RESULT_PREVIEW_HEAD_BYTES = 16 * 1024;
export const TOOL_RESULT_PREVIEW_TAIL_BYTES = 8 * 1024;

const TRUNCATION_NOTICE_SEPARATOR = "\n\n";

export interface ToolResultFullContent {
  sessionId: string;
  contentRef: string;
  content: string;
  contentBytes: number;
  createdAt: number;
}

export interface ToolResultCompactionOptions {
  sessionId: string;
  inlineLimitBytes?: number;
  headBytes?: number;
  tailBytes?: number;
  registerFullContent?: (content: ToolResultFullContent) => void;
}

interface ToolResultLike {
  type?: string;
  role?: string;
  toolUseId?: string;
  toolName?: string;
  content?: unknown;
  historySeq?: unknown;
}

export function compactServerMessageForClient(
  message: ServerMessage,
  options: ToolResultCompactionOptions,
): ServerMessage {
  if (message.type !== "tool_result") return message;
  return compactToolResultLike(message, options) as ServerMessage;
}

export function compactHistoryEntryForClient(
  entry: HistoryEntry,
  options: ToolResultCompactionOptions,
): HistoryEntry {
  return {
    ...entry,
    message: compactServerMessageForClient(entry.message, options),
  };
}

export function compactPastHistoryMessageForClient(
  message: SessionHistoryMessage,
  options: ToolResultCompactionOptions,
): SessionHistoryMessage {
  if (message.role !== "tool_result") return message;
  return compactToolResultLike(message, options) as SessionHistoryMessage;
}

function compactToolResultLike<T extends ToolResultLike>(
  message: T,
  options: ToolResultCompactionOptions,
): T {
  if (typeof message.content !== "string") return message;
  const content = message.content;
  const originalBytes = Buffer.byteLength(content, "utf8");
  const inlineLimitBytes =
    options.inlineLimitBytes ?? TOOL_RESULT_INLINE_LIMIT_BYTES;
  if (originalBytes <= inlineLimitBytes) return message;

  const headBytes = options.headBytes ?? TOOL_RESULT_PREVIEW_HEAD_BYTES;
  const tailBytes = options.tailBytes ?? TOOL_RESULT_PREVIEW_TAIL_BYTES;
  const originalLines = countLines(content);
  const contentRef = createToolResultContentRef(
    options.sessionId,
    message.toolUseId,
    message.historySeq,
    content,
  );
  const truncation: ToolResultTruncation = {
    version: 1,
    kind: "tool_result_content",
    strategy: "head_tail",
    originalBytes,
    originalChars: content.length,
    originalLines,
    previewBytes: Math.min(originalBytes, headBytes + tailBytes),
    omittedBytes: Math.max(0, originalBytes - headBytes - tailBytes),
    contentRef,
    fullContentAvailable: true,
  };
  const preview = buildPreviewContent(content, truncation, headBytes, tailBytes);
  const previewBytes = Buffer.byteLength(preview, "utf8");
  if (previewBytes >= originalBytes) return message;

  options.registerFullContent?.({
    sessionId: options.sessionId,
    contentRef,
    content,
    contentBytes: originalBytes,
    createdAt: Date.now(),
  });

  return {
    ...message,
    content: preview,
    isTruncated: true,
    truncation: {
      ...truncation,
      previewBytes,
      omittedBytes: Math.max(0, originalBytes - previewBytes),
    },
  };
}

function createToolResultContentRef(
  sessionId: string,
  toolUseId: string | undefined,
  historySeq: unknown,
  content: string,
): string {
  const hash = createHash("sha256")
    .update(sessionId)
    .update("\0")
    .update(toolUseId ?? "")
    .update("\0")
    .update(String(historySeq ?? "live"))
    .update("\0")
    .update(content)
    .digest("hex")
    .slice(0, 24);
  return `tr_${hash}`;
}

function buildPreviewContent(
  content: string,
  truncation: ToolResultTruncation,
  headBytes: number,
  tailBytes: number,
): string {
  const head = takeUtf8Prefix(content, headBytes);
  const tail = takeUtf8Suffix(content, tailBytes);
  const notice = [
    "[CC Pocket] Output truncated by Bridge.",
    `Original: ${truncation.originalBytes} bytes / ${truncation.originalLines} lines.`,
    `Shown: first ${headBytes} bytes + last ${tailBytes} bytes.`,
    "Full output is available from a compatible CC Pocket client.",
  ].join("\n");
  return [head, notice, tail]
    .filter((part) => part.length > 0)
    .join(TRUNCATION_NOTICE_SEPARATOR);
}

function takeUtf8Prefix(value: string, maxBytes: number): string {
  let used = 0;
  let result = "";
  for (const char of value) {
    const bytes = Buffer.byteLength(char, "utf8");
    if (used + bytes > maxBytes) break;
    result += char;
    used += bytes;
  }
  return result;
}

function takeUtf8Suffix(value: string, maxBytes: number): string {
  let used = 0;
  const chars: string[] = [];
  const codePoints = Array.from(value);
  for (let i = codePoints.length - 1; i >= 0; i -= 1) {
    const char = codePoints[i];
    const bytes = Buffer.byteLength(char, "utf8");
    if (used + bytes > maxBytes) break;
    chars.push(char);
    used += bytes;
  }
  return chars.reverse().join("");
}

function countLines(value: string): number {
  if (value.length === 0) return 0;
  let lines = 1;
  for (let i = 0; i < value.length; i += 1) {
    if (value.charCodeAt(i) === 0x0a) lines += 1;
  }
  return lines;
}
