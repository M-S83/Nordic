-- =============================================================================
-- 0002_rls_policies.sql
-- Row Level Security for all tables.
--
-- Guiding rules (kept simple but safe for the MVP):
--   * Users can view and edit their own records.
--   * Club admins can view their club's records.
--   * Coaches / coach developers can view records for their club's teams.
--   * Users can view events they created (plus their club's, as staff).
--   * Players can view their own reflections.
--   * Reports are visible to the creator, club admins, or explicitly granted users.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Helper functions (SECURITY DEFINER to avoid recursive RLS lookups)
-- -----------------------------------------------------------------------------

-- Current user's club.
create or replace function public.current_club_id()
returns uuid
language sql stable security definer set search_path = public
as $$
  select club_id from public.profiles where id = auth.uid();
$$;

-- Current user's role.
create or replace function public.current_user_role()
returns user_role
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- Is the current user a staff member (admin / coach / coach_developer) of a club?
create or replace function public.is_club_staff(target_club uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.club_id = target_club
      and p.role in ('admin', 'coach', 'coach_developer')
  );
$$;

-- Is the current user an admin of a club?
create or replace function public.is_club_admin(target_club uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.club_id = target_club
      and p.role = 'admin'
  );
$$;

-- Can the current user access a given event?
-- (owner, or club staff of the event's club)
create or replace function public.can_access_event(target_event uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.events e
    where e.id = target_event
      and (
        e.user_id = auth.uid()
        or (e.club_id is not null and public.is_club_staff(e.club_id))
      )
  );
$$;

-- Can the current user access a given report?
-- (creator, club admin of the event's club, or explicitly granted)
create or replace function public.can_access_report(target_report uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.reports r
    left join public.events e on e.id = r.event_id
    left join public.teams t on t.id = r.team_id
    where r.id = target_report
      and (
        r.created_by = auth.uid()
        or (e.club_id is not null and public.is_club_admin(e.club_id))     -- per-event report
        or (t.club_id is not null and public.is_club_admin(t.club_id))     -- period report
        or exists (
          select 1 from public.report_access ra
          where ra.report_id = r.id and ra.user_id = auth.uid()
        )
      )
  );
$$;

-- =============================================================================
-- Enable RLS on every table
-- =============================================================================

alter table public.clubs               enable row level security;
alter table public.profiles            enable row level security;
alter table public.teams               enable row level security;
alter table public.players             enable row level security;
alter table public.player_development_notes enable row level security;
alter table public.coach_voice_profiles enable row level security;
alter table public.competitions        enable row level security;
alter table public.events              enable row level security;
alter table public.event_attendance    enable row level security;
alter table public.match_details       enable row level security;
alter table public.match_stats         enable row level security;
alter table public.team_sheets         enable row level security;
alter table public.team_sheet_players  enable row level security;
alter table public.observations        enable row level security;
alter table public.reflections         enable row level security;
alter table public.followup_questions  enable row level security;
alter table public.followup_answers    enable row level security;
alter table public.reports             enable row level security;
alter table public.report_access       enable row level security;
alter table public.insights            enable row level security;

-- =============================================================================
-- PROFILES
-- =============================================================================

create policy "profiles: read self or club members"
  on public.profiles for select
  using (
    id = auth.uid()
    or (club_id is not null and club_id = public.current_club_id())
  );

create policy "profiles: insert self"
  on public.profiles for insert
  with check (id = auth.uid());

create policy "profiles: update self"
  on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- =============================================================================
-- CLUBS
-- =============================================================================

create policy "clubs: read own club or created"
  on public.clubs for select
  using (id = public.current_club_id() or created_by = auth.uid());

create policy "clubs: insert by authenticated"
  on public.clubs for insert
  with check (created_by = auth.uid());

create policy "clubs: update by admin or creator"
  on public.clubs for update
  using (created_by = auth.uid() or public.is_club_admin(id))
  with check (created_by = auth.uid() or public.is_club_admin(id));

-- =============================================================================
-- TEAMS
-- =============================================================================

create policy "teams: read for club staff or creator"
  on public.teams for select
  using (created_by = auth.uid() or public.is_club_staff(club_id));

create policy "teams: insert for club staff"
  on public.teams for insert
  with check (created_by = auth.uid() and public.is_club_staff(club_id));

create policy "teams: update for club staff or creator"
  on public.teams for update
  using (created_by = auth.uid() or public.is_club_staff(club_id))
  with check (created_by = auth.uid() or public.is_club_staff(club_id));

create policy "teams: delete for club admin or creator"
  on public.teams for delete
  using (created_by = auth.uid() or public.is_club_admin(club_id));

-- =============================================================================
-- COMPETITIONS  (club staff manage; names are editable)
-- =============================================================================

create policy "competitions: read for club staff or creator"
  on public.competitions for select
  using (created_by = auth.uid() or public.is_club_staff(club_id));

create policy "competitions: insert for club staff"
  on public.competitions for insert
  with check (created_by = auth.uid() and public.is_club_staff(club_id));

create policy "competitions: update for club staff or creator"
  on public.competitions for update
  using (created_by = auth.uid() or public.is_club_staff(club_id))
  with check (created_by = auth.uid() or public.is_club_staff(club_id));

create policy "competitions: delete for club admin or creator"
  on public.competitions for delete
  using (created_by = auth.uid() or public.is_club_admin(club_id));

-- =============================================================================
-- PLAYERS
-- Visible to the creator, or to staff of the team's club.
-- =============================================================================

create policy "players: read"
  on public.players for select
  using (
    created_by = auth.uid()
    or exists (
      select 1 from public.teams t
      where t.id = players.team_id and public.is_club_staff(t.club_id)
    )
  );

create policy "players: insert"
  on public.players for insert
  with check (created_by = auth.uid());

create policy "players: update"
  on public.players for update
  using (
    created_by = auth.uid()
    or exists (
      select 1 from public.teams t
      where t.id = players.team_id and public.is_club_staff(t.club_id)
    )
  )
  with check (
    created_by = auth.uid()
    or exists (
      select 1 from public.teams t
      where t.id = players.team_id and public.is_club_staff(t.club_id)
    )
  );

create policy "players: delete"
  on public.players for delete
  using (created_by = auth.uid());

-- =============================================================================
-- PLAYER DEVELOPMENT NOTES
-- Author writes; club staff of the player's team can also read.
-- =============================================================================

create policy "player_dev_notes: read own or club staff"
  on public.player_development_notes for select
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.players p
      join public.teams t on t.id = p.team_id
      where p.id = player_development_notes.player_id and public.is_club_staff(t.club_id)
    )
  );

create policy "player_dev_notes: insert own"
  on public.player_development_notes for insert
  with check (user_id = auth.uid());

create policy "player_dev_notes: update own"
  on public.player_development_notes for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "player_dev_notes: delete own"
  on public.player_development_notes for delete
  using (user_id = auth.uid());

-- =============================================================================
-- COACH VOICE PROFILES  (each user owns their own)
-- =============================================================================

create policy "voice_profile: read own"
  on public.coach_voice_profiles for select
  using (user_id = auth.uid());

create policy "voice_profile: insert own"
  on public.coach_voice_profiles for insert
  with check (user_id = auth.uid());

create policy "voice_profile: update own"
  on public.coach_voice_profiles for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- =============================================================================
-- EVENTS
-- =============================================================================

create policy "events: read own or club staff"
  on public.events for select
  using (
    user_id = auth.uid()
    or (club_id is not null and public.is_club_staff(club_id))
  );

create policy "events: insert own"
  on public.events for insert
  with check (user_id = auth.uid());

create policy "events: update own or club admin"
  on public.events for update
  using (user_id = auth.uid() or (club_id is not null and public.is_club_admin(club_id)))
  with check (user_id = auth.uid() or (club_id is not null and public.is_club_admin(club_id)));

create policy "events: delete own or club admin"
  on public.events for delete
  using (user_id = auth.uid() or (club_id is not null and public.is_club_admin(club_id)));

-- =============================================================================
-- EVENT-SCOPED CHILD TABLES
-- Access follows whoever can access the parent event.
-- =============================================================================

-- team_sheets ----------------------------------------------------------------
create policy "team_sheets: access via event"
  on public.team_sheets for all
  using (public.can_access_event(event_id))
  with check (public.can_access_event(event_id));

-- team_sheet_players ----------------------------------------------------------
create policy "team_sheet_players: access via team sheet"
  on public.team_sheet_players for all
  using (
    exists (
      select 1 from public.team_sheets ts
      where ts.id = team_sheet_players.team_sheet_id
        and public.can_access_event(ts.event_id)
    )
  )
  with check (
    exists (
      select 1 from public.team_sheets ts
      where ts.id = team_sheet_players.team_sheet_id
        and public.can_access_event(ts.event_id)
    )
  );

-- observations ----------------------------------------------------------------
-- Owner always has access (covers ad-hoc notes with no event); event-linked
-- notes are additionally visible to anyone who can access the event.
create policy "observations: access own or via event"
  on public.observations for all
  using (
    user_id = auth.uid()
    or (event_id is not null and public.can_access_event(event_id))
  )
  with check (
    user_id = auth.uid()
    or (event_id is not null and public.can_access_event(event_id))
  );

-- attendance / match record (event-scoped) ------------------------------------
create policy "event_attendance: access via event"
  on public.event_attendance for all
  using (public.can_access_event(event_id))
  with check (public.can_access_event(event_id));

create policy "match_details: access via event"
  on public.match_details for all
  using (public.can_access_event(event_id))
  with check (public.can_access_event(event_id));

create policy "match_stats: access via event"
  on public.match_stats for all
  using (public.can_access_event(event_id))
  with check (public.can_access_event(event_id));

-- =============================================================================
-- REFLECTIONS
-- The author always has access; club staff can read reflections on their
-- club's events. Players reading their own reflections is covered by user_id.
-- =============================================================================

create policy "reflections: read own or event access"
  on public.reflections for select
  using (user_id = auth.uid() or public.can_access_event(event_id));

create policy "reflections: insert own"
  on public.reflections for insert
  with check (user_id = auth.uid());

create policy "reflections: update own"
  on public.reflections for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "reflections: delete own"
  on public.reflections for delete
  using (user_id = auth.uid());

-- =============================================================================
-- FOLLOW-UP QUESTIONS & ANSWERS  (scoped to the parent reflection's owner)
-- =============================================================================

create policy "followup_questions: access via reflection"
  on public.followup_questions for all
  using (
    exists (
      select 1 from public.reflections r
      where r.id = followup_questions.reflection_id
        and (r.user_id = auth.uid() or public.can_access_event(r.event_id))
    )
  )
  with check (
    exists (
      select 1 from public.reflections r
      where r.id = followup_questions.reflection_id
        and r.user_id = auth.uid()
    )
  );

create policy "followup_answers: access via question"
  on public.followup_answers for all
  using (
    exists (
      select 1 from public.followup_questions q
      join public.reflections r on r.id = q.reflection_id
      where q.id = followup_answers.question_id
        and (r.user_id = auth.uid() or public.can_access_event(r.event_id))
    )
  )
  with check (
    exists (
      select 1 from public.followup_questions q
      join public.reflections r on r.id = q.reflection_id
      where q.id = followup_answers.question_id
        and r.user_id = auth.uid()
    )
  );

-- =============================================================================
-- REPORTS
-- Visible to creator, club admins, or explicitly granted users.
-- =============================================================================

create policy "reports: read"
  on public.reports for select
  using (public.can_access_report(id));

create policy "reports: insert via event or team access"
  on public.reports for insert
  with check (
    created_by = auth.uid()
    and (
      (event_id is not null and public.can_access_event(event_id))          -- per-event report
      or (event_id is null and team_id is not null and exists (             -- period report
        select 1 from public.teams t
        where t.id = reports.team_id and public.is_club_staff(t.club_id)
      ))
    )
  );

create policy "reports: update by creator"
  on public.reports for update
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

create policy "reports: delete by creator"
  on public.reports for delete
  using (created_by = auth.uid());

-- report_access ---------------------------------------------------------------
create policy "report_access: read own or report owner"
  on public.report_access for select
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.reports r
      where r.id = report_access.report_id and r.created_by = auth.uid()
    )
  );

create policy "report_access: manage by report owner"
  on public.report_access for all
  using (
    exists (
      select 1 from public.reports r
      where r.id = report_access.report_id and r.created_by = auth.uid()
    )
  )
  with check (
    granted_by = auth.uid()
    and exists (
      select 1 from public.reports r
      where r.id = report_access.report_id and r.created_by = auth.uid()
    )
  );

-- =============================================================================
-- INSIGHTS
-- Owned by the user who generated them; club staff can read club-scoped ones.
-- =============================================================================

create policy "insights: read own or club staff"
  on public.insights for select
  using (
    user_id = auth.uid()
    or (club_id is not null and public.is_club_staff(club_id))
  );

create policy "insights: insert own"
  on public.insights for insert
  with check (user_id = auth.uid());

create policy "insights: update own"
  on public.insights for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "insights: delete own"
  on public.insights for delete
  using (user_id = auth.uid());

-- =============================================================================
-- TABLE-LEVEL GRANTS
-- RLS only *restricts* access; the API roles still need base privileges.
-- Supabase's managed platform normally configures these via default
-- privileges, but we set them explicitly so the migrations are self-contained.
-- =============================================================================

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to anon, authenticated;
