-- 베스티안 멘토 센터 · 영단어 시험: 데스크 전용 Supabase 프로젝트(eftroiiexkpnladkiypu)의 SQL Editor에서 한 번 실행하세요.
-- 다시 실행해도 안전합니다. 기존 데스크 표(bestian_desk_*)는 건드리지 않습니다.
-- 이 파일에는 비밀번호·단어장·학생 기록이 없습니다. 그런 값은 따로 받은 bestian_private_seed.sql로 넣습니다.

-- ============================================================
-- 1) 멘토·원장·부원장 명단 (로그인한 이메일이 여기 있어야 멘토 센터 자료가 보입니다)
-- ============================================================
create table if not exists public.bestian_staff (
  email      text primary key check (email = lower(email)),
  name       text not null default '',
  role       text not null default 'mentor' check (role in ('admin','mentor')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.bestian_my_email() returns text
language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;

create or replace function public.bestian_is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bestian_staff where email = public.bestian_my_email() and active)
$$;

create or replace function public.bestian_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bestian_staff where email = public.bestian_my_email() and active and role = 'admin')
$$;

-- 로그인한 사람이 누구인지 (명단에 없으면 null)
create or replace function public.bestian_me() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('email', email, 'name', name, 'role', role)
  from public.bestian_staff where email = public.bestian_my_email() and active
$$;

revoke all on function public.bestian_is_staff() from public;
revoke all on function public.bestian_is_admin() from public;
revoke all on function public.bestian_me() from public;
grant execute on function public.bestian_my_email() to authenticated;
grant execute on function public.bestian_is_staff() to authenticated;
grant execute on function public.bestian_is_admin() to authenticated;
grant execute on function public.bestian_me() to authenticated;

alter table public.bestian_staff enable row level security;
drop policy if exists bestian_staff_read on public.bestian_staff;
create policy bestian_staff_read on public.bestian_staff for select to authenticated using (public.bestian_is_staff());
drop policy if exists bestian_staff_admin on public.bestian_staff;
create policy bestian_staff_admin on public.bestian_staff for all to authenticated
  using (public.bestian_is_admin()) with check (public.bestian_is_admin());
revoke all on public.bestian_staff from anon;
grant select, insert, update, delete on public.bestian_staff to authenticated;

-- ============================================================
-- 2) 멘토 센터 자료 (상담·주간 관리·상담 요청·성적 등). 클로드 멘토 센터의 저장 공간과 같은 모양:
--    col = 모음 이름(counsel, weekly, students …), id = 문서 이름, data = 내용
--    로그인한 명단의 사람만 읽고 쓸 수 있습니다. 학생·데스크·로그인 안 한 사람은 못 봅니다.
-- ============================================================
create table if not exists public.bestian_mc_docs (
  col        text not null,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by text not null default '',
  primary key (col, id)
);

create or replace function public.bestian_mc_docs_stamp() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := public.bestian_my_email();
  return new;
end $$;
drop trigger if exists bestian_mc_docs_stamp on public.bestian_mc_docs;
create trigger bestian_mc_docs_stamp before insert or update on public.bestian_mc_docs
  for each row execute function public.bestian_mc_docs_stamp();

alter table public.bestian_mc_docs enable row level security;
drop policy if exists bestian_mc_docs_staff on public.bestian_mc_docs;
create policy bestian_mc_docs_staff on public.bestian_mc_docs for all to authenticated
  using (public.bestian_is_staff()) with check (public.bestian_is_staff());
revoke all on public.bestian_mc_docs from anon;
grant select, insert, update, delete on public.bestian_mc_docs to authenticated;

-- ============================================================
-- 3) 영단어 시험
--    단어장은 저작권 자료라 저장소(공개)에 두지 않고 여기 표에 넣습니다.
--    학생 화면은 '센터 코드'를 알아야 단어장을 받을 수 있습니다 (코드는 bestian_settings에 저장).
-- ============================================================
create table if not exists public.bestian_settings (
  key   text primary key,
  value text not null
);
alter table public.bestian_settings enable row level security;
drop policy if exists bestian_settings_admin on public.bestian_settings;
create policy bestian_settings_admin on public.bestian_settings for all to authenticated
  using (public.bestian_is_admin()) with check (public.bestian_is_admin());
revoke all on public.bestian_settings from anon;
grant select, insert, update, delete on public.bestian_settings to authenticated;

create table if not exists public.bestian_vocab_books (
  id   text primary key,
  ord  int  not null default 0,
  data jsonb not null
);
alter table public.bestian_vocab_books enable row level security;
revoke all on public.bestian_vocab_books from anon, authenticated;

-- 학생별 · 단어장별 · 회별 진도 (처음 점수, 시험 횟수, 통과한 회차, 최근 오답)
create table if not exists public.bestian_vocab_state (
  student_id text not null,
  book       text not null,
  n          int  not null,
  state      jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (student_id, book, n)
);
alter table public.bestian_vocab_state enable row level security;
drop policy if exists bestian_vocab_state_staff on public.bestian_vocab_state;
create policy bestian_vocab_state_staff on public.bestian_vocab_state for select to authenticated using (public.bestian_is_staff());
revoke all on public.bestian_vocab_state from anon;
grant select on public.bestian_vocab_state to authenticated;

-- 시험 한 번 볼 때마다 한 줄 (데스크·멘토가 보는 기록)
create table if not exists public.bestian_vocab_attempts (
  id           bigint generated always as identity primary key,
  created_at   timestamptz not null default now(),
  biz_date     date not null default (((now() at time zone 'Asia/Seoul') - interval '70 minutes')::date),
  student_id   text not null,
  student_name text not null default '',
  book         text not null,
  book_name    text not null default '',
  n            int  not null,
  unit_label   text not null default '',
  kind         text not null check (kind in ('main','retake')),
  correct      int  not null,
  total        int  not null,
  mc           int[] not null default '{0,0}',
  sp           int[] not null default '{0,0}',
  wrong        text[] not null default '{}',
  passed       boolean not null default false,
  first_try    boolean not null default false,
  took_sec     int
);
create index if not exists bestian_vocab_attempts_day on public.bestian_vocab_attempts (biz_date, student_id);
alter table public.bestian_vocab_attempts enable row level security;
drop policy if exists bestian_vocab_attempts_staff on public.bestian_vocab_attempts;
create policy bestian_vocab_attempts_staff on public.bestian_vocab_attempts for select to authenticated using (public.bestian_is_staff());
revoke all on public.bestian_vocab_attempts from anon;
grant select on public.bestian_vocab_attempts to authenticated;

create or replace function public.bestian_vocab_check_code(p_code text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if p_code is null or not exists (select 1 from public.bestian_settings where key = 'vocab_code' and value = trim(p_code)) then
    raise exception 'BAD_CODE';
  end if;
end $$;
revoke all on function public.bestian_vocab_check_code(text) from public, anon, authenticated;

-- 학생 화면이 처음 열릴 때: 단어장 전체 + 이 학생의 진도
create or replace function public.bestian_vocab_load(p_code text, p_student text) returns json
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.bestian_vocab_check_code(p_code);
  return json_build_object(
    'books',  coalesce((select json_agg(data order by ord, id) from public.bestian_vocab_books), '[]'::json),
    'states', coalesce((select json_agg(json_build_object('book', book, 'n', n, 'state', state))
                        from public.bestian_vocab_state where student_id = coalesce(p_student, '')), '[]'::json)
  );
end $$;

-- 본시험·재시험을 낼 때마다: 기록 한 줄 + 진도 갱신
create or replace function public.bestian_vocab_submit(
  p_code text, p_student text, p_name text, p_book text, p_book_name text, p_n int, p_unit_label text,
  p_kind text, p_grade jsonb, p_state jsonb, p_took_sec int, p_at timestamptz default null
) returns void
language plpgsql security definer set search_path = public as $$
declare cur jsonb; first_try boolean;
begin
  perform public.bestian_vocab_check_code(p_code);
  if coalesce(p_student, '') = '' or p_n is null or p_n < 1 or p_kind not in ('main','retake') then
    raise exception 'BAD_INPUT';
  end if;
  select state into cur from public.bestian_vocab_state where student_id = p_student and book = p_book and n = p_n;
  first_try := cur is null or coalesce((cur ->> 'attempts')::int, 0) = 0;
  insert into public.bestian_vocab_attempts
    (created_at, biz_date, student_id, student_name, book, book_name, n, unit_label, kind, correct, total, mc, sp, wrong, passed, first_try, took_sec)
  values (
    coalesce(least(p_at, now()), now()),
    ((coalesce(least(p_at, now()), now()) at time zone 'Asia/Seoul') - interval '70 minutes')::date,
    p_student, left(coalesce(p_name, ''), 20), p_book, left(coalesce(p_book_name, ''), 40), p_n, left(coalesce(p_unit_label, ''), 20), p_kind,
    (p_grade ->> 'correct')::int, (p_grade ->> 'total')::int,
    array[(p_grade -> 'mc' ->> 0)::int, (p_grade -> 'mc' ->> 1)::int],
    array[(p_grade -> 'sp' ->> 0)::int, (p_grade -> 'sp' ->> 1)::int],
    coalesce(array(select jsonb_array_elements_text(p_grade -> 'wrong')), '{}'),
    (p_grade ->> 'correct')::int >= ceil((p_grade ->> 'total')::numeric * 0.9 - 1e-9),
    first_try, p_took_sec
  );
  -- 진도는 시험 횟수가 더 많은 쪽을 남깁니다 (같은 학생이 두 기기에서 봐도 뒤로 돌아가지 않게)
  if cur is null or coalesce((p_state ->> 'attempts')::int, 0) >= coalesce((cur ->> 'attempts')::int, 0) then
    insert into public.bestian_vocab_state (student_id, book, n, state, updated_at)
    values (p_student, p_book, p_n, p_state, now())
    on conflict (student_id, book, n) do update set state = excluded.state, updated_at = now();
  end if;
end $$;

-- 데스크 화면: 오늘(영업일) 본 시험 목록. 이름·점수만 내보냅니다.
create or replace function public.bestian_vocab_today() returns table (
  id bigint, created_at timestamptz, student_id text, student_name text, book_name text, unit_label text,
  kind text, correct int, total int, passed boolean, first_try boolean, wrong_count int
)
language sql stable security definer set search_path = public as $$
  select id, created_at, student_id, student_name, book_name, unit_label, kind, correct, total, passed, first_try, coalesce(array_length(wrong, 1), 0)
  from public.bestian_vocab_attempts
  where biz_date = ((now() at time zone 'Asia/Seoul') - interval '70 minutes')::date
  order by created_at desc
  limit 300
$$;

grant execute on function public.bestian_vocab_load(text, text) to anon, authenticated;
grant execute on function public.bestian_vocab_submit(text, text, text, text, text, int, text, text, jsonb, jsonb, int, timestamptz) to anon, authenticated;
grant execute on function public.bestian_vocab_today() to anon, authenticated;

-- ============================================================
-- 4) 실시간 반영 (멘토 센터끼리 서로 쓴 내용이 바로 보이게)
-- ============================================================
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['bestian_mc_docs','bestian_vocab_attempts'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
