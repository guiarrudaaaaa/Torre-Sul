create extension if not exists pg_cron;

alter table public.operations add column if not exists tons numeric;
alter table public.operations add column if not exists uf text;
alter table public.operations add column if not exists load_type text;
alter table public.operations add column if not exists history_problem text;
alter table public.operations add column if not exists guide_call text;
alter table public.operations add column if not exists delivery_info text;
alter table public.operations add column if not exists otm_date date;
alter table public.operations add column if not exists otm_time time;
alter table public.operations add column if not exists horse_plate text;
alter table public.operations add column if not exists composition text;

create table if not exists public.operational_reports (
  id uuid primary key default gen_random_uuid(),
  report_type text not null check (report_type in ('DAILY', 'WEEKLY', 'MONTHLY')),
  period_start timestamptz not null,
  period_end timestamptz not null,
  timezone text not null default 'America/Sao_Paulo',
  metrics jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default now(),
  unique (report_type, period_start, period_end)
);

alter table public.operational_reports enable row level security;
drop policy if exists "authenticated users can read operational reports" on public.operational_reports;
create policy "authenticated users can read operational reports"
  on public.operational_reports for select to authenticated using (true);

create index if not exists operational_reports_period_idx
  on public.operational_reports (report_type, period_start desc);

create or replace function public.generate_operational_report(
  p_type text,
  p_start timestamptz,
  p_end timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.operational_reports (report_type, period_start, period_end, metrics)
  select p_type, p_start, p_end,
    jsonb_build_object(
      'operations', count(*),
      'finished', count(*) filter (where status in ('SAIDA REALIZADA', 'CARREGAMENTO FINALIZADO', 'DESCARGA FINALIZADA')),
      'by_type', jsonb_build_object(
        'CARREGAMENTO', count(*) filter (where operation_type = 'CARREGAMENTO'),
        'DESCARGA', count(*) filter (where operation_type = 'DESCARGA')
      ),
      'by_status', coalesce((select jsonb_object_agg(status, status_count) from (
        select status, count(*) as status_count from public.operations
        where operation_date >= (p_start at time zone 'America/Sao_Paulo')::date
          and operation_date < (p_end at time zone 'America/Sao_Paulo')::date
        group by status
      ) status_summary), '{}'::jsonb)
    )
  from public.operations
  where operation_date >= (p_start at time zone 'America/Sao_Paulo')::date
    and operation_date < (p_end at time zone 'America/Sao_Paulo')::date
  on conflict (report_type, period_start, period_end) do update
    set metrics = excluded.metrics, generated_at = now();
end;
$$;
revoke execute on function public.generate_operational_report(text, timestamptz, timestamptz) from public;
revoke execute on function public.generate_operational_report(text, timestamptz, timestamptz) from anon, authenticated;

select cron.unschedule('torre-sul-daily-report') where exists (select 1 from cron.job where jobname = 'torre-sul-daily-report');
select cron.unschedule('torre-sul-weekly-report') where exists (select 1 from cron.job where jobname = 'torre-sul-weekly-report');
select cron.unschedule('torre-sul-monthly-report') where exists (select 1 from cron.job where jobname = 'torre-sul-monthly-report');

-- Daily at 00:00 in Sao Paulo (03:00 UTC).
select cron.schedule('torre-sul-daily-report', '0 3 * * *', $$
  select public.generate_operational_report(
    'DAILY',
    (date_trunc('day', now() at time zone 'America/Sao_Paulo') - interval '1 day') at time zone 'America/Sao_Paulo',
    date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'
  );
$$);

-- Weekly: Sunday 22:00 through Saturday 22:00 in Sao Paulo (01:00 UTC Sunday).
select cron.schedule('torre-sul-weekly-report', '0 1 * * 0', $$
  select public.generate_operational_report(
    'WEEKLY',
    (date_trunc('week', now() at time zone 'America/Sao_Paulo') - interval '1 day' + interval '22 hours') at time zone 'America/Sao_Paulo',
    (date_trunc('week', now() at time zone 'America/Sao_Paulo') + interval '5 days' + interval '22 hours') at time zone 'America/Sao_Paulo'
  );
$$);

-- Monthly at 00:00 on the first day of the following month (03:00 UTC).
select cron.schedule('torre-sul-monthly-report', '0 3 1 * *', $$
  select public.generate_operational_report(
    'MONTHLY',
    (date_trunc('month', now() at time zone 'America/Sao_Paulo') - interval '1 month') at time zone 'America/Sao_Paulo',
    date_trunc('month', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'
  );
$$);
