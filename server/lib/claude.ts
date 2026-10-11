import Anthropic from "@anthropic-ai/sdk";

// Reads ANTHROPIC_API_KEY from the environment (or an `ant auth login` profile when running locally).
export const client = new Anthropic();

export const MODEL = "claude-opus-5-5";

export const CONTAMINANTS = ["nitrate", "arsenic", "lead", "manganese", "fluoride", "coliform"] as const;

/** Thrown for problems we can explain to the app user. */
export class UserFacingError extends Error {
  constructor(
    message: string,
    readonly status = 400,
  ) {
    super(message);
  }
}

/**
 * One Claude call that must return JSON matching `schema`.
 * Uses structured outputs so the reply is always valid JSON, and the server-side
 * fallback so a declined request is retried on another model automatically.
 */
export async function askForJson(params: {
  system: string;
  content: Anthropic.Beta.BetaContentBlockParam[];
  schema: Record<string, unknown>;
  effort: "low" | "medium" | "high";
  maxTokens: number;
}): Promise<unknown> {
  let response: Anthropic.Beta.BetaMessage;
  try {
    response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: params.maxTokens,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: params.system,
      output_config: {
        effort: params.effort,
        format: { type: "json_schema", schema: params.schema },
      },
      messages: [{ role: "user", content: params.content }],
    });
  } catch (error) {
    if (error instanceof Anthropic.AuthenticationError) {
      throw new UserFacingError("The ClearWell server's Claude API key is missing or invalid.", 500);
    }
    if (error instanceof Anthropic.RateLimitError) {
      throw new UserFacingError("The AI is busy right now. Please try again in a minute.", 503);
    }
    if (error instanceof Anthropic.APIConnectionError) {
      throw new UserFacingError("The ClearWell server couldn't reach the AI. Please try again.", 502);
    }
    if (error instanceof Anthropic.APIError) {
      console.error("Claude API error", error.status, error.message);
      throw new UserFacingError("The AI couldn't handle this request. Please try again.", 502);
    }
    // Most often: no API key configured, so the SDK can't build the request.
    console.error(error);
    throw new UserFacingError("The ClearWell server isn't connected to Claude yet. Check that its API key is set up.", 500);
  }

  if (response.stop_reason === "refusal") {
    throw new UserFacingError("The AI declined this request. Showing standard explanations instead.", 502);
  }
  if (response.stop_reason === "max_tokens") {
    throw new UserFacingError("The AI's answer was cut off. Please try again.", 502);
  }

  const text = response.content
    .filter((block): block is Anthropic.Beta.BetaTextBlock => block.type === "text")
    .map((block) => block.text)
    .join("");
  try {
    return JSON.parse(text);
  } catch {
    throw new UserFacingError("The AI sent back an answer ClearWell couldn't read. Please try again.", 502);
  }
}

/** If CLEARWELL_APP_TOKEN is set, rejects requests that don't send the same token. */
export function checkToken(request: Request): Response | null {
  const expectedToken = process.env.CLEARWELL_APP_TOKEN;
  if (expectedToken && request.headers.get("x-clearwell-token") !== expectedToken) {
    return Response.json({ error: "This app isn't allowed to use the ClearWell server. Check the app token in Settings." }, { status: 401 });
  }
  return null;
}

/** Shared request handling: optional app token, JSON body, friendly errors. */
export async function handleJson(request: Request, handler: (body: unknown) => Promise<unknown>): Promise<Response> {
  const rejected = checkToken(request);
  if (rejected) return rejected;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "The request wasn't valid JSON." }, { status: 400 });
  }

  try {
    return Response.json(await handler(body));
  } catch (error) {
    if (error instanceof UserFacingError) {
      return Response.json({ error: error.message }, { status: error.status });
    }
    console.error(error);
    return Response.json({ error: "Something went wrong on the ClearWell server." }, { status: 500 });
  }
}
