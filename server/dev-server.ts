// Runs the same API routes Vercel runs, on your Mac, for testing with the iPhone Simulator.
// Start it with:  npm run dev
import { createServer } from "node:http";
import { existsSync } from "node:fs";

if (existsSync(".env")) process.loadEnvFile(".env");

const { POST: explain } = await import("./api/explain.js");
const { POST: scan } = await import("./api/scan.js");
const { GET: health } = await import("./api/health.js");

const routes: Record<string, (request: Request) => Response | Promise<Response>> = {
  "POST /api/explain": explain,
  "POST /api/scan": scan,
  "GET /api/health": () => health(),
};

const port = Number(process.env.PORT ?? 8787);

createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", `http://localhost:${port}`);
  const route = routes[`${req.method} ${url.pathname}`];
  const started = Date.now();

  let response: Response;
  if (!route) {
    response = Response.json({ error: "Not found" }, { status: 404 });
  } else {
    const chunks: Buffer[] = [];
    for await (const chunk of req) chunks.push(chunk as Buffer);
    const headers = new Headers();
    for (const [key, value] of Object.entries(req.headers)) {
      if (typeof value === "string") headers.set(key, value);
    }
    const body = chunks.length ? Buffer.concat(chunks) : undefined;
    response = await route(new Request(url, { method: req.method, headers, body }));
  }

  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.end(Buffer.from(await response.arrayBuffer()));
  console.log(`${req.method} ${url.pathname} → ${response.status} (${Date.now() - started} ms)`);
}).listen(port, () => {
  console.log(`ClearWell server running at http://localhost:${port}`);
  if (!process.env.ANTHROPIC_API_KEY) {
    console.log("Note: ANTHROPIC_API_KEY is not set. Add it to server/.env (see .env.example).");
  }
});
