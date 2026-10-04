# ClearWell server

A tiny server that lets the ClearWell app use Claude **without putting the API key inside the app** (CAC build plan, Step 6).

| Route | What it does |
|---|---|
| `POST /api/explain` | Writes a 2–3 sentence plain-English explanation and a "what to do next" line for each result. It receives each result's color but can't change it, and every red result is guaranteed to point to MDH or a certified lab. |
| `POST /api/scan` | Reads a photo of a lab report and returns the contaminant names, values and units. The app converts the units and the user confirms every number. |
| `GET /api/health` | Used by the app's "Test connection" button. |

The prompts live in `api/explain.ts` and `api/scan.ts`. Claude calls go through `lib/claude.ts`.

## Run it on your Mac (for the iPhone Simulator)

1. Copy `.env.example` to `.env` and paste your Claude API key after `ANTHROPIC_API_KEY=`.
2. Start the server:
   ```bash
   npm install
   npm run dev
   ```
3. In the simulator the app already points to `http://localhost:8787`. Use **Settings → AI server → Test connection** to check it.

## Deploy it (for a real iPhone)

A real phone can't reach `localhost` on your Mac, so put the server on Vercel:

1. Create a free account at vercel.com and install the CLI: `npm i -g vercel`
2. From this `server` folder run `vercel` and follow the prompts.
3. In the Vercel dashboard, add `ANTHROPIC_API_KEY` (and optionally `CLEARWELL_APP_TOKEN`) under **Settings → Environment Variables**, then run `vercel --prod`.
4. In the app, open **Settings → AI server** and enter your Vercel address (for example `https://clearwell-server.vercel.app`) and the app token if you set one.

Never commit `.env` or put the API key in the app. `.gitignore` already excludes `.env`.
