# Nordic — Coaching, Reflection & Scouting Backend

Supabase backend for a football **coaching, player reflection and scouting
intelligence** app. Three user modes — **Coach**, **Player**, **Scout** (plus
`coach_developer` and `admin`) — share one event-centric data model.

> **Product principle: “Mirror, not verdict.”**
> The AI helps users reflect, organise and surface patterns. It never judges.
> This is enforced in the Edge Function prompts (`clean-observation`,
> `generate-reflection-questions`, `generate-report`).

## Layout

```
supabase/
  config.toml                      Local project + function config
  migrations/
    0001_initial_schema.sql        Enums + tables + triggers
    0002_rls_policies.sql          Row Level Security + helper functions
    0003_storage_buckets.sql       Buckets + storage.objects policies
  seed.sql                         Example data (club, team, players, events…)
  functions/
    _shared/                       CORS + Supabase/Claude client helpers
    transcribe-audio/              Audio → transcript
    process-team-sheet/            Team sheet → extracted players
    clean-observation/             Raw note → cleaned note + tags + sentiment
    generate-reflection-questions/ Reflection → optional follow-up questions
    generate-report/               Event → structured report (JSON + markdown)
    update-insights/               Observations → long-term pattern insights
types/database.ts                  TypeScript interfaces for the main objects
```

## Quick start

```bash
supabase start          # boots local Postgres, Auth, Storage, etc.
supabase db reset       # applies migrations/*.sql then seed.sql
supabase functions serve

# Generate fully-typed client types (optional, complements types/database.ts):
supabase gen types typescript --local > types/supabase.ts
```

Edge Function secrets:

```bash
supabase secrets set ANTHROPIC_API_KEY=...   # clean/questions/report/team-sheet
supabase secrets set OPENAI_API_KEY=...       # transcribe-audio (Whisper STT)
# SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected.
```

## Data model at a glance

`clubs → teams → players` is the org hierarchy. **Everything else hangs off an
`event`** (training session, match, scouting, observation or reflection). An
event owns its `team_sheets` (+ `team_sheet_players`), `observations`,
`reflections` and `reports`. Reflections own `followup_questions`, which own
`followup_answers`. `insights` aggregate patterns over time and can be scoped to
a user, club, team or player.

## How the backend supports each capability

### Coach Mode
A coach creates `events` of type `training_session` / `match` / `coach_observation`,
captures live `observations`, records a `coach` reflection, and generates a
`coach_reflection` report. Their `club_id` + `coach` role lets them read their
club’s teams, players and events (RLS helper `is_club_staff`).

### Player Mode
A player creates `player_reflection` events and `player` reflections about their
own performance, answers optional follow-up questions, and gets a `player_report`.
RLS keeps a player’s reflections private to them (`user_id = auth.uid()`) — they
only see what they author.

### Scout Mode
A scout creates `player_scouting` / `team_scouting` events, uploads opposition
`team_sheets`, captures `observations` against shirt numbers, and generates
`player_scout_report` / `team_scout_report`. Scouting events are private to the
creator (RLS: `events.user_id = auth.uid()`), so scouts only see events they made.

### Live capture
`observations` store `timestamp_seconds` + `match_minute`, an `input_type`
(`voice_note` / `text_note` / `tag_only`), a rich `observation_type`, `tags[]`,
`sentiment` and `phase_of_play`. Voice notes are uploaded to the
`audio-recordings` bucket and transcribed by `transcribe-audio`; raw notes are
tidied by `clean-observation` (mirror, not verdict).

### Team sheet upload
A `team_sheets` row points at a file in the `uploads` bucket. `process-team-sheet`
OCRs/extracts the roster into `team_sheet_players`, linking shirt numbers to
canonical `players`. `clean-observation` then auto-attributes a note like
“Number 8 scans before receiving” to the right player via the shirt number.

### Post-event reflection
`reflections` hold the `raw_transcript`, a `summary`, and JSONB lists
(`what_went_well`, `what_did_not_work`, `learning_evidence`, `action_points`,
`suggested_next_focus`). `generate-reflection-questions` adds optional,
always-skippable `followup_questions`; answers land in `followup_answers`.

### Report generation
`generate-report` aggregates an event’s observations + reflection (+ roster for
scouting) into a `reports` row with `content_json` and `content_markdown`; an
optional PDF can be rendered to the `reports` bucket. Reports are visible only to
the creator, club admins, or users explicitly listed in `report_access`.

### Long-term insight tracking
`update-insights` scans a user’s observations, counts recurring tags per player /
theme, and writes `insights` (with `evidence_count` + `confidence_score`). This
powers cross-event intelligence such as “scanning under pressure mentioned in the
last 6 sessions”.

## Security model (RLS)

All tables have RLS enabled. SECURITY DEFINER helpers avoid recursive lookups:
`current_club_id()`, `current_user_role()`, `is_club_staff()`, `is_club_admin()`,
`can_access_event()`, `can_access_report()`.

- Users read/write their **own** records.
- **Club admins** read their club’s records; **coaches / coach developers** read
  their club’s teams, players and events.
- **Scouts** see only scouting events they created.
- **Players** see only their own reflections.
- **Reports** are restricted to creator, club admins, or `report_access` grants.
- **Storage** objects are namespaced under `<auth.uid()>/…`; policies allow each
  user to manage only their own folder in every bucket.
