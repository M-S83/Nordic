// =============================================================================
// update-insights
// Recomputes long-term pattern intelligence for a user by scanning their
// observations across events, and upserts rows into `insights`.
//
// Examples it produces:
//   "Oscar has been mentioned 8 times for finding space but not receiving."
//   "The last 6 sessions mention scanning under pressure."
//   "We've built through the number 6 in each of the last 6 matches."
//
// Body: { user_id?: string, player_id?: string, team_id?: string }
//   (defaults to the calling user)
// =============================================================================
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { serviceClient, userClient } from "../_shared/clients.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supa = userClient(req);
    const { data: auth } = await supa.auth.getUser();
    if (!auth?.user) return jsonResponse({ error: "Not authenticated" }, 401);

    const body = await req.json().catch(() => ({}));
    const userId: string = body.user_id ?? auth.user.id;
    if (userId !== auth.user.id) {
      return jsonResponse({ error: "Can only recompute your own insights" }, 403);
    }

    // Pull this user's observations (RLS-scoped).
    const { data: observations, error } = await supa
      .from("observations")
      .select("player_id, tags, event_id, events(team_id, club_id)")
      .eq("user_id", userId);
    if (error) return jsonResponse({ error: error.message }, 500);

    // --- Simple frequency-based pattern detection ----------------------------
    // Count tag occurrences per player; surface anything mentioned >= 3 times.
    const counts = new Map<string, { player_id: string | null; tag: string; n: number; team_id: string | null; club_id: string | null }>();
    for (const o of observations ?? []) {
      const ev = (o as any).events ?? {};
      for (const tag of o.tags ?? []) {
        const key = `${o.player_id ?? "team"}::${tag}`;
        const cur = counts.get(key) ?? {
          player_id: o.player_id, tag, n: 0,
          team_id: ev.team_id ?? null, club_id: ev.club_id ?? null,
        };
        cur.n += 1;
        counts.set(key, cur);
      }
    }

    const admin = serviceClient();
    const upserted: unknown[] = [];
    for (const { player_id, tag, n, team_id, club_id } of counts.values()) {
      if (n < 3) continue;
      const title = player_id
        ? `Player repeatedly tagged "${tag}"`
        : `Recurring theme: "${tag}"`;
      const description = player_id
        ? `This player has been mentioned ${n} times in relation to "${tag}".`
        : `"${tag}" has appeared in ${n} observations.`;

      const { data } = await admin.from("insights").insert({
        user_id: userId,
        club_id, team_id, player_id,
        insight_type: player_id ? "player_pattern" : "recurring_theme",
        title,
        description,
        evidence_count: n,
        confidence_score: Math.min(1, n / 10),
      }).select().single();
      if (data) upserted.push(data);
    }

    return jsonResponse({ ok: true, insights: upserted, scanned: observations?.length ?? 0 });
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
});
