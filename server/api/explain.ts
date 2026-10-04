import { z } from "zod";
import { askForJson, CONTAMINANTS, handleJson, UserFacingError } from "../lib/claude.js";

// What the app sends. Status colors were already decided by the official limits table in the app.
const ExplainRequest = z.object({
  household: z.object({
    infantOrPregnantAtHome: z.boolean(),
    wellAge: z.string().max(60),
    county: z.string().max(60),
  }),
  results: z
    .array(
      z.object({
        contaminant: z.enum(CONTAMINANTS),
        name: z.string().max(60),
        measured: z.string().max(40),
        status: z.enum(["green", "amber", "red"]),
        statusMeaning: z.string().max(40),
        officialLimit: z.string().max(120),
        mostAtRisk: z.string().max(200),
        trend: z.string().max(200).nullish(),
        approvedNextStep: z.string().max(600),
      }),
    )
    .min(1)
    .max(CONTAMINANTS.length),
});

const ExplainResponse = z.object({
  explanations: z.array(
    z.object({
      contaminant: z.enum(CONTAMINANTS),
      explanation: z.string(),
      nextStep: z.string(),
    }),
  ),
});

// JSON schema for structured outputs. Note there is no status field: the AI cannot change a color.
const responseSchema = {
  type: "object",
  properties: {
    explanations: {
      type: "array",
      items: {
        type: "object",
        properties: {
          contaminant: { type: "string", enum: [...CONTAMINANTS] },
          explanation: { type: "string" },
          nextStep: { type: "string" },
        },
        required: ["contaminant", "explanation", "nextStep"],
        additionalProperties: false,
      },
    },
  },
  required: ["explanations"],
  additionalProperties: false,
};

const SYSTEM = `You write plain-English explanations of private well water test results for ClearWell, an app that helps Minnesota families understand their well water.

Each result arrives with a status color (green, amber or red). That color was already decided by a fixed table of official limits from the EPA and the Minnesota Department of Health (MDH). It is final. Never change it, question it, or describe the water as safer or more dangerous than the color says.

Write for a busy parent at about a 6th-grade reading level. Use short sentences and everyday words; if a technical word is unavoidable, explain it.

For each result, write:
- explanation: 2-3 sentences on what this result means for this particular household. If an infant or pregnant person lives in the home and the result is amber or red for something most dangerous to babies or pregnancy, say that first. Mention the trend if one is given.
- nextStep: 1-2 sentences built from the approved next step. For any red result, tell the family to contact MDH or a certified lab.

Use only the facts you are given: the measured value, the official limit, who is most at risk, the trend and the approved next step. Do not add numbers, limits or health effects that are not provided. Do not diagnose anyone or predict illness, and do not claim what caused a result; a rising trend "may be worth looking into" but its cause is unknown.

Return one entry for every result, using the same contaminant ids.`;

const MDH_HELP = "Contact the Minnesota Department of Health well program (651-201-4600) or a certified lab for help.";

export async function POST(request: Request): Promise<Response> {
  return handleJson(request, async (body) => {
    const parsed = ExplainRequest.safeParse(body);
    if (!parsed.success) {
      throw new UserFacingError("The app sent results the server didn't understand.");
    }
    const input = parsed.data;

    const raw = await askForJson({
      system: SYSTEM,
      content: [{ type: "text", text: JSON.stringify(input, null, 2) }],
      schema: responseSchema,
      effort: "low",
      maxTokens: 8000,
    });
    const output = ExplainResponse.safeParse(raw);
    if (!output.success) {
      throw new UserFacingError("The AI sent back an answer ClearWell couldn't read. Please try again.", 502);
    }

    // Keep only results the app asked about, and guarantee every red result points to MDH or a lab.
    const statusById = new Map(input.results.map((r) => [r.contaminant, r.status]));
    const explanations = output.data.explanations
      .filter((e) => statusById.has(e.contaminant))
      .map((e) => {
        const mentionsHelp = /MDH|Minnesota Department of Health|certified lab/i.test(e.nextStep);
        const nextStep = statusById.get(e.contaminant) === "red" && !mentionsHelp ? `${e.nextStep} ${MDH_HELP}` : e.nextStep;
        return { ...e, nextStep };
      });

    return { explanations };
  });
}
