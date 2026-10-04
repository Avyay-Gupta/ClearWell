import { z } from "zod";
import { askForJson, CONTAMINANTS, handleJson, UserFacingError } from "../lib/claude.js";

// About 6 MB of base64 — far more than a resized phone photo needs.
const MAX_IMAGE_BASE64 = 6_000_000;

const ScanRequest = z.object({
  imageBase64: z.string().min(100).max(MAX_IMAGE_BASE64),
  mediaType: z.enum(["image/jpeg", "image/png"]),
});

const nullable = (type: string) => ({ type: [type, "null"] });

const responseSchema = {
  type: "object",
  properties: {
    isLabReport: { type: "boolean" },
    testDate: { ...nullable("string"), description: "Sample collection date as YYYY-MM-DD, or null if not shown" },
    labName: nullable("string"),
    readings: {
      type: "array",
      items: {
        type: "object",
        properties: {
          contaminant: { type: "string", enum: [...CONTAMINANTS] },
          nameOnReport: { type: "string" },
          value: nullable("number"),
          unit: nullable("string"),
          present: nullable("boolean"),
          nitrateBasis: { type: "string", enum: ["as_nitrogen", "as_nitrate", "unknown"] },
          belowDetectionLimit: { type: "boolean" },
        },
        required: ["contaminant", "nameOnReport", "value", "unit", "present", "nitrateBasis", "belowDetectionLimit"],
        additionalProperties: false,
      },
    },
  },
  required: ["isLabReport", "testDate", "labName", "readings"],
  additionalProperties: false,
};

const ScanResponse = z.object({
  isLabReport: z.boolean(),
  testDate: z.string().nullable(),
  labName: z.string().nullable(),
  readings: z.array(
    z.object({
      contaminant: z.enum(CONTAMINANTS),
      nameOnReport: z.string(),
      value: z.number().nullable(),
      unit: z.string().nullable(),
      present: z.boolean().nullable(),
      nitrateBasis: z.enum(["as_nitrogen", "as_nitrate", "unknown"]),
      belowDetectionLimit: z.boolean(),
    }),
  ),
});

const SYSTEM = `You read photos of private well water laboratory reports for ClearWell. The family will check every number you extract before it is saved, so accuracy matters more than completeness.

Extract results only for these contaminants: nitrate, arsenic, lead, manganese, fluoride, and coliform bacteria. Skip anything else on the report, and skip contaminants that aren't on it.

- Copy each number exactly as printed. Do not round, estimate or convert units; put the unit exactly as printed in "unit".
- If a result is reported as not detected, ND, or below a detection or reporting limit (for example "<0.5"), set belowDetectionLimit to true and value to null.
- Nitrate: set nitrateBasis to "as_nitrogen" when labeled Nitrate-N, NO3-N, "nitrate as N" or "nitrate + nitrite as N"; "as_nitrate" when reported as the nitrate ion (NO3); otherwise "unknown". For the other contaminants use "unknown".
- Coliform bacteria: set present to true or false from words like Present/Absent, Positive/Negative or Detected/Not detected, and set value to null. If E. coli is present, coliform is present too.
- testDate is the sample collection date (or the report date if no collection date is shown) as YYYY-MM-DD.
- If you can't read a value clearly, leave that contaminant out rather than guess.

If the photo is not a water test report, set isLabReport to false and return no readings.`;

export async function POST(request: Request): Promise<Response> {
  return handleJson(request, async (body) => {
    const parsed = ScanRequest.safeParse(body);
    if (!parsed.success) {
      throw new UserFacingError("That photo couldn't be sent. Try a smaller photo.");
    }

    const raw = await askForJson({
      system: SYSTEM,
      content: [
        { type: "image", source: { type: "base64", media_type: parsed.data.mediaType, data: parsed.data.imageBase64 } },
        { type: "text", text: "Extract the water test results from this lab report." },
      ],
      schema: responseSchema,
      effort: "medium",
      maxTokens: 8000,
    });
    const output = ScanResponse.safeParse(raw);
    if (!output.success) {
      throw new UserFacingError("The AI sent back an answer ClearWell couldn't read. Please try again.", 502);
    }
    if (!output.data.isLabReport) {
      throw new UserFacingError("This photo doesn't look like a water test report. Try a clear photo of the results page.", 422);
    }

    const { testDate, labName, readings } = output.data;
    return { testDate, labName, readings };
  });
}
