// =============================================================================
// generate-reflection-questions
// After a reflection is saved, gently nudge the coach to add a little context
// ONLY where the reflection reads as brief or broad. If it's already detailed,
// ask nothing. Every question is optional and skippable.
//
// Principle: "Mirror, not verdict." Questions invite a bit more detail — a
// concrete example, what something looked like, which player/moment — never
// analysis, judgement, or advice on what they should have done.
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

    // Give the model the whole reflection so it can judge where detail is thin.
    const context = JSON.stringify({
      raw_transcript: ref.raw_transcript,
      summary: ref.summary,
      what_went_well: ref.what_went_well,
      what_did_not_work: ref.what_did_not_work,
      learning_evidence: ref.learning_evidence,
      action_points: ref.action_points,
      suggested_next_focus: ref.suggested_next_focus,
    });

    const raw = await callClaude({
      system:
        "You help a coach add a little context to their own reflection. " +
        "Principle: MIRROR, NOT VERDICT — never judge, coach, or suggest what " +
        "they should have done. Your ONLY job is to invite a bit more detail " +
        "where the reflection reads as brief or broad: a concrete example, what " +
        "something looked like, which player or moment, or what a vague word " +
        "(\"chaotic\", \"good\", \"better\") actually meant here.\n" +
        "Rules:\n" +
        "- If a point is already specific and detailed, do NOT ask about it.\n" +
        "- If the whole reflection is already rich, return an empty array [].\n" +
        `- Ask AT MOST ${max_questions} short, gentle, open questions, each tied ` +
        "to one thin or broad spot.\n" +
        "- Questions invite context, not analysis or self-criticism, and are " +
        "always skippable.\n" +
        'Return ONLY a JSON array of objects with keys: question_text (string), ' +
        'question_type ("text"|"voice"|"multiple_choice"|"rating"), options ' +
        "(array of {value,label}; [] unless multiple_choice).",
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
