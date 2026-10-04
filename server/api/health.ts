// Lets the app's "Test connection" button check that the server is up and has a Claude API key.
export function GET(): Response {
  const aiConfigured = Boolean(process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN);
  return Response.json({ ok: true, aiConfigured });
}
