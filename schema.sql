-- =====================================================================
--  Pujo Parikrama  |  Supabase (free plan) database setup
--  Paste this whole file in: Supabase Dashboard > SQL Editor > Run
-- =====================================================================

-- ---------- helper tables ----------
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.app_settings (
  key text primary key,
  value text not null
);
alter table public.admins       enable row level security;
alter table public.app_settings enable row level security;   -- no policies: only server functions can read it

create policy "admin reads own row" on public.admins
  for select to authenticated using (user_id = auth.uid());

create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = public as
$$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

-- ---------- profiles (friend names) ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 40),
  consented_at timestamptz not null default now(),
  created_at  timestamptz not null default now()
);
alter table public.profiles enable row level security;

create or replace function public.is_member() returns boolean
language sql security definer stable set search_path = public as
$$ select public.is_admin() or exists (select 1 from public.profiles where id = auth.uid()) $$;

-- names are visible to members (needed to pick a friend to chat with)
create policy "members read names" on public.profiles
  for select to authenticated using (public.is_member());
-- nobody inserts directly: they join through join_group() with the secret code
-- a friend can NOT rename themselves; only the admin can
create policy "admin renames" on public.profiles
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin removes" on public.profiles
  for delete to authenticated using (public.is_admin());

create or replace function public.join_group(p_name text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if not exists (select 1 from public.app_settings
                 where key = 'join_code' and lower(btrim(value)) = lower(btrim(p_code))) then
    raise exception 'Wrong join code';
  end if;
  insert into public.profiles (id, name) values (auth.uid(), btrim(p_name))
  on conflict (id) do nothing;
end $$;

create or replace function public.ensure_admin_profile() returns void
language sql security definer set search_path = public as $$
  insert into public.profiles (id, name)
  select auth.uid(), 'Admin' where public.is_admin()
  on conflict (id) do nothing
$$;

-- ---------- pandals (only admin can write) ----------
create table if not exists public.pandals (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  area       text,
  zone       text default 'others',
  note       text,
  lat        double precision not null,
  lng        double precision not null,
  created_at timestamptz not null default now()
);
alter table public.pandals enable row level security;
create policy "members read pandals" on public.pandals
  for select to authenticated using (public.is_member());
create policy "admin writes pandals" on public.pandals
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- live location (friend sees only own, admin sees all) ----------
create table if not exists public.locations (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  lat        double precision not null,
  lng        double precision not null,
  accuracy   real,
  heading    real,
  speed      real,
  updated_at timestamptz not null default now()
);
alter table public.locations enable row level security;
create policy "own or admin read" on public.locations
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "own insert" on public.locations
  for insert to authenticated with check (user_id = auth.uid() and public.is_member());
create policy "own update" on public.locations
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own delete" on public.locations
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- ---------- permanent location history (audit trail, admin only) ----------
create table if not exists public.location_log (
  id        bigint generated always as identity primary key,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  lat       double precision not null,
  lng       double precision not null,
  accuracy  real,
  at        timestamptz not null default now()
);
create index if not exists location_log_user_at on public.location_log (user_id, at desc);
alter table public.location_log enable row level security;
create policy "own insert log" on public.location_log
  for insert to authenticated with check (user_id = auth.uid() and public.is_member());
create policy "admin reads log" on public.location_log
  for select to authenticated using (public.is_admin());

-- ---------- photos (owner + admin only; nobody can delete) ----------
create table if not exists public.photos (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  pandal_id  uuid references public.pandals(id) on delete set null,
  path       text not null,
  lat        double precision,
  lng        double precision,
  distance_m real,
  created_at timestamptz not null default now()
);
alter table public.photos enable row level security;
create policy "own or admin read photos" on public.photos
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "own insert photos" on public.photos
  for insert to authenticated with check (user_id = auth.uid() and public.is_member());

insert into storage.buckets (id, name, public)
values ('pandal-photos', 'pandal-photos', false)
on conflict (id) do nothing;

create policy "upload to own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'pandal-photos'
              and (storage.foldername(name))[1] = auth.uid()::text
              and public.is_member());
create policy "read own folder or admin" on storage.objects
  for select to authenticated
  using (bucket_id = 'pandal-photos'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- ---------- private messages (the two people + admin; nobody can delete) ----------
create table if not exists public.messages (
  id          bigint generated always as identity primary key,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 2000),
  created_at  timestamptz not null default now(),
  check (sender_id <> receiver_id)
);
create index if not exists messages_pair on public.messages (sender_id, receiver_id, created_at);
alter table public.messages enable row level security;
create policy "participants or admin read" on public.messages
  for select to authenticated
  using (sender_id = auth.uid() or receiver_id = auth.uid() or public.is_admin());
create policy "send as yourself" on public.messages
  for insert to authenticated with check (sender_id = auth.uid() and public.is_member());

-- ---------- realtime ----------
alter publication supabase_realtime add table public.locations, public.messages, public.profiles, public.pandals;

-- =====================================================================
--  AFTER running the above, run these TWO lines once (edit the values):
--
--  insert into public.app_settings (key, value) values ('join_code', 'PUJO2026')
--    on conflict (key) do update set value = excluded.value;
--
--  insert into public.admins (user_id)
--    select id from auth.users where email = 'YOUR-ADMIN-EMAIL@example.com';
--
--  (Create the admin user first: Dashboard > Authentication > Users > Add user,
--   tick "Auto Confirm User".)
-- =====================================================================
