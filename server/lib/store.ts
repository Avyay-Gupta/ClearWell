// Tiny storage for community challenge progress.
// • On Vercel: a Redis database from Upstash (add it from the Vercel Marketplace;
//   Vercel then sets KV_REST_API_URL and KV_REST_API_TOKEN for you).
// • On your Mac: a JSON file in server/.data (fine for testing).
import { promises as fs } from "node:fs";
import path from "node:path";
import { UserFacingError } from "./claude.js";

export interface HashStore {
  hset(key: string, field: string, value: string): Promise<void>;
  hdel(key: string, field: string): Promise<void>;
  hgetall(key: string): Promise<Record<string, string>>;
}

function upstashStore(url: string, token: string): HashStore {
  async function command(args: string[]): Promise<unknown> {
    const response = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });
    const json = (await response.json()) as { result?: unknown; error?: string };
    if (!response.ok || json.error) throw new Error(json.error ?? `Database error ${response.status}`);
    return json.result;
  }
  return {
    async hset(key, field, value) {
      await command(["HSET", key, field, value]);
    },
    async hdel(key, field) {
      await command(["HDEL", key, field]);
    },
    async hgetall(key) {
      const flat = ((await command(["HGETALL", key])) as string[] | null) ?? [];
      const record: Record<string, string> = {};
      for (let i = 0; i + 1 < flat.length; i += 2) record[flat[i]] = flat[i + 1];
      return record;
    },
  };
}

function fileStore(file: string): HashStore {
  async function read(): Promise<Record<string, Record<string, string>>> {
    try {
      return JSON.parse(await fs.readFile(file, "utf8"));
    } catch {
      return {};
    }
  }
  async function write(data: Record<string, Record<string, string>>) {
    await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, JSON.stringify(data, null, 2));
  }
  return {
    async hset(key, field, value) {
      const data = await read();
      data[key] = { ...(data[key] ?? {}), [field]: value };
      await write(data);
    },
    async hdel(key, field) {
      const data = await read();
      if (data[key]) delete data[key][field];
      await write(data);
    },
    async hgetall(key) {
      return (await read())[key] ?? {};
    },
  };
}

export function getStore(): HashStore {
  const url = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN;
  if (url && token) return upstashStore(url, token);
  if (process.env.VERCEL) {
    // Vercel's file system isn't shared or kept between requests, so totals would be wrong.
    throw new UserFacingError("Community challenges need a database on the ClearWell server. See server/README.md.", 503);
  }
  return fileStore(path.join(process.cwd(), ".data", "challenges.json"));
}
