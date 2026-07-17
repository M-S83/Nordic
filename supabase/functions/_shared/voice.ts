// Shared helper: fetch a coach's learned voice profile and turn it into a
// prompt instruction, so every AI reply is written in THEIR language and level.
// Returns "" when there's no profile yet (falls back to plain, neutral output).
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export async function voiceInstruction(
  admin: SupabaseClient,
  userId: string | null | undefined,
): Promise<string> {
  if (!userId) return "";
  const { data } = await admin
    .from("coach_voice_profiles")
    .select("style_summary, glossary, language_level")
    .eq("user_id", userId)
    .maybeSingle();

  if (!data?.style_summary) return "";
  const terms = Array.isArray(data.glossary) ? data.glossary.join(", ") : "";

  return (
    "\n\nVOICE — write so it reads as THIS coach's own words, not a textbook. " +
    `Their style: ${data.style_summary} ` +
    (data.language_level ? `Language level: ${data.language_level}. ` : "") +
    (terms ? `Terms they actually use: ${terms}. ` : "") +
    "Match their vocabulary and level exactly: don't upgrade plain, everyday " +
    "coaching language into jargon, and don't talk down to an experienced coach. " +
    "Mirror how they speak."
  );
}
