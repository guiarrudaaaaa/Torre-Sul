create extension if not exists pgcrypto;

create table if not exists public.operations (
  id uuid primary key default gen_random_uuid(),
  dt text not null unique,
  operation_date date not null,
  plate text not null,
  client text not null,
  carrier text not null,
  driver text not null,
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

alter table public.operations enable row level security;
alter table public.docks enable row level security;
alter table public.operation_events enable row level security;
alter table public.profiles enable row level security;

create policy "authenticated users can read operations"
  on public.operations for select to authenticated using (true);
create policy "authenticated users can update operations"
  on public.operations for update to authenticated using (true) with check (true);
create policy "authenticated users can insert operations"
  on public.operations for insert to authenticated with check (true);

create policy "authenticated users can read docks"
  on public.docks for select to authenticated using (true);
create policy "authenticated users can update docks"
  on public.docks for update to authenticated using (true) with check (true);

create policy "authenticated users can read events"
  on public.operation_events for select to authenticated using (true);
create policy "authenticated users can insert events"
  on public.operation_events for insert to authenticated with check (true);

create policy "users can read own profile"
  on public.profiles for select to authenticated using (id = auth.uid());

create index if not exists operations_date_idx on public.operations (operation_date);
create index if not exists operations_status_idx on public.operations (status);
create index if not exists events_operation_idx on public.operation_events (operation_id, created_at desc);

alter publication supabase_realtime add table public.operations;
alter publication supabase_realtime add table public.docks;
alter publication supabase_realtime add table public.operation_events;
