-- 베스티안 식사 주문: Supabase SQL Editor에서 처음 한 번 실행하세요. 다시 실행해도 안전합니다.
-- 기존 출결 표는 건드리지 않고, 식사 메뉴와 주문을 담을 새 표 두 개와 메뉴 사진 저장소 하나만 만듭니다.

create table if not exists public.bestian_meal_menu (
  meal_date  date        not null,
  meal       text        not null check (meal in ('lunch','dinner')),
  options    jsonb       not null default '[]'::jsonb,
  deadline   text,
  note       text,
  is_open    boolean     not null default true,
  updated_at timestamptz not null default now(),
  primary key (meal_date, meal)
);

create table if not exists public.bestian_meal_orders (
  meal_date    date        not null,
  meal         text        not null check (meal in ('lunch','dinner')),
  student_id   text        not null,
  student_name text        not null,
  choice       text        not null,
  updated_at   timestamptz not null default now(),
  primary key (meal_date, meal, student_id)
);

alter table public.bestian_meal_menu   enable row level security;
alter table public.bestian_meal_orders enable row level security;

drop policy if exists bestian_meal_menu_all on public.bestian_meal_menu;
create policy bestian_meal_menu_all on public.bestian_meal_menu
  for all to anon, authenticated using (true) with check (true);

drop policy if exists bestian_meal_orders_all on public.bestian_meal_orders;
create policy bestian_meal_orders_all on public.bestian_meal_orders
  for all to anon, authenticated using (true) with check (true);

grant select, insert, update, delete on public.bestian_meal_menu   to anon, authenticated;
grant select, insert, update, delete on public.bestian_meal_orders to anon, authenticated;

-- 메뉴 사진 (붙여넣은 사진 주소를 저장)
alter table public.bestian_meal_menu add column if not exists image_url text;

-- 메뉴 사진 저장소: 누구나 볼 수 있는 공개 폴더 하나
insert into storage.buckets (id, name, public)
values ('bestian-meal', 'bestian-meal', true)
on conflict (id) do update set public = true;

drop policy if exists bestian_meal_img_read on storage.objects;
create policy bestian_meal_img_read on storage.objects
  for select to anon, authenticated using (bucket_id = 'bestian-meal');

drop policy if exists bestian_meal_img_insert on storage.objects;
create policy bestian_meal_img_insert on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'bestian-meal');

-- 실시간 반영 켜기 (이미 켜져 있으면 건너뜀)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bestian_meal_menu') then
      alter publication supabase_realtime add table public.bestian_meal_menu;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bestian_meal_orders') then
      alter publication supabase_realtime add table public.bestian_meal_orders;
    end if;
  end if;
end $$;
