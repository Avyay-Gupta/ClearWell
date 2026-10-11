import { z } from "zod";
import { askForJson, handleJson, UserFacingError } from "../lib/claude.js";

// Published U.S. EPA WaterSense figures (https://www.epa.gov/watersense/statistics-and-facts).
// The AI never writes savings numbers itself: it can only point to one of these.
const REFERENCE_SAVINGS = {
  leaks: { gallonsPerYear: 9_400, basis: "EPA WaterSense: the average family can waste 9,400 gallons a year from household leaks." },
  toilets: { gallonsPerYear: 13_000, basis: "EPA WaterSense: replacing old toilets with WaterSense models saves the average family about 13,000 gallons a year." },
  showerheads: { gallonsPerYear: 2_700, basis: "EPA WaterSense: WaterSense showerheads save the average family more than 2,700 gallons a year." },
  irrigation: { gallonsPerYear: 15_000, basis: "EPA WaterSense: a WaterSense irrigation controller can save an average home up to 15,000 gallons a year. Many homes save less." },
  dishwasher: { gallonsPerYear: 320, basis: "EPA WaterSense: running the dishwasher only when full saves the average family nearly 320 gallons a year." },
  tap: { gallonsPerYear: 5_700, basis: "EPA WaterSense: turning off the tap while brushing and shaving saves nearly 5,700 gallons a year per person." },
} as const;
type ReferenceId = keyof typeof REFERENCE_SAVINGS;
const REFERENCE_IDS = Object.keys(REFERENCE_SAVINGS) as ReferenceId[];

const ConserveRequest = z.object({
  season: z.enum(["spring", "summer", "fall", "winter"]),
  county: z.string().max(60),
  waterSource: z.string().max(60),
  people: z.number().int().min(1).max(20),
  outdoorWatering: z.string().max(80),
  olderToilets: z.string().max(20),
  olderShowerheads: z.string().max(20),
  latestGallonsPerDay: z.number().int().min(0).max(100_000).nullish(),
  typicalGallonsPerDay: z.number().int().min(0).max(100_000).nullish(),
  comparisons: z
    .array(
      z.object({
        period: z.string().max(10),
        currentGallonsPerDay: z.number().int(),
        previousGallonsPerDay: z.number().int(),
        percentChange: z.number().int(),
      }),
    )
    .max(3),
  possibleLeak: z.boolean(),
  goalPercent: z.number().int().min(1).max(90).nullish(),
  countyInDrought: z.boolean(),
});

const responseSchema = {
  type: "object",
  properties: {
    recommendations: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          detail: { type: "string" },
          savingsReference: { type: "string", enum: [...REFERENCE_IDS, "none"] },
        },
        required: ["title", "detail", "savingsReference"],
        additionalProperties: false,
      },
    },
  },
  required: ["recommendations"],
  additionalProperties: false,
};

const ConserveResponse = z.object({
  recommendations: z.array(
    z.object({
      title: z.string(),
      detail: z.string(),
      savingsReference: z.enum(["none", ...REFERENCE_IDS]),
    }),
  ),
});

const SYSTEM = `You suggest practical ways for one Minnesota household to use less water, for ClearWell, an app for private-well and city-water households.

You get a summary of the household: season, county, water source, number of people, habits, and usage worked out from their own meter readings or bills. Base every suggestion on those facts.

Write 3 to 5 suggestions, most useful first:
- title: at most 8 words.
- detail: 1 or 2 short sentences a busy parent can act on, at about a 6th-grade reading level.
- savingsReference: the id of the published savings fact that matches the suggestion, or "none". Never write savings numbers yourself; ClearWell adds the published figure for the id you choose and labels it as an estimate.

Reference facts (EPA WaterSense):
${REFERENCE_IDS.map((id) => `- ${id}: ${REFERENCE_SAVINGS[id].basis}`).join("\n")}

Guidance:
- If possibleLeak is true, the first suggestion is checking for a leak (turn everything off and watch the meter for an hour), with savingsReference "leaks".
- Match the season: lawn and garden watering advice only in spring and summer; in fall, suggest winterizing outdoor faucets and sprinklers; in winter, focus indoors.
- If countyInDrought is true, mention the drought where it fits.
- Don't suggest anything the household already said doesn't apply (for example, toilet replacement when olderToilets is "No").
- Don't claim how much this household will save or has saved; don't mention costs or brands.`;

export async function POST(request: Request): Promise<Response> {
  return handleJson(request, async (body) => {
    const parsed = ConserveRequest.safeParse(body);
    if (!parsed.success) {
      throw new UserFacingError("The app sent a usage summary the server didn't understand.");
    }

    const raw = await askForJson({
      system: SYSTEM,
      content: [{ type: "text", text: JSON.stringify(parsed.data, null, 2) }],
      schema: responseSchema,
      effort: "low",
      maxTokens: 8000,
    });
    const output = ConserveResponse.safeParse(raw);
    if (!output.success) {
      throw new UserFacingError("The AI sent back an answer ClearWell couldn't read. Please try again.", 502);
    }

    // Savings come only from the published table — never from the AI's own numbers.
    const recommendations = output.data.recommendations.slice(0, 5).map((r) => {
      const ref = r.savingsReference === "none" ? undefined : REFERENCE_SAVINGS[r.savingsReference as ReferenceId];
      const perPerson = r.savingsReference === "tap";
      return {
        title: r.title,
        detail: r.detail,
        estimatedGallonsPerYear: ref ? ref.gallonsPerYear * (perPerson ? parsed.data.people : 1) : null,
        estimateBasis: ref
          ? `${ref.basis}${perPerson ? ` Shown for ${parsed.data.people} people.` : ""} Your savings depend on your home and habits.`
          : null,
      };
    });
    return { recommendations };
  });
}
