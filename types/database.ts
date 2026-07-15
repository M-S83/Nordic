// =============================================================================
// types/database.ts
// TypeScript interfaces for the main backend objects.
// Mirrors the SQL schema in supabase/migrations/0001_initial_schema.sql.
//
// These are hand-written for clarity. For a fully generated, end-to-end typed
// client you can additionally run:
//   supabase gen types typescript --local > types/supabase.ts
// =============================================================================

// ---- Enums ------------------------------------------------------------------

export type UserRole =
  | "coach"
  | "player"
  | "coach_developer"
  | "admin";

export type EventType =
  | "training_session"
  | "match"
  | "coach_observation"
  | "player_reflection";

export type EventStatus = "draft" | "live" | "completed";

export type TeamSheetSource = "image" | "pdf" | "manual";

export type ProcessingStatus = "pending" | "processing" | "completed" | "failed";

export type ObservationInputType = "voice_note" | "text_note" | "tag_only";

export type ObservationType =
  | "player_observation"
  | "team_observation"
  | "tactical_pattern"
  | "technical_action"
  | "physical_action"
  | "psychological_behavioural"
  | "set_piece"
  | "moment_of_quality"
  | "concern_risk"
  | "follow_up_later";

export type SubjectType = "player" | "team" | "coach" | "unit" | "unknown";

export type Sentiment = "positive" | "concern" | "neutral";

// When a note was captured, relative to its event. 'ad_hoc' = a thought at any
// time, which may not belong to an event at all.
export type CapturePhase = "pre_event" | "live" | "post_event" | "ad_hoc";

export type ReflectionType = "coach" | "player" | "coach_developer";

export type QuestionType = "multiple_choice" | "voice" | "text" | "rating";

export type ReportType =
  | "coach_reflection"
  | "player_report"
  | "team_report"
  | "coach_observation";

export type InsightType =
  | "player_pattern"
  | "team_pattern"
  | "coach_development"
  | "recurring_theme";

// ---- Core tables ------------------------------------------------------------

export interface Club {
  id: string;
  name: string;
  created_by: string | null;
  created_at: string;
}

export interface Profile {
  id: string; // == auth.users.id
  email: string | null;
  full_name: string | null;
  role: UserRole;
  club_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface Team {
  id: string;
  club_id: string;
  name: string;
  age_group: string | null;
  created_by: string | null;
  created_at: string;
}

export interface Player {
  id: string;
  team_id: string | null;
  first_name: string | null;
  last_name: string | null;
  display_name: string | null;
  shirt_number: number | null;
  position: string | null;
  notes: string | null;
  created_by: string | null;
  created_at: string;
}

export interface Event {
  id: string;
  user_id: string;
  club_id: string | null;
  team_id: string | null;
  event_type: EventType;
  title: string;
  event_date: string | null; // ISO date
  opposition: string | null;
  venue: string | null;
  focus_area: string | null;
  status: EventStatus;
  started_at: string | null;
  ended_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface TeamSheet {
  id: string;
  event_id: string;
  uploaded_by: string | null;
  source: TeamSheetSource;
  file_path: string | null;
  extracted_text: string | null;
  processing_status: ProcessingStatus;
  created_at: string;
}

export interface TeamSheetPlayer {
  id: string;
  team_sheet_id: string;
  player_id: string | null;
  shirt_number: number | null;
  player_name: string | null;
  position: string | null;
  team_name: string | null;
  is_starter: boolean;
  confidence_score: number | null;
  created_at: string;
}

export interface Observation {
  id: string;
  event_id: string | null; // null for ad-hoc notes
  user_id: string;
  team_id: string | null; // for scoping ad-hoc notes
  capture_phase: CapturePhase;
  timestamp_seconds: number | null;
  match_minute: number | null;
  input_type: ObservationInputType;
  observation_type: ObservationType;
  subject_type: SubjectType;
  player_id: string | null;
  shirt_number: number | null;
  raw_note: string | null;
  cleaned_note: string | null;
  tags: string[];
  sentiment: Sentiment;
  phase_of_play: string | null;
  confidence_score: number | null;
  audio_path: string | null;
  created_at: string;
}

export interface Reflection {
  id: string;
  event_id: string;
  user_id: string;
  reflection_type: ReflectionType;
  raw_transcript: string | null;
  summary: string | null;
  what_went_well: string[];
  what_did_not_work: string[];
  learning_evidence: string[];
  action_points: string[];
  suggested_next_focus: string[];
  audio_path: string | null;
  created_at: string;
  updated_at: string;
}

export interface FollowupQuestion {
  id: string;
  reflection_id: string;
  question_text: string;
  question_type: QuestionType;
  options: QuestionOption[];
  skipped: boolean;
  created_at: string;
}

export interface QuestionOption {
  value: string;
  label: string;
}

export interface FollowupAnswer {
  id: string;
  question_id: string;
  answer_text: string | null;
  selected_option: string | null;
  audio_path: string | null;
  created_at: string;
}

export interface Report {
  id: string;
  event_id: string;
  created_by: string | null;
  report_type: ReportType;
  title: string;
  content_json: Record<string, unknown>;
  content_markdown: string | null;
  pdf_path: string | null;
  created_at: string;
}

export interface ReportAccess {
  id: string;
  report_id: string;
  user_id: string;
  granted_by: string | null;
  created_at: string;
}

export interface Insight {
  id: string;
  user_id: string;
  club_id: string | null;
  team_id: string | null;
  player_id: string | null;
  insight_type: InsightType;
  title: string;
  description: string | null;
  evidence_count: number;
  confidence_score: number | null;
  created_at: string;
  updated_at: string;
}

// ---- Storage bucket names ---------------------------------------------------

export const BUCKETS = {
  audio: "audio-recordings",
  uploads: "uploads",
  reports: "reports",
} as const;

export type BucketName = (typeof BUCKETS)[keyof typeof BUCKETS];
