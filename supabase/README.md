# Nordic — Coaching & Player Reflection Backend

Supabase backend for a football **coaching and player reflection** app focused
on analysing your **own team** and recording notes. User roles — **Coach**,
**Player**, **Coach developer** (plus `admin`) — share one event-centric data
model.

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
    generate-reflection-questions/ Reflection → optional context-nudge questions
    enrich-reflection/             Answers → reflection.enriched_summary
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

`clubs → teams → players` is the org hierarchy, with `competitions` (leagues /
cups) alongside. **Everything else hangs off an `event`** (training session,
match, coach observation or player reflection). An event owns its `team_sheets`
(+ `team_sheet_players`), `observations`, `event_attendance`, `reflections` and
`reports`; match events also own `match_details` and `match_stats`. Reflections
own `followup_questions`, which own `followup_answers`. `insights` aggregate
patterns over time and can be scoped to a user, club, team or player.

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

### Coach-developer Mode
A coach developer supports and observes coaches. They create `coach_observation`
events, record `coach_developer` reflections, and their insights are typed
`coach_development`. As club staff they can read their club’s events, teams and
players (RLS helper `is_club_staff`); anything they author stays theirs.

### Capturing notes (any time)
`observations` are atomic notes captured across the whole timeline. A
`capture_phase` marks when: `pre_event` (planning thoughts), `live` (during a
session/match), `post_event` (a quick thought right after), or `ad_hoc` (a
thought at any time, with `event_id` null). Each note stores `timestamp_seconds`
+ `match_minute`, an `input_type` (`voice_note` / `text_note` / `tag_only`), a
rich `observation_type`, `tags[]`, `sentiment` and the tactical `phase_of_play`.
Ad-hoc notes carry no event but can still be scoped to a `team_id` and/or
`player_id`. Voice notes go to the `audio-recordings` bucket and are transcribed
by `transcribe-audio`; raw notes are tidied by `clean-observation` (mirror, not
verdict). The deeper structured post-event write-up lives in `reflections`.

### Team sheet upload (optional)
Selecting from the squad list is the primary path. Snapping a team sheet is an
optional alternative — handy for bulk-adding players or working from a paper
sheet. A `team_sheets` row points at a file in the `uploads` bucket;
`process-team-sheet` extracts the roster into `team_sheet_players`, linking shirt
numbers to canonical `players`. Either way, `clean-observation` auto-attributes a
note like “Number 8 scans before receiving” to the right player by shirt number.

### Squad selection, attendance & match record
For a match, the coach picks the matchday squad straight from the team's player
list: `event_attendance` holds one row per player with a `status` (`present` /
`absent` / `injured` / `unavailable`) and, for matches, a `selection`
(`starter` / `substitute`). For training the same table just records who turned
up (`selection` stays null).
Matches also record results — `match_details` stores `home_away`, `goals_for` /
`goals_against` (with a **generated** `result` of win/draw/loss), `man_of_the_match`
and notes; `match_stats` holds per-player `goals`, `assists`, `yellow_cards`,
`red_cards`, `clean_sheet` and `minutes_played` (so "who scored / assisted" falls
straight out). A match's `event.competition_id` links it to a `competitions` row
— a league or cup with an **editable** name (e.g. rename "Cup 1" to "County Cup").

### Post-event reflection
`reflections` hold the `raw_transcript`, a `summary`, and JSONB lists
(`what_went_well`, `what_did_not_work`, `learning_evidence`, `action_points`,
`suggested_next_focus`). `generate-reflection-questions` reads the reflection and,
**only where it's brief or broad**, offers a light nudge to add a bit of context
(a concrete example, which player/moment, what a vague word meant) — if the
reflection is already detailed it asks nothing. Questions are optional and
always-skippable (`followup_questions`); answers land in `followup_answers`.
Any answers the coach does add are then folded back into the reflection by
`enrich-reflection`, which writes an `enriched_summary` (the original `summary`
is left untouched, and it no-ops if everything was skipped). Reflections and
notes can be captured by **text or by voice** — voice recordings go to
`audio-recordings` and `transcribe-audio` fills in the transcript / answer text.
`generate-report` prefers the `enriched_summary` when one exists.

### Report generation
`generate-report` aggregates an event’s observations + reflection (+ squad
roster) into a `reports` row with `content_json` and `content_markdown`; an
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
- **Users** see events they created; **club staff** additionally see their club's events.
- **Players** see only their own reflections.
- **Reports** are restricted to creator, club admins, or `report_access` grants.
- **Storage** objects are namespaced under `<auth.uid()>/…`; policies allow each
  user to manage only their own folder in every bucket.
