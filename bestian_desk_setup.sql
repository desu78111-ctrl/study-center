-- 베스티안 스터디센터 데스크 ↔ 학생 태블릿: Supabase SQL Editor에서 처음 한 번 실행하세요. 다시 실행해도 안전합니다.
-- 데스크 전용 Supabase 프로젝트(eftroiiexkpnladkiypu)에 실행했습니다. 학생·출결·좌석은 원래 출결 서버에서 읽습니다.
-- 새 표 세 개와 사진 저장소 하나만 만듭니다.
-- 하루 기준은 독서실 영업일과 같습니다(새벽 01:10에 다음 날로 바뀜).

-- 1) 학생 → 데스크 요청 (질문·자료·깨우기·호출·메시지)
create table if not exists public.bestian_desk_requests (
  id           bigint generated always as identity primary key,
  created_at   timestamptz not null default now(),
  biz_date     date        not null default (((now() at time zone 'Asia/Seoul') - interval '70 minutes')::date),
  student_id   text        not null,
  student_name text        not null,
  seat_no      int,
  kind         text        not null check (kind in ('question','material','wake','call','message')),
  subject      text,
  body         text,
  image_url    text,
  status       text        not null default 'new' check (status in ('new','doing','done','cancel')),
  wake_until   timestamptz,
  reply        text,
  replied_at   timestamptz,
  done_at      timestamptz,
  done_by      text,
  self_woke    boolean     not null default false
);
create index if not exists bestian_desk_requests_day on public.bestian_desk_requests (biz_date, student_id);

-- 2) 데스크 → 학생 메시지 (student_id가 비어 있으면 전체 공지)
create table if not exists public.bestian_desk_messages (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  biz_date   date        not null default (((now() at time zone 'Asia/Seoul') - interval '70 minutes')::date),
  student_id text,
  body       text        not null,
  kind       text        not null default 'msg' check (kind in ('msg','call','notice')),
  sent_by    text,
  read_at    timestamptz
);
create index if not exists bestian_desk_messages_day on public.bestian_desk_messages (biz_date);

-- 3) 깨우기 추가 횟수 (데스크에서 +1회 줄 때)
create table if not exists public.bestian_desk_wake_bonus (
  biz_date   date not null,
  student_id text not null,
  extra      int  not null default 0,
  primary key (biz_date, student_id)
);

-- 깨우기 규칙: 10분 고정, 하루 3회(+데스크가 준 추가 횟수), 동시에 하나만.
-- 시작 시각과 끝나는 시각은 서버 시계로 정하므로 태블릿 시계가 틀려도 데스크와 똑같이 맞습니다.
create or replace function public.bestian_desk_before_insert() returns trigger
language plpgsql as $$
declare used int; bonus int;
begin
  new.created_at := now();
  new.biz_date   := ((now() at time zone 'Asia/Seoul') - interval '70 minutes')::date;
  new.status     := 'new';
  new.wake_until := null;
  if new.kind = 'wake' then
    if exists (select 1 from public.bestian_desk_requests
               where student_id = new.student_id and kind = 'wake' and status in ('new','doing')) then
      raise exception 'WAKE_ACTIVE';
    end if;
    select count(*) into used from public.bestian_desk_requests
      where student_id = new.student_id and kind = 'wake' and biz_date = new.biz_date;
    select coalesce(max(extra),0) into bonus from public.bestian_desk_wake_bonus
      where student_id = new.student_id and biz_date = new.biz_date;
    if used >= 3 + bonus then
      raise exception 'WAKE_LIMIT';
    end if;
    new.wake_until := now() + interval '10 minutes';
  end if;
  return new;
end $$;

drop trigger if exists bestian_desk_before_insert on public.bestian_desk_requests;
create trigger bestian_desk_before_insert before insert on public.bestian_desk_requests
  for each row execute function public.bestian_desk_before_insert();

create or replace function public.bestian_desk_msg_before_insert() returns trigger
language plpgsql as $$
begin
  new.created_at := now();
  new.biz_date   := ((now() at time zone 'Asia/Seoul') - interval '70 minutes')::date;
  return new;
end $$;
drop trigger if exists bestian_desk_msg_before_insert on public.bestian_desk_messages;
create trigger bestian_desk_msg_before_insert before insert on public.bestian_desk_messages
  for each row execute function public.bestian_desk_msg_before_insert();

-- 서버 시계 (두 화면의 카운트다운을 맞추는 데 씀)
create or replace function public.bestian_now() returns timestamptz language sql stable as $$ select now() $$;
grant execute on function public.bestian_now() to anon, authenticated;

-- 접근 권한 (기존 식사 주문 표와 같은 방식)
alter table public.bestian_desk_requests   enable row level security;
alter table public.bestian_desk_messages   enable row level security;
alter table public.bestian_desk_wake_bonus enable row level security;

drop policy if exists bestian_desk_requests_all on public.bestian_desk_requests;
create policy bestian_desk_requests_all on public.bestian_desk_requests
  for all to anon, authenticated using (true) with check (true);
drop policy if exists bestian_desk_messages_all on public.bestian_desk_messages;
create policy bestian_desk_messages_all on public.bestian_desk_messages
  for all to anon, authenticated using (true) with check (true);
drop policy if exists bestian_desk_wake_bonus_all on public.bestian_desk_wake_bonus;
create policy bestian_desk_wake_bonus_all on public.bestian_desk_wake_bonus
  for all to anon, authenticated using (true) with check (true);

grant select, insert, update, delete on public.bestian_desk_requests   to anon, authenticated;
grant select, insert, update, delete on public.bestian_desk_messages   to anon, authenticated;
grant select, insert, update, delete on public.bestian_desk_wake_bonus to anon, authenticated;

-- 질문 사진 저장소
insert into storage.buckets (id, name, public)
values ('bestian-desk', 'bestian-desk', true)
on conflict (id) do update set public = true;

drop policy if exists bestian_desk_img_read on storage.objects;
create policy bestian_desk_img_read on storage.objects
  for select to anon, authenticated using (bucket_id = 'bestian-desk');
drop policy if exists bestian_desk_img_insert on storage.objects;
create policy bestian_desk_img_insert on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'bestian-desk');

-- 실시간 반영 켜기
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['bestian_desk_requests','bestian_desk_messages','bestian_desk_wake_bonus'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
