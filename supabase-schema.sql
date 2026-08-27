create extension if not exists pgcrypto;

create table if not exists public.operations (
  id uuid primary key default gen_random_uuid(),
  dt text not null unique,
  operation_date date not null,
  plate text not null,
  client text not null,
  carrier text not null,
  driver text not null,
  tons numeric,
  uf text,
  load_type text,
  history_problem text,
  guide_call text,
  delivery_info text,
  otm_date date,
  otm_time time,
  horse_plate text,
  composition text,
  operation_type text not null check (operation_type in ('CARREGAMENTO', 'DESCARGA')),
  dock_number text,
  start_time time,
  status text not null,
  risk text not null default 'green' check (risk in ('red', 'orange', 'green')),
  tone text not null default 'blue',
  age text not null default 'current',
  sla text not null default '02:00',
  elapsed text not null default '00:00',
  next_action text,
  last_action time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.docks (
  number text primary key,
  state text not null check (state in ('free', 'busy', 'blocked', 'reserved')),
  updated_at timestamptz not null default now()
);

create table if not exists public.operation_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null references public.operations(id) on delete cascade,
  event_type text not null,
  observation text,
  user_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  role text not null check (role in ('ADMINISTRADOR', 'COORDENADOR', 'SUPERVISOR', 'OPERADOR', 'VISUALIZACAO')),
  created_at timestamptz not null default now()
);

create table if not exists public.operational_settings (
  key text primary key,
  value text not null,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

alter table public.operations enable row level security;
alter table public.docks enable row level security;
alter table public.operation_events enable row level security;
alter table public.profiles enable row level security;
alter table public.operational_settings enable row level security;

drop policy if exists "authenticated users can read operations" on public.operations;
create policy "authenticated users can read operations"
  on public.operations for select to authenticated using (true);

drop policy if exists "authenticated users can read docks" on public.docks;
create policy "authenticated users can read docks"
  on public.docks for select to authenticated using (true);

drop policy if exists "authenticated users can read events" on public.operation_events;
create policy "authenticated users can read events"
  on public.operation_events for select to authenticated using (true);
drop policy if exists "authenticated users can insert events" on public.operation_events;
create policy "authenticated users can insert events"
  on public.operation_events for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "users can read own profile" on public.profiles;
create policy "users can read own profile"
  on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists "authenticated users can read settings" on public.operational_settings;
create policy "authenticated users can read settings" on public.operational_settings for select to authenticated using (true);

create index if not exists operations_date_idx on public.operations (operation_date);
create index if not exists operations_status_idx on public.operations (status);
create index if not exists events_operation_idx on public.operation_events (operation_id, created_at desc);
create unique index if not exists active_operation_dock_idx on public.operations (dock_number) where dock_number is not null and status <> 'SAIDA REALIZADA';

create or replace function public.user_has_role(allowed_roles text[])
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id = auth.uid() and role = any(allowed_roles)); $$;

insert into public.profiles (id, name, role)
select id, coalesce(raw_user_meta_data ->> 'name', email), 'COORDENADOR'
from auth.users
on conflict (id) do nothing;

create or replace function public.handle_new_user_profile()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  insert into public.profiles (id, name, role) values (new.id, coalesce(new.raw_user_meta_data ->> 'name', new.email), 'VISUALIZACAO') on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile after insert on auth.users for each row execute function public.handle_new_user_profile();

drop policy if exists "managers can read profiles" on public.profiles;
create policy "managers can read profiles" on public.profiles for select to authenticated using (public.user_has_role(array['ADMINISTRADOR','COORDENADOR']));
drop policy if exists "managers can write settings" on public.operational_settings;
create policy "managers can write settings" on public.operational_settings for all to authenticated using (public.user_has_role(array['ADMINISTRADOR','COORDENADOR'])) with check (public.user_has_role(array['ADMINISTRADOR','COORDENADOR']));

drop policy if exists "authenticated users can update operations" on public.operations;
drop policy if exists "authenticated users can insert operations" on public.operations;
drop policy if exists "authenticated users can update docks" on public.docks;
drop policy if exists "authenticated users can insert docks" on public.docks;
drop policy if exists "authenticated users can delete operations" on public.operations;
drop policy if exists "operation roles can update operations" on public.operations;
drop policy if exists "operation roles can insert operations" on public.operations;
drop policy if exists "operation roles can update docks" on public.docks;
drop policy if exists "operation roles can insert docks" on public.docks;
drop policy if exists "administrators can delete operations" on public.operations;
create policy "operation roles can update operations" on public.operations for update to authenticated using (public.user_has_role(array['ADMINISTRADOR','COORDENADOR','SUPERVISOR','OPERADOR'])) with check (public.user_has_role(array['ADMINISTRADOR','COORDENADOR','SUPERVISOR','OPERADOR']));
create policy "operation roles can insert operations" on public.operations for insert to authenticated with check (public.user_has_role(array['ADMINISTRADOR','COORDENADOR','SUPERVISOR','OPERADOR']));
create policy "operation roles can update docks" on public.docks for update to authenticated using (public.user_has_role(array['ADMINISTRADOR','COORDENADOR','SUPERVISOR','OPERADOR'])) with check (public.user_has_role(array['ADMINISTRADOR','COORDENADOR','SUPERVISOR','OPERADOR']));
create policy "operation roles can insert docks" on public.docks for insert to authenticated with check (public.user_has_role(array['ADMINISTRADOR','COORDENADOR','SUPERVISOR','OPERADOR']));
create policy "administrators can delete operations" on public.operations for delete to authenticated using (public.user_has_role(array['ADMINISTRADOR']));

revoke execute on function public.user_has_role(text[]) from public;
revoke all on function public.user_has_role(text[]) from anon;
grant execute on function public.user_has_role(text[]) to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'operations') then alter publication supabase_realtime add table public.operations; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'docks') then alter publication supabase_realtime add table public.docks; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'operation_events') then alter publication supabase_realtime add table public.operation_events; end if;
end $$;
