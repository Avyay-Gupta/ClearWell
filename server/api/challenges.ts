// Community conservation challenges.
// GET  /api/challenges  → active challenges with community totals
// POST /api/challenges  → { action: "join" | "progress" | "leave", challengeId, participantId, ... }
//
// Privacy: households are known only by a random ID. Totals are hidden until
// MINIMUM_PARTICIPANTS households join, so no single household's numbers show.
// Measured savings (from meters) and estimated savings (from actions) stay separate.
import { z } from "zod";
import { checkToken, handleJson, UserFacingError } from "../lib/claude.js";
import { getStore } from "../lib/store.js";

const MINIMUM_PARTICIPANTS = 5;

interface ChallengeAction {
  id: string;
  title: string;
  estimatedGallons: number | null;
}

interface ChallengeDefinition {
  id: string;
  title: string;
  summary: string;
  whyItMatters: string;
  startDate: string;
  endDate: string;
  measuredByMeter: boolean;
  actions: ChallengeAction[];
}

interface ParticipantRecord {
  measuredGallonsSaved: number | null;
  completedActions: string[];
  updatedAt: string;
}

const day = (date: Date) => date.toISOString().slice(0, 10);

/** Challenges running on `now`. Dates use the server's calendar (UTC). */
export function activeChallenges(now = new Date()): ChallengeDefinition[] {
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth(); // 0 = January
  const monthName = now.toLocaleString("en-US", { month: "long", timeZone: "UTC" });
  const list: ChallengeDefinition[] = [
    {
      id: `use-less-${year}-${String(month + 1).padStart(2, "0")}`,
      title: `Use 10% less water in ${monthName}`,
      summary: "Cut your household's water use by 10% this month compared with last month.",
      whyItMatters:
        "Every home in the area draws on the same groundwater, lakes and rivers. Small cuts across many homes ease the strain during dry spells and keep more water in our aquifers.",
      startDate: day(new Date(Date.UTC(year, month, 1))),
      endDate: day(new Date(Date.UTC(year, month + 1, 0))),
      measuredByMeter: true,
      actions: [
        { id: "leak-check", title: "Did the one-hour meter leak check", estimatedGallons: null },
        // EPA WaterSense: leaks waste 9,400 gallons a year for the average family → about 783 a month.
        { id: "fixed-leak", title: "Found and fixed a leak", estimatedGallons: 783 },
        // EPA WaterSense: full dishwasher loads save nearly 320 gallons a year → about 27 a month.
        { id: "full-loads", title: "Ran only full dishwasher loads", estimatedGallons: 27 },
      ],
    },
  ];

  if (month >= 4 && month <= 8) {
    list.push({
      id: `smart-watering-${year}`,
      title: "Smarter outdoor watering",
      summary: "Water lawns and gardens less often, more deeply, and in the morning.",
      whyItMatters:
        "Lawn watering is often a household's biggest summer water use. Watering in the heat of the day loses much of it to evaporation, and over-watering washes fertilizer toward lakes and streams.",
      startDate: `${year}-05-01`,
      endDate: `${year}-09-30`,
      measuredByMeter: true,
      actions: [
        { id: "once-a-week", title: "Watered the lawn once a week or less", estimatedGallons: null },
        { id: "mornings", title: "Watered only in the morning", estimatedGallons: null },
        { id: "skip-rain", title: "Skipped watering when rain was forecast", estimatedGallons: null },
      ],
    });
  }

  if (month >= 9 && month <= 10) {
    list.push({
      id: `winterize-${year}`,
      title: "Winterize outdoor water",
      summary: "Get outdoor faucets, hoses and sprinklers ready before the hard freeze.",
      whyItMatters:
        "Frozen pipes and faucets can crack and leak for weeks before anyone notices — wasting water and sometimes damaging homes and wells.",
      startDate: `${year}-10-01`,
      endDate: `${year}-11-30`,
      measuredByMeter: false,
      actions: [
        { id: "hoses", title: "Disconnected and drained garden hoses", estimatedGallons: null },
        { id: "faucets", title: "Shut off outdoor faucets from inside", estimatedGallons: null },
        { id: "sprinklers", title: "Had the sprinkler system blown out", estimatedGallons: null },
      ],
    });
  }
  return list;
}

async function withTotals(challenges: ChallengeDefinition[]) {
  const store = getStore();
  return Promise.all(
    challenges.map(async (challenge) => {
      const records = Object.values(await store.hgetall(`challenge:${challenge.id}`)).map(
        (value) => JSON.parse(value) as ParticipantRecord,
      );
      const participants = records.length;
      if (participants < MINIMUM_PARTICIPANTS) return { ...challenge, participants, totals: null };

      const estimateFor = new Map(challenge.actions.map((a) => [a.id, a.estimatedGallons ?? 0]));
      const actionsCompleted: Record<string, number> = {};
      let estimatedGallonsSaved = 0;
      for (const record of records) {
        for (const id of record.completedActions) {
          actionsCompleted[id] = (actionsCompleted[id] ?? 0) + 1;
          estimatedGallonsSaved += estimateFor.get(id) ?? 0;
        }
      }
      const measured = records.filter((r) => r.measuredGallonsSaved !== null);
      return {
        ...challenge,
        participants,
        totals: {
          measuredHouseholds: measured.length,
          measuredGallonsSaved: Math.round(measured.reduce((sum, r) => sum + (r.measuredGallonsSaved ?? 0), 0)),
          estimatedGallonsSaved: Math.round(estimatedGallonsSaved),
          actionsCompleted,
        },
      };
    }),
  );
}

async function list() {
  return { challenges: await withTotals(activeChallenges()), minimumParticipants: MINIMUM_PARTICIPANTS };
}

const Update = z.object({
  action: z.enum(["join", "progress", "leave"]),
  challengeId: z.string().max(80),
  participantId: z.string().uuid(),
  // A household saving more than this in one challenge is almost certainly a typo.
  measuredGallonsSaved: z.number().min(0).max(50_000).nullish(),
  completedActions: z.array(z.string().max(40)).max(20).default([]),
});

export async function GET(request: Request): Promise<Response> {
  const rejected = checkToken(request);
  if (rejected) return rejected;
  try {
    return Response.json(await list());
  } catch (error) {
    if (error instanceof UserFacingError) return Response.json({ error: error.message }, { status: error.status });
    console.error(error);
    return Response.json({ error: "Couldn't load community challenges." }, { status: 500 });
  }
}

export async function POST(request: Request): Promise<Response> {
  return handleJson(request, async (body) => {
    const parsed = Update.safeParse(body);
    if (!parsed.success) throw new UserFacingError("The app sent a challenge update the server didn't understand.");
    const update = parsed.data;

    const challenge = activeChallenges().find((c) => c.id === update.challengeId);
    if (!challenge) throw new UserFacingError("That challenge has ended.", 404);

    const store = getStore();
    const key = `challenge:${challenge.id}`;
    if (update.action === "leave") {
      await store.hdel(key, update.participantId);
    } else {
      const validActions = new Set(challenge.actions.map((a) => a.id));
      const record: ParticipantRecord = {
        measuredGallonsSaved: challenge.measuredByMeter ? (update.measuredGallonsSaved ?? null) : null,
        completedActions: [...new Set(update.completedActions)].filter((id) => validActions.has(id)),
        updatedAt: new Date().toISOString(),
      };
      await store.hset(key, update.participantId, JSON.stringify(record));
    }
    return list();
  });
}
