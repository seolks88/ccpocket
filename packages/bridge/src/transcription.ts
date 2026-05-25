import type { IncomingMessage, ServerResponse } from "node:http";
import { fetch as undiciFetch, FormData } from "undici";

export const DEFAULT_TRANSCRIPTION_MODEL = "gpt-4o-mini-transcribe";
const MAX_TRANSCRIPTION_AUDIO_BYTES = 25 * 1024 * 1024;

export async function transcribeAudioWithOpenAI(params: {
  audioBase64: string;
  mimeType: string;
  fileName?: string;
  model?: string;
  language?: string;
}): Promise<{ text: string; model: string }> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not set on the Bridge machine");
  }

  const audio = Buffer.from(params.audioBase64, "base64");
  if (audio.length === 0) {
    throw new Error("Audio recording is empty");
  }
  if (audio.length > MAX_TRANSCRIPTION_AUDIO_BYTES) {
    throw new Error("Audio recording exceeds the 25 MB transcription limit");
  }

  const model = params.model?.trim() || DEFAULT_TRANSCRIPTION_MODEL;
  const form = new FormData();
  form.append(
    "file",
    new Blob([audio], {
      type: params.mimeType || "audio/mp4",
    }),
    params.fileName || "voice-command.m4a",
  );
  form.append("model", model);
  form.append("response_format", "json");
  if (params.language?.trim()) {
    form.append("language", params.language.trim());
  }

  const response = await undiciFetch(
    "https://api.openai.com/v1/audio/transcriptions",
    {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    },
  );

  const body = (await response.json().catch(() => null)) as
    | { text?: unknown; error?: { message?: unknown } }
    | null;
  if (!response.ok) {
    throw new Error(
      typeof body?.error?.message === "string"
        ? body.error.message
        : `OpenAI transcription failed with HTTP ${response.status}`,
    );
  }

  if (typeof body?.text !== "string") {
    throw new Error("OpenAI transcription response did not include text");
  }
  return { text: body.text.trim(), model };
}

function writeJson(
  res: ServerResponse,
  statusCode: number,
  body: Record<string, unknown>,
): void {
  res.writeHead(statusCode, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

export function handleTranscriptionRequest(
  req: IncomingMessage,
  res: ServerResponse,
): boolean {
  if (req.url !== "/api/transcribe" || req.method !== "POST") return false;

  let body = "";
  req.on("data", (chunk: Buffer) => {
    body += chunk.toString();
    if (body.length > MAX_TRANSCRIPTION_AUDIO_BYTES * 2) {
      req.destroy(new Error("Transcription request is too large"));
    }
  });
  req.on("end", async () => {
    try {
      const parsed = JSON.parse(body) as {
        requestId?: unknown;
        audioBase64?: unknown;
        mimeType?: unknown;
        fileName?: unknown;
        model?: unknown;
        language?: unknown;
      };
      if (
        typeof parsed.audioBase64 !== "string" ||
        typeof parsed.mimeType !== "string"
      ) {
        writeJson(res, 400, {
          success: false,
          error: "audioBase64 and mimeType are required",
        });
        return;
      }

      const requestId =
        typeof parsed.requestId === "string" ? parsed.requestId : undefined;
      console.log(
        `[transcribe] request${requestId ? ` ${requestId}` : ""} received`,
      );
      const result = await transcribeAudioWithOpenAI({
        audioBase64: parsed.audioBase64,
        mimeType: parsed.mimeType,
        fileName:
          typeof parsed.fileName === "string" ? parsed.fileName : undefined,
        model: typeof parsed.model === "string" ? parsed.model : undefined,
        language:
          typeof parsed.language === "string" ? parsed.language : undefined,
      });
      console.log(
        `[transcribe] request${requestId ? ` ${requestId}` : ""} succeeded`,
      );
      writeJson(res, 200, { success: true, requestId, ...result });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.warn(`[transcribe] failed: ${message}`);
      writeJson(res, 500, { success: false, error: message });
    }
  });
  req.on("error", (err) => {
    writeJson(res, 400, { success: false, error: err.message });
  });
  return true;
}
