-- 베스티안 순공 리그: Supabase SQL Editor에서 처음 한 번 실행하세요. 다시 실행해도 안전합니다.
-- 데스크 전용 Supabase 프로젝트(bestian_desk_setup.sql을 실행한 곳)에 실행하세요.
-- 순공 시간은 원래 출결 서버(키오스크)에서 읽고, 여기에는 닉네임과 보상 기록만 저장합니다.

-- 1) 닉네임 (학생 1명당 1개, 대소문자 무시 중복 금지)
create table if not exists public.bestian_league_profiles (
  student_id text primary key,
  nickname   text not null check (char_length(nickname) between 2 and 10),
  updated_at timestamptz not null default now(),
  updated_by text            -- 'student' 또는 직원 이름
);
create unique index if not exists bestian_league_profiles_nick on public.bestian_league_profiles (lower(nickname));

-- 2) 보상 기록 (주간 1등, 성장왕, 개근 등 — 스터디카페 보상 지급 장부)
create table if not exists public.bestian_league_rewards (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  week_from  date        not null,          -- 그 주 월요일
  student_id text        not null,
  nickname   text,
  kind       text        not null,          -- 'week1','week2','week3','growth','streak' 등
  title      text        not null,          -- 화면에 보이는 이름 (예: 주간 순공 1위)
  prize      text,                          -- 실제 준 보상 (예: 스터디카페 1일권)
  given_by   text,
  unique (week_from, student_id, kind)
);
-- 상점 점수 (전체 1위 10점, 학년 1위 5점). 예전에 실행했어도 이 줄로 열이 추가됩니다.
alter table public.bestian_league_rewards add column if not exists points int not null default 0;

alter table public.bestian_league_profiles enable row level security;
alter table public.bestian_league_rewards  enable row level security;

drop policy if exists bestian_league_profiles_all on public.bestian_league_profiles;
create policy bestian_league_profiles_all on public.bestian_league_profiles
  for all to anon, authenticated using (true) with check (true);
drop policy if exists bestian_league_rewards_all on public.bestian_league_rewards;
create policy bestian_league_rewards_all on public.bestian_league_rewards
  for all to anon, authenticated using (true) with check (true);

grant select, insert, update, delete on public.bestian_league_profiles to anon, authenticated;
grant select, insert, update, delete on public.bestian_league_rewards  to anon, authenticated;

-- 닉네임 바뀌면 TV에 바로 반영
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                     and schemaname = 'public' and tablename = 'bestian_league_profiles') then
    execute 'alter publication supabase_realtime add table public.bestian_league_profiles';
  end if;
end $$;
