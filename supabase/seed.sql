-- =============================================================================
-- seed.sql
-- Example seed data for local development.
--
--   1 club, 1 team, 3 players,
--   1 match, 1 training session,
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
\set match_event_id      '55555555-5555-5555-5555-555555555501'
\set training_event_id   '55555555-5555-5555-5555-555555555502'
\set league_comp_id      '66666666-6666-6666-6666-666666666601'
\set cup_comp_id         '66666666-6666-6666-6666-666666666602'

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

-- Competitions (editable names) -----------------------------------------------
insert into public.competitions (id, club_id, team_id, name, kind, created_by)
values
  (:'league_comp_id', :'club_id', :'team_id', 'JPL Division 1', 'league', :'coach_id'),
  (:'cup_comp_id',    :'club_id', :'team_id', 'County Cup',     'cup',    :'coach_id')
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
  (id, user_id, club_id, team_id, competition_id, event_type, title, event_date, opposition, venue, focus_area, status, started_at, ended_at)
values
  (:'training_event_id', :'coach_id', :'club_id', :'team_id', null, 'training_session',
   'Tuesday Session — Playing Out From The Back', '2026-06-16', null, 'Home Ground',
   'Building under pressure', 'completed', '2026-06-16 18:00:00+00', '2026-06-16 19:30:00+00'),
  (:'match_event_id', :'coach_id', :'club_id', :'team_id', :'league_comp_id', 'match',
   'JPL Division 1 vs Barnet Youth', '2026-06-18', 'Barnet Youth', 'Home Ground',
   'Our build-up shape', 'completed', '2026-06-18 15:00:00+00', '2026-06-18 16:45:00+00')
on conflict (id) do nothing;

-- Pre-training note (planning thought before the session) ---------------------
insert into public.observations
  (event_id, user_id, team_id, capture_phase, input_type, observation_type,
   subject_type, raw_note, cleaned_note, tags, sentiment)
values
  (:'training_event_id', :'coach_id', :'team_id', 'pre_event', 'text_note', 'follow_up_later',
   'team', 'want to see if they can build out under a press today',
   'Focus: can the team build out under pressure today?',
   array['plan','build_up'], 'neutral');

-- Live observations (during the training session) -----------------------------
insert into public.observations
  (event_id, user_id, team_id, capture_phase, timestamp_seconds, match_minute, input_type,
   observation_type, subject_type, player_id, shirt_number, raw_note, cleaned_note, tags, sentiment, phase_of_play)
values
  (:'training_event_id', :'coach_id', :'team_id', 'live', 320, 5, 'text_note', 'technical_action',
   'player', :'player_oscar', 8,
   'oscar scans before receiving good',
   'Oscar scans before receiving.',
   array['scanning','receiving','awareness'], 'positive', 'build_up'),

  (:'training_event_id', :'coach_id', :'team_id', 'live', 1100, 18, 'voice_note', 'concern_risk',
   'team', null, null,
   'session got a bit chaotic in the middle third',
   'The session became chaotic in the middle third.',
   array['organisation','chaos'], 'concern', 'middle_third'),

  (:'training_event_id', :'coach_id', :'team_id', 'live', 1850, 31, 'tag_only', 'moment_of_quality',
   'player', :'player_jay', 11,
   null, null,
   array['1v1','beat_defender'], 'positive', 'attacking_third');

-- Post-training quick note (a thought right after) ----------------------------
insert into public.observations
  (event_id, user_id, team_id, capture_phase, input_type, observation_type,
   subject_type, raw_note, cleaned_note, tags, sentiment)
values
  (:'training_event_id', :'coach_id', :'team_id', 'post_event', 'voice_note', 'team_observation',
   'team', 'constraints were too loose in the middle block, tighten next week',
   'The constraints in the middle block were too loose; tighten them next week.',
   array['constraints','organisation'], 'concern');

-- Ad-hoc note (a thought at any time, not tied to any event) -------------------
insert into public.observations
  (event_id, user_id, team_id, capture_phase, input_type, observation_type,
   subject_type, player_id, raw_note, cleaned_note, tags, sentiment)
values
  (null, :'coach_id', :'team_id', 'ad_hoc', 'text_note', 'follow_up_later',
   'player', :'player_oscar',
   'idea: give oscar a half-space receiving role next block',
   'Idea: try Oscar in a half-space receiving role next training block.',
   array['idea','role','oscar'], 'neutral');

-- Attendance (who was there) --------------------------------------------------
insert into public.event_attendance (event_id, player_id, status)
values
  (:'training_event_id', :'player_oscar', 'present'),
  (:'training_event_id', :'player_maya',  'present'),
  (:'training_event_id', :'player_jay',   'injured'),
  (:'match_event_id',    :'player_oscar', 'present'),
  (:'match_event_id',    :'player_maya',  'present'),
  (:'match_event_id',    :'player_jay',   'present')
on conflict (event_id, player_id) do nothing;

-- Match record: scoreline, venue side, man of the match -----------------------
insert into public.match_details
  (event_id, home_away, goals_for, goals_against, man_of_the_match, notes)
values
  (:'match_event_id', 'home', 2, 0, :'player_oscar',
   'Clean sheet held under late pressure; controlled build-up throughout.')
on conflict (event_id) do nothing;

-- Per-player match stats (who scored, assists, cards, clean sheets) -----------
insert into public.match_stats
  (event_id, player_id, goals, assists, yellow_cards, red_cards, clean_sheet, minutes_played)
values
  (:'match_event_id', :'player_oscar', 1, 1, 0, 0, false, 90),
  (:'match_event_id', :'player_jay',   1, 0, 1, 0, false, 78),
  (:'match_event_id', :'player_maya',  0, 1, 0, 0, true,  90)
on conflict (event_id, player_id) do nothing;

-- Live observations (match) ---------------------------------------------------
insert into public.observations
  (event_id, user_id, timestamp_seconds, match_minute, input_type, observation_type,
   subject_type, player_id, shirt_number, raw_note, cleaned_note, tags, sentiment, phase_of_play)
values
  (:'match_event_id', :'coach_id', 600, 10, 'text_note', 'tactical_pattern',
   'team', null, 6,
   'we keep building through maya at the 6',
   'The team consistently builds play through Maya at number 6.',
   array['build_up','number_6'], 'neutral', 'build_up');
