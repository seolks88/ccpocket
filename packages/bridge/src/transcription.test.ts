import { createServer, type Server } from "node:http";
import { afterEach, describe, expect, it, vi } from "vitest";
import { handleTranscriptionRequest } from "./transcription.js";

async function startTestServer(): Promise<{ server: Server; url: string }> {
  const server = createServer((req, res) => {
    if (handleTranscriptionRequest(req, res)) return;
    res.writeHead(404);
    res.end();
  });

  await new Promise<void>((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  if (!address || typeof address === "string") {
    throw new Error("Failed to start test server");
  }
  return { server, url: `http://127.0.0.1:${address.port}` };
}

describe("handleTranscriptionRequest", () => {
  const originalOpenAiKey = process.env.OPENAI_API_KEY;
  const servers: Server[] = [];

  afterEach(async () => {
    process.env.OPENAI_API_KEY = originalOpenAiKey;
    vi.restoreAllMocks();
    await Promise.all(
      servers.splice(0).map(
        (server) =>
          new Promise<void>((resolve, reject) => {
            server.close((err) => (err ? reject(err) : resolve()));
          }),
      ),
    );
  });

  it("returns a 400 response when required audio fields are missing", async () => {
    const { server, url } = await startTestServer();
    servers.push(server);

    const response = await fetch(`${url}/api/transcribe`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ requestId: "missing-audio" }),
    });
    const body = (await response.json()) as {
      success?: boolean;
      error?: string;
    };

    expect(response.status).toBe(400);
    expect(body.success).toBe(false);
    expect(body.error).toContain("audioBase64");
  });

  it("reports a setup error when OPENAI_API_KEY is not configured", async () => {
    process.env.OPENAI_API_KEY = "";
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const { server, url } = await startTestServer();
    servers.push(server);
    const audioBase64 = Buffer.from("not real audio").toString("base64");

    const response = await fetch(`${url}/api/transcribe`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        requestId: "missing-key",
        audioBase64,
        mimeType: "audio/wav",
        fileName: "voice-command.wav",
        language: "ko",
      }),
    });
    const body = (await response.json()) as {
      success?: boolean;
      error?: string;
    };

    expect(response.status).toBe(500);
    expect(body.success).toBe(false);
    expect(body.error).toContain("OPENAI_API_KEY");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        "received mimeType=audio/wav fileName=voice-command.wav",
      ),
    );
    expect(logSpy.mock.calls.join("\n")).not.toContain(audioBase64);
  });
});
