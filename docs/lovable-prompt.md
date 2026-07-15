# Lovable build prompt — Nordic frontend

Use this to build the **Nordic** frontend in [Lovable](https://lovable.dev)
against the existing Supabase backend (schema, RLS, Auth, Storage and Edge
Functions in `../supabase`).

## Before you paste the prompt

1. **Connect Lovable to your Supabase project first** (Lovable → Settings →
   Supabase integration). This makes Lovable build against the real schema
   instead of inventing its own.
2. **Do not let Lovable recreate the schema.** The migrations in
   `supabase/migrations/` are the source of truth. The prompt instructs it to
   read/write only through existing tables, policies and buckets.
3. **Keep field names aligned with the schema.** Point Lovable at
   `types/database.ts` (or paste it), and have it run
   `supabase gen types typescript` against the project so generated queries
   match the real columns.
4. **Build mode-by-mode** (Coach first). Lovable does better with one flow at a
   time than the whole app in one shot.

## The prompt

> Build a mobile-first web app called **Nordic** — a football **coaching and
> player reflection** tool for analysing your **own team** and recording notes.
> The Supabase backend (Postgres schema, RLS, Auth, Storage, Edge Functions)
> already exists and is connected — **do not create or modify tables, policies,
> or buckets; only read/write through the existing ones.**
>
> **Product principle: "Mirror, not verdict."** The app helps users reflect,
> organise and spot patterns — it never judges them. Keep all AI-facing copy
> neutral and curious, never evaluative.
>
> **Auth:** Supabase Auth (email magic link). On signup, a `profiles` row is
> auto-created with a `role`. After login, route the user by `profiles.role`:
> `coach`, `player`, `coach_developer`, `admin`. Let users pick their role +
> optional club during onboarding (write to `profiles`).
>
> **Roles / modes (driven by role):**
> - **Coach Mode** — manage clubs/teams/players; create `training_session` /
>   `match` / `coach_observation` events; capture live observations on their own
>   squad; write a coach reflection; generate a coach report.
> - **Player Mode** — create `player_reflection` events; record reflections
>   about own performance; answer optional follow-up questions; view own player
>   reports. A player only ever sees their own data.
> - **Coach-developer Mode** — create `coach_observation` events to observe and
>   support coaches; record `coach_developer` reflections; their insights track
>   coach development over time.
>
> **Core screens:**
> 1. **Home / dashboard** — recent events, quick "Start live capture", recent
>    insights.
> 2. **Event list + create event** — fields: title, type, date, opposition,
>    venue, focus area, team. Status `draft → live → completed`. For a match,
>    also pick a **competition** (a `competitions` row — league or cup, with
>    editable names, managed in team settings) and set **home / away / neutral**.
> 2b. **Attendance** — for any training or match, tick which players were there;
>    each becomes an `event_attendance` row with status `present` / `absent` /
>    `injured` / `unavailable`.
> 2c. **Match record** (match events) — enter the score (`goals_for` /
>    `goals_against`; `result` win/draw/loss is derived automatically), pick
>    **man of the match**, and per player log goals, assists, yellow/red cards,
>    clean sheet and minutes (`match_details` + `match_stats`).
> 3. **Note capture** (the centrepiece) — an `observation` is a note that can be
>    taken at any point, marked by `capture_phase`: `pre_event` (planning notes
>    before training/a match), `live` (rapid-fire during it), `post_event` (a
>    quick thought right after), or `ad_hoc` (a thought any time, with no event —
>    optionally scoped to a team/player). Capture as a big record button (voice),
>    a text field, or quick tag chips. Each note stores match minute, observation
>    type, subject type (player/team/coach/unit), optional shirt number, tags,
>    sentiment (positive/concern/neutral) and tactical phase of play. Voice notes
>    upload to `audio-recordings`. Show live notes as a timeline; surface a
>    quick "capture a thought" entry point everywhere for ad-hoc notes.
> 4. **Team sheet upload** — upload your own squad sheet (image/PDF to the
>    `uploads` bucket) or enter manually; show extracted players (shirt number →
>    name) so observations auto-attribute to your players by shirt number.
> 5. **Post-event reflection** — record/transcribe a reflection, with structured
>    sections: what went well, what didn't work, learning evidence, action
>    points, suggested next focus. Then show **optional, always-skippable** AI
>    follow-up questions and capture answers.
> 6. **Reports** — view generated report (`content_markdown` rendered nicely +
>    optional PDF download from `reports` bucket). Reports are private to
>    creator/club-admin/granted users.
> 7. **Insights** — long-term pattern cards (e.g. "scanning under pressure
>    mentioned in last 6 sessions"), scoped to player/team/club.
>
> **Edge Functions to call (already deployed):** `transcribe-audio`,
> `process-team-sheet`, `clean-observation`, `generate-reflection-questions`,
> `generate-report`, `update-insights`. Invoke via
> `supabase.functions.invoke(...)` and reflect their results in the UI (e.g.
> show the cleaned note after `clean-observation`).
>
> **Storage buckets:** `audio-recordings`, `uploads`, `reports`. Upload files
> under a path prefixed with the user's id (`<user_id>/...`) — RLS requires this.
>
> **Design:** clean, calm, sporty, mobile-first. Reflective and supportive tone,
> not analytical/scoreboard-like. Fast one-handed live capture (big tap targets).
> Light + dark mode.
>
> Build the auth flow, role-based routing, and the Coach Mode flow end-to-end
> first (event → live capture → reflection → report), then Player and
> Coach-developer modes.

## Reference

- Schema & enums: `supabase/migrations/0001_initial_schema.sql`
- RLS rules: `supabase/migrations/0002_rls_policies.sql`
- Buckets: `supabase/migrations/0003_storage_buckets.sql`
- TypeScript object shapes: `types/database.ts`
- Backend overview & per-mode notes: `supabase/README.md`
