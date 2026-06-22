// Shared client helpers for Edge Functions (Deno runtime).
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// A client scoped to the *calling user* — RLS applies. Use for reads/writes
// that should respect the caller's permissions.
export function userClient(req: Request): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: {
        headers: { Authorization: req.headers.get("Authorization") ?? "" },
      },
    },
  );
}

// A service-role client — bypasses RLS. Use only for trusted server-side
// writes (e.g. writing AI-generated results back) after you have verified the
// caller is allowed to touch the row.
export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

// Minimal Anthropic Messages API helper.
// Default model is the latest Claude Opus; override per call when needed.
export async function callClaude(opts: {
  system?: string;
  prompt: string;
  model?: string;
  maxTokens?: number;
}): Promise<string> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: opts.model ?? "claude-opus-4-8",
      max_tokens: opts.maxTokens ?? 1024,
      system: opts.system,
      messages: [{ role: "user", content: opts.prompt }],
    }),
  });

  if (!res.ok) {
    throw new Error(`Anthropic API error ${res.status}: ${await res.text()}`);
  }
  const data = await res.json();
  return data.content?.[0]?.text ?? "";
}
