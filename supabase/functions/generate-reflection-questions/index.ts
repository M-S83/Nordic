// =============================================================================
// generate-reflection-questions
// After a reflection is saved, generate a small set of OPTIONAL follow-up
// questions that help the user reflect more deeply. Every question is skippable.
//
// Principle: "Mirror, not verdict." Questions are open and curious, never
// leading or judgemental.
//
// Body: { reflection_id: string, max_questions?: number }
// =============================================================================
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { callClaude, serviceClient, userClient } from "../_shared/clients.ts";

interface GeneratedQuestion {
  question_text: string;
  question_type: "multiple_choice" | "voice" | "text" | "rating";
  options: { value: string; label: string }[];
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { reflection_id, max_questions = 3 } = await req.json();
    if (!reflection_id) return jsonResponse({ error: "Missing reflection_id" }, 400);

    const supa = userClient(req);
    const { data: ref, error } = await supa
      .from("reflections").select("*").eq("id", reflection_id).single();
    if (error || !ref) return jsonResponse({ error: "Not found or not permitted" }, 403);

    const context = JSON.stringify({
      summary: ref.summary,
      what_went_well: ref.what_went_well,
      what_did_not_work: ref.what_did_not_work,
      action_points: ref.action_points,
    });

    const raw = await callClaude({
      system:
        "You help coaches and players reflect. Principle: MIRROR, NOT VERDICT. " +
        "Generate open, curious, non-judgemental follow-up questions based on the " +
        `reflection. Return ONLY a JSON array (max ${max_questions}) of objects with ` +
        'keys: question_text (string), question_type ("multiple_choice"|"voice"|' +
        '"text"|"rating"), options (array of {value,label}; [] unless multiple_choice).',
      prompt: context,
    });

    const questions = safeParse(raw).slice(0, max_questions);

    const admin = serviceClient();
    const rows = questions.map((q) => ({
      reflection_id,
      question_text: q.question_text,
      question_type: q.question_type ?? "text",
      options: q.options ?? [],
    }));
    const { data: inserted, error: insErr } = rows.length
      ? await admin.from("followup_questions").insert(rows).select()
      : { data: [], error: null };
    if (insErr) return jsonResponse({ error: insErr.message }, 500);

    return jsonResponse({ ok: true, questions: inserted });
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
});

function safeParse(raw: string): GeneratedQuestion[] {
  try {
    const m = raw.match(/\[[\s\S]*\]/);
    return m ? JSON.parse(m[0]) : [];
  } catch {
    return [];
  }
}
