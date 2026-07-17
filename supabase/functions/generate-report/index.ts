// =============================================================================
// generate-report
// Aggregates an event's observations + reflection (+ team sheet roster)
// into a structured report (JSON + markdown) and stores it in `reports`.
//
// Principle: "Mirror, not verdict." The report organises and surfaces patterns;
// it does not grade or pass judgement on the user or players.
//
// Body: { event_id: string, report_type: ReportType, title?: string }
// =============================================================================
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { callClaude, serviceClient, userClient } from "../_shared/clients.ts";
import { voiceInstruction } from "../_shared/voice.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { event_id, report_type, title } = await req.json();
    if (!event_id || !report_type) {
      return jsonResponse({ error: "Missing event_id / report_type" }, 400);
    }

    // Caller must be able to access the event (RLS).
    const supa = userClient(req);
    const { data: event, error } = await supa
      .from("events").select("*").eq("id", event_id).single();
    if (error || !event) return jsonResponse({ error: "Not found or not permitted" }, 403);

    const [{ data: observations }, { data: reflections }, { data: sheetPlayers },
           { data: matchDetails }, { data: matchStats }] =
      await Promise.all([
        supa.from("observations").select("*").eq("event_id", event_id)
          .order("timestamp_seconds", { ascending: true }),
        supa.from("reflections").select("*").eq("event_id", event_id),
        supa.from("team_sheet_players")
          .select("*, team_sheets!inner(event_id)")
          .eq("team_sheets.event_id", event_id),
        supa.from("match_details").select("*").eq("event_id", event_id).maybeSingle(),
        supa.from("match_stats").select("*, players(display_name)").eq("event_id", event_id),
      ]);

    const payload = JSON.stringify({
      event: {
        type: event.event_type, title: event.title, date: event.event_date,
        opposition: event.opposition, focus_area: event.focus_area,
        purpose: event.purpose,
      },
      // What the coach hoped to see up front, and how the notes matched it.
      hoping_to_see: event.hoping_to_see ?? [],
      hoped_to_see_review: reflections?.[0]?.hoped_to_see_review ?? [],
      observations: (observations ?? []).map((o) => ({
        minute: o.match_minute, type: o.observation_type, subject: o.subject_type,
        note: o.cleaned_note ?? o.raw_note, tags: o.tags, sentiment: o.sentiment,
        phase: o.phase_of_play,
      })),
      reflection: reflections?.[0]
        ? {
          ...reflections[0],
          // Use the context-enriched summary if the coach added any.
          summary: reflections[0].enriched_summary ?? reflections[0].summary,
        }
        : null,
      // Included for match reports (null/empty for training).
      match_result: matchDetails ?? null,
      match_stats: matchStats ?? [],
      roster: sheetPlayers ?? [],
    });

    const admin = serviceClient();
    const voice = await voiceInstruction(admin, event.user_id);

    const raw = await callClaude({
      system:
        "You produce structured football coaching reflection reports. " +
        "Principle: MIRROR, NOT VERDICT — organise observations into themes and " +
        "patterns; do not grade or judge. Include a \"hoped_to_see\" section that " +
        "reflects each thing the coach hoped to see back against the notes " +
        "(what showed up, and what wasn't observed — plainly, no judgement). " +
        "For next-focus items, reflect back what the COACH noted for next time " +
        "(from their reflection) — do not invent your own recommendations. " +
        'Return ONLY JSON with keys: "headline" (string), "sections" (array of ' +
        '{heading, points: string[]}), "hoped_to_see" (array of {item, status, ' +
        'note}), "patterns" (string[]), "suggested_next_focus" (string[]).' +
        voice,
      prompt: `Report type: ${report_type}\n\nData:\n${payload}`,
      maxTokens: 2048,
    });

    const content_json = safeParse(raw);
    const content_markdown = toMarkdown(title ?? event.title, content_json);

    const { data: report, error: insErr } = await admin.from("reports").insert({
      event_id,
      created_by: event.user_id,
      report_type,
      title: title ?? `${event.title} — Report`,
      content_json,
      content_markdown,
    }).select().single();
    if (insErr) return jsonResponse({ error: insErr.message }, 500);

    return jsonResponse({ ok: true, report });
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
});

function safeParse(raw: string): Record<string, unknown> {
  try {
    const m = raw.match(/\{[\s\S]*\}/);
    return m ? JSON.parse(m[0]) : {};
  } catch {
    return {};
  }
}

function toMarkdown(title: string, c: any): string {
  const lines: string[] = [`# ${title}`];
  if (c.headline) lines.push(`\n_${c.headline}_`);
  for (const s of c.sections ?? []) {
    lines.push(`\n## ${s.heading}`);
    for (const p of s.points ?? []) lines.push(`- ${p}`);
  }
  if (c.hoped_to_see?.length) {
    const mark = (st: string) =>
      st === "showed_up" ? "✓" : st === "partly" ? "~" : "✗";
    lines.push(`\n## What you hoped to see`);
    for (const h of c.hoped_to_see) {
      lines.push(`- ${mark(h.status)} **${h.item}**${h.note ? ` — ${h.note}` : ""}`);
    }
  }
  if (c.patterns?.length) {
    lines.push(`\n## Patterns`);
    for (const p of c.patterns) lines.push(`- ${p}`);
  }
  if (c.suggested_next_focus?.length) {
    lines.push(`\n## Noted for next`);
    for (const p of c.suggested_next_focus) lines.push(`- ${p}`);
  }
  return lines.join("\n");
}
