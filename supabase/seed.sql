-- =============================================================================
-- seed.sql
-- Example seed data for local development.
--
--   1 club, 1 team, 3 players,
--   1 scouting event, 1 training session,
--   a few live observations.
--
-- A demo auth user is created so foreign keys resolve. In a real Supabase
-- project you would normally sign up through Supabase Auth; this is only for
-- `supabase db reset` / local seeding.
-- =============================================================================

-- Fixed UUIDs so the seed is deterministic / re-runnable.
-- coach user
\set coach_id            '11111111-1111-1111-1111-111111111111'
\set club_id             '22222222-2222-2222-2222-222222222222'
\set team_id             '33333333-3333-3333-3333-333333333333'
\set player_oscar        '44444444-4444-4444-4444-444444444401'
\set player_maya         '44444444-4444-4444-4444-444444444402'
\set player_jay          '44444444-4444-4444-4444-444444444403'
\set scout_event_id      '55555555-5555-5555-5555-555555555501'
\set training_event_id   '55555555-5555-5555-5555-555555555502'

-- Demo auth user (bypasses normal signup). -----------------------------------
insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values (
  :'coach_id',
  'coach@enfieldtownyouth.test',
  '{"full_name": "Sam Coach", "role": "coach"}'::jsonb,
  now(), now()
)
on conflict (id) do nothing;

-- Club ------------------------------------------------------------------------
insert into public.clubs (id, name, created_by)
values (:'club_id', 'Enfield Town Youth', :'coach_id')
on conflict (id) do nothing;

-- Make sure the coach profile points at the club (the new-user trigger
-- created the profile row already; we just enrich it).
update public.profiles
   set full_name = 'Sam Coach', role = 'coach', club_id = :'club_id'
 where id = :'coach_id';

-- Team ------------------------------------------------------------------------
insert into public.teams (id, club_id, name, age_group, created_by)
values (:'team_id', :'club_id', 'U15 JPL', 'U15', :'coach_id')
on conflict (id) do nothing;

-- Players ---------------------------------------------------------------------
insert into public.players
  (id, team_id, first_name, last_name, display_name, shirt_number, position, notes, created_by)
values
  (:'player_oscar', :'team_id', 'Oscar', 'Reed',  'Oscar',  8,  'Central Midfield', 'Good at finding space', :'coach_id'),
  (:'player_maya',  :'team_id', 'Maya',  'Lewis', 'Maya',   6,  'Defensive Midfield', null,                  :'coach_id'),
  (:'player_jay',   :'team_id', 'Jay',   'Owens', 'Jay',    11, 'Left Wing', null,                            :'coach_id')
on conflict (id) do nothing;

-- Events ----------------------------------------------------------------------
insert into public.events
  (id, user_id, club_id, team_id, event_type, title, event_date, opposition, venue, focus_area, status, started_at, ended_at)
values
  (:'training_event_id', :'coach_id', :'club_id', :'team_id', 'training_session',
   'Tuesday Session — Playing Out From The Back', '2026-06-16', null, 'Home Ground',
   'Building under pressure', 'completed', '2026-06-16 18:00:00+00', '2026-06-16 19:30:00+00'),
  (:'scout_event_id', :'coach_id', :'club_id', null, 'team_scouting',
   'Scouting: Dumbarton FC', '2026-06-18', 'Dumbarton FC', 'Away',
   'Build-up shape', 'completed', '2026-06-18 15:00:00+00', '2026-06-18 16:45:00+00')
on conflict (id) do nothing;

-- Live observations (training session) ----------------------------------------
insert into public.observations
  (event_id, user_id, timestamp_seconds, match_minute, input_type, observation_type,
   subject_type, player_id, shirt_number, raw_note, cleaned_note, tags, sentiment, phase_of_play)
values
  (:'training_event_id', :'coach_id', 320, 5, 'text_note', 'technical_action',
   'player', :'player_oscar', 8,
   'oscar scans before receiving good',
   'Oscar scans before receiving.',
   array['scanning','receiving','awareness'], 'positive', 'build_up'),

  (:'training_event_id', :'coach_id', 1100, 18, 'voice_note', 'concern_risk',
   'team', null, null,
   'session got a bit chaotic in the middle third',
   'The session became chaotic in the middle third.',
   array['organisation','chaos'], 'concern', 'middle_third'),

  (:'training_event_id', :'coach_id', 1850, 31, 'tag_only', 'moment_of_quality',
   'player', :'player_jay', 11,
   null, null,
   array['1v1','beat_defender'], 'positive', 'attacking_third');

-- Live observations (scouting event) ------------------------------------------
insert into public.observations
  (event_id, user_id, timestamp_seconds, match_minute, input_type, observation_type,
   subject_type, player_id, shirt_number, raw_note, cleaned_note, tags, sentiment, phase_of_play)
values
  (:'scout_event_id', :'coach_id', 600, 10, 'text_note', 'tactical_pattern',
   'team', null, 6,
   'they build everything through the 6',
   'Opposition builds play through their number 6.',
   array['build_up','number_6'], 'neutral', 'build_up');
