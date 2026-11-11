// A&T TaskDesk AI helper. Optional: only needed for the Assistant, Agents, meeting summaries and "Create doc with AI".
// Deploy in Supabase: Edge Functions -> Deploy a new function -> name it "ai" -> paste this file.
// Then add a secret named ANTHROPIC_API_KEY (Edge Functions -> Secrets). Optional secret AI_MODEL to choose the model.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    // only signed-in, active TaskDesk users may use the AI
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: role } = await supabase.rpc("my_role");
    if (!role) return json({ error: "not allowed" }, 401);

    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) return json({ error: "ANTHROPIC_API_KEY is not set" }, 500);
    const { messages } = await req.json();
    if (!Array.isArray(messages) || !messages.length) return json({ error: "no messages" }, 400);

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: Deno.env.get("AI_MODEL") ?? "claude-sonnet-5-5",
        max_tokens: 1500,
        messages: messages.slice(-20).map((m: { role: string; content: string }) => ({
          role: m.role === "assistant" ? "assistant" : "user",
          content: String(m.content ?? "").slice(0, 60000),
        })),
      }),
    });
    const out = await r.json();
    if (!r.ok) return json({ error: out?.error?.message ?? "AI request failed" }, 502);
    const text = (out.content ?? []).filter((b: { type: string }) => b.type === "text").map((b: { text: string }) => b.text).join("");
    return json({ text });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
