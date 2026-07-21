// Frontend view of the backend rows we touch (subset of ../../types/database.ts).
export type EventType = "training_session" | "match" | "tournament" | "other";
export type TeamFormat = "3v3" | "5v5" | "6v6" | "7v7" | "9v9" | "11v11";
export type CapturePhase = "pre_event" | "live" | "post_event" | "ad_hoc";
export type Sentiment = "positive" | "concern" | "neutral";

export interface Club { id: string; name: string; created_at: string; }
export interface Team {
  id: string; club_id: string; name: string; age_group: string | null; format: TeamFormat;
}
export interface Player {
  id: string; team_id: string | null; display_name: string | null;
  first_name: string | null; last_name: string | null; shirt_number: number | null; position: string | null;
}
export interface EventRow {
  id: string; team_id: string | null; club_id: string | null; event_type: EventType;
  title: string; event_date: string | null; opposition: string | null;
  focus_area: string | null; purpose: string | null; hoping_to_see: string[];
  status: "draft" | "live" | "completed"; created_at: string;
}
export interface Observation {
  id: string; event_id: string | null; capture_phase: CapturePhase;
  input_type: "voice_note" | "text_note" | "tag_only";
  raw_note: string | null; cleaned_note: string | null; tags: string[];
  sentiment: Sentiment; audio_path: string | null; created_at: string;
}
export interface Reflection {
  id: string; event_id: string; reflection_type: "coach" | "player";
  raw_transcript: string | null; summary: string | null; enriched_summary: string | null;
  audio_path: string | null; created_at: string;
}
export interface FollowupQuestion {
  id: string; reflection_id: string; question_text: string; question_type: string; skipped: boolean;
}
export interface Report {
  id: string; event_id: string | null; report_type: string; title: string;
  content_markdown: string | null; created_at: string;
}

export const FORMATS: TeamFormat[] = ["3v3", "5v5", "6v6", "7v7", "9v9", "11v11"];
export const EVENT_TYPES: { value: EventType; label: string }[] = [
  { value: "training_session", label: "Training" },
  { value: "match", label: "Match" },
  { value: "tournament", label: "Tournament" },
  { value: "other", label: "Other" },
];
export const PHASES: { value: CapturePhase; label: string }[] = [
  { value: "pre_event", label: "Before" },
  { value: "live", label: "Live" },
  { value: "post_event", label: "After" },
  { value: "ad_hoc", label: "Thought" },
];
