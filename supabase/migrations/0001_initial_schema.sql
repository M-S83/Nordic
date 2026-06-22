-- =============================================================================
-- 0001_initial_schema.sql
-- Football Coaching / Player Reflection / Scouting Intelligence app
-- Core schema: enums + tables.
--
-- Product principle: "Mirror, not verdict."
-- The data model is built to help users reflect, organise and surface patterns.
-- =============================================================================

-- Useful extensions ----------------------------------------------------------
create extension if not exists "pgcrypto"; -- gen_random_uuid()

-- =============================================================================
-- ENUMS
-- =============================================================================

create type user_role as enum (
  'coach',
  'player',
  'scout',
  'coach_developer',
  'admin'
);

create type event_type as enum (
  'training_session',
  'match',
  'player_scouting',
  'team_scouting',
  'coach_observation',
  'player_reflection'
);

create type event_status as enum (
  'draft',
  'live',
  'completed'
);

create type team_sheet_source as enum (
  'image',
  'pdf',
  'manual'
);

-- Generic async processing status (team sheet OCR, transcription, etc.)
create type processing_status as enum (
  'pending',
  'processing',
  'completed',
  'failed'
);

-- How a live observation was captured
create type observation_input_type as enum (
  'voice_note',
  'text_note',
  'tag_only'
);

-- What the observation is about
create type observation_type as enum (
  'player_observation',
  'team_observation',
  'tactical_pattern',
  'technical_action',
  'physical_action',
  'psychological_behavioural',
  'set_piece',
  'moment_of_quality',
  'concern_risk',
  'follow_up_later'
);

create type subject_type as enum (
  'player',
  'team',
  'coach',
  'unit',
  'unknown'
);

create type sentiment as enum (
  'positive',
  'concern',
  'neutral'
);

create type reflection_type as enum (
  'coach',
  'player',
  'scout',
  'coach_developer'
);

create type question_type as enum (
  'multiple_choice',
  'voice',
  'text',
  'rating'
);

create type report_type as enum (
  'coach_reflection',
  'player_report',
  'team_scout_report',
  'player_scout_report',
  'coach_observation'
);

create type insight_type as enum (
  'player_pattern',
  'team_pattern',
  'opposition_pattern',
  'coach_development',
  'recurring_theme'
);

-- =============================================================================
-- CORE ORGANISATION TABLES
-- =============================================================================

-- Clubs / organisations -------------------------------------------------------
create table public.clubs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

-- Profiles: 1:1 with Supabase auth users -------------------------------------
-- A user can be a coach, player, scout, coach_developer or admin and belongs
-- optionally to a single club.
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text,
  full_name   text,
  role        user_role not null default 'coach',
  club_id     uuid references public.clubs (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index profiles_club_id_idx on public.profiles (club_id);

-- Teams: belong to a club -----------------------------------------------------
create table public.teams (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs (id) on delete cascade,
  name        text not null,
  age_group   text,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

create index teams_club_id_idx on public.teams (club_id);

-- Players: belong to a team (nullable so scouting-created players are allowed)
create table public.players (
  id            uuid primary key default gen_random_uuid(),
  team_id       uuid references public.teams (id) on delete set null,
  first_name    text,
  last_name     text,
  display_name  text,
  shirt_number  int,
  position      text,
  notes         text,
  created_by    uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now()
);

create index players_team_id_idx on public.players (team_id);

-- =============================================================================
-- EVENTS  (everything starts with an event)
-- =============================================================================

create table public.events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  club_id     uuid references public.clubs (id) on delete set null,
  team_id     uuid references public.teams (id) on delete set null,
  event_type  event_type not null,
  title       text not null,
  event_date  date,
  opposition  text,
  venue       text,
  focus_area  text,
  status      event_status not null default 'draft',
  started_at  timestamptz,
  ended_at    timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index events_user_id_idx on public.events (user_id);
create index events_club_id_idx on public.events (club_id);
create index events_team_id_idx on public.events (team_id);

-- =============================================================================
-- TEAM SHEET UPLOADS
-- =============================================================================

create table public.team_sheets (
  id                 uuid primary key default gen_random_uuid(),
  event_id           uuid not null references public.events (id) on delete cascade,
  uploaded_by        uuid references auth.users (id) on delete set null,
  source             team_sheet_source not null default 'image',
  file_path          text,                 -- path within the `uploads` storage bucket
  extracted_text     text,
  processing_status  processing_status not null default 'pending',
  created_at         timestamptz not null default now()
);

create index team_sheets_event_id_idx on public.team_sheets (event_id);

-- Players extracted from an uploaded team sheet -------------------------------
-- Links shirt numbers / names to canonical players so live notes like
-- "Number 8 scans before receiving" can be attributed automatically.
create table public.team_sheet_players (
  id               uuid primary key default gen_random_uuid(),
  team_sheet_id    uuid not null references public.team_sheets (id) on delete cascade,
  player_id        uuid references public.players (id) on delete set null,
  shirt_number     int,
  player_name      text,
  position         text,
  team_name        text,
  is_starter       boolean not null default true,
  confidence_score numeric(4,3),           -- 0.000 - 1.000
  created_at       timestamptz not null default now()
);

create index team_sheet_players_sheet_id_idx on public.team_sheet_players (team_sheet_id);
create index team_sheet_players_player_id_idx on public.team_sheet_players (player_id);

-- =============================================================================
-- LIVE OBSERVATIONS
-- =============================================================================

create table public.observations (
  id                uuid primary key default gen_random_uuid(),
  event_id          uuid not null references public.events (id) on delete cascade,
  user_id           uuid not null references auth.users (id) on delete cascade,
  timestamp_seconds int,                   -- offset within the recording/session
  match_minute      int,
  input_type        observation_input_type not null default 'text_note',
  observation_type  observation_type not null default 'player_observation',
  subject_type      subject_type not null default 'unknown',
  player_id         uuid references public.players (id) on delete set null,
  shirt_number      int,
  raw_note          text,                  -- original transcription / text
  cleaned_note      text,                  -- AI-cleaned (mirror, not verdict)
  tags              text[] not null default '{}',
  sentiment         sentiment not null default 'neutral',
  phase_of_play     text,
  confidence_score  numeric(4,3),
  audio_path        text,                  -- path within `audio-recordings` bucket
  created_at        timestamptz not null default now()
);

create index observations_event_id_idx on public.observations (event_id);
create index observations_user_id_idx on public.observations (user_id);
create index observations_player_id_idx on public.observations (player_id);
create index observations_tags_idx on public.observations using gin (tags);

-- =============================================================================
-- POST-EVENT REFLECTIONS
-- =============================================================================

create table public.reflections (
  id                   uuid primary key default gen_random_uuid(),
  event_id             uuid not null references public.events (id) on delete cascade,
  user_id              uuid not null references auth.users (id) on delete cascade,
  reflection_type      reflection_type not null,
  raw_transcript       text,
  summary              text,
  -- Structured lists kept as JSONB arrays of strings/objects.
  what_went_well       jsonb not null default '[]'::jsonb,
  what_did_not_work    jsonb not null default '[]'::jsonb,
  learning_evidence    jsonb not null default '[]'::jsonb,
  action_points        jsonb not null default '[]'::jsonb,
  suggested_next_focus  jsonb not null default '[]'::jsonb,
  audio_path           text,               -- path within `audio-recordings` bucket
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index reflections_event_id_idx on public.reflections (event_id);
create index reflections_user_id_idx on public.reflections (user_id);

-- =============================================================================
-- INTERACTIVE FOLLOW-UP QUESTIONS  (always skippable)
-- =============================================================================

create table public.followup_questions (
  id             uuid primary key default gen_random_uuid(),
  reflection_id  uuid not null references public.reflections (id) on delete cascade,
  question_text  text not null,
  question_type  question_type not null default 'text',
  options        jsonb not null default '[]'::jsonb,  -- for multiple_choice / rating
  skipped        boolean not null default false,
  created_at     timestamptz not null default now()
);

create index followup_questions_reflection_id_idx on public.followup_questions (reflection_id);

create table public.followup_answers (
  id               uuid primary key default gen_random_uuid(),
  question_id      uuid not null references public.followup_questions (id) on delete cascade,
  answer_text      text,
  selected_option  text,
  audio_path       text,                   -- path within `audio-recordings` bucket
  created_at       timestamptz not null default now()
);

create index followup_answers_question_id_idx on public.followup_answers (question_id);

-- =============================================================================
-- GENERATED REPORTS
-- =============================================================================

create table public.reports (
  id                uuid primary key default gen_random_uuid(),
  event_id          uuid not null references public.events (id) on delete cascade,
  created_by        uuid references auth.users (id) on delete set null,
  report_type       report_type not null,
  title             text not null,
  content_json      jsonb not null default '{}'::jsonb,
  content_markdown  text,
  pdf_path          text,                  -- path within `reports` bucket
  created_at        timestamptz not null default now()
);

create index reports_event_id_idx on public.reports (event_id);

-- Explicit grants of access to a report (beyond owner / club admin) -----------
create table public.report_access (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.reports (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  granted_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (report_id, user_id)
);

create index report_access_user_id_idx on public.report_access (user_id);

-- =============================================================================
-- LONG-TERM INSIGHTS  (pattern intelligence)
-- =============================================================================

create table public.insights (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  club_id          uuid references public.clubs (id) on delete set null,
  team_id          uuid references public.teams (id) on delete set null,
  player_id        uuid references public.players (id) on delete set null,
  insight_type     insight_type not null,
  title            text not null,
  description      text,
  evidence_count   int not null default 1,
  confidence_score numeric(4,3),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index insights_user_id_idx on public.insights (user_id);
create index insights_player_id_idx on public.insights (player_id);
create index insights_team_id_idx on public.insights (team_id);

-- =============================================================================
-- updated_at trigger helper
-- =============================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger events_set_updated_at
  before update on public.events
  for each row execute function public.set_updated_at();

create trigger reflections_set_updated_at
  before update on public.reflections
  for each row execute function public.set_updated_at();

create trigger insights_set_updated_at
  before update on public.insights
  for each row execute function public.set_updated_at();

-- =============================================================================
-- Auto-create a profile row when a new auth user signs up
-- =============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce((new.raw_user_meta_data ->> 'role')::user_role, 'coach')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
