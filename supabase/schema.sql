-- Run once in a new Supabase project's SQL editor.
create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id),
  operator_id uuid references auth.users(id),
  service text not null check (service in ('5-finger excavator grapple', 'Pickup van', 'Big truck')),
  address text not null check (length(trim(address)) between 5 and 300),
  details text not null check (length(trim(details)) between 10 and 1000),
  status text not null default 'requested' check (status in ('requested','accepted','on_the_way','working','completed','cancelled')),
  created_at timestamptz not null default now(),
  check (operator_id is null or operator_id <> customer_id)
);
create unique index one_customer_job on public.jobs(customer_id)
  where status in ('requested','accepted','on_the_way','working');
create unique index one_operator_job on public.jobs(operator_id)
  where status in ('accepted','on_the_way','working');
create table public.declines (
  job_id uuid references public.jobs(id) on delete cascade,
  operator_id uuid references auth.users(id),
  primary key (job_id, operator_id)
);
alter table public.jobs enable row level security;
alter table public.declines enable row level security;
revoke all on public.jobs, public.declines from anon, authenticated;
grant select on public.jobs, public.declines to authenticated;
grant insert(customer_id,service,address,details) on public.jobs to authenticated;
create policy read_jobs on public.jobs for select to authenticated using (
  customer_id = auth.uid() or operator_id = auth.uid() or
  (status = 'requested' and auth.jwt()->'app_metadata'->>'role' = 'operator'
    and service = auth.jwt()->'app_metadata'->>'service')
);
create policy request_job on public.jobs for insert to authenticated with check (
  customer_id = auth.uid() and operator_id is null and status = 'requested'
  and coalesce(auth.jwt()->'app_metadata'->>'role', 'customer') <> 'operator'
);
create policy own_declines on public.declines for select to authenticated
  using (operator_id = auth.uid());

create function public.job_action(job_id uuid, action text) returns void
language plpgsql security definer set search_path = '' as $$
declare j public.jobs; uid uuid := auth.uid(); next_status text;
begin
  if uid is null then raise exception 'Sign in first'; end if;
  select * into j from public.jobs where id = job_id for update;
  if not found then raise exception 'Request unavailable'; end if;
  if action = 'cancel' then
    if j.customer_id <> uid or j.status <> 'requested' then
      raise exception 'Only your waiting request can be cancelled'; end if;
    update public.jobs set status = 'cancelled' where id = job_id;
    return;
  end if;
  if coalesce(auth.jwt()->'app_metadata'->>'role', '') <> 'operator' then
    raise exception 'Approved operator account required'; end if;
  if action in ('accept', 'decline') then
    if j.status <> 'requested' or j.customer_id = uid or
       j.service <> coalesce(auth.jwt()->'app_metadata'->>'service', '') then
      raise exception 'This request is no longer available for you'; end if;
    if action = 'decline' then
      insert into public.declines values(job_id, uid) on conflict do nothing;
      return;
    end if;
    if exists(select 1 from public.declines d where d.job_id = j.id and d.operator_id = uid) then
      raise exception 'You already declined this request'; end if;
    update public.jobs set operator_id = uid, status = 'accepted' where id = job_id;
    return;
  end if;
  if j.operator_id is distinct from uid then raise exception 'This is not your job'; end if;
  next_status := case
    when action = 'travel' and j.status = 'accepted' then 'on_the_way'
    when action = 'start' and j.status = 'on_the_way' then 'working'
    when action = 'complete' and j.status = 'working' then 'completed'
    else null end;
  if next_status is null then raise exception 'Invalid work status change'; end if;
  update public.jobs set status = next_status where id = job_id;
end $$;
revoke all on function public.job_action(uuid,text) from public, anon;
grant execute on function public.job_action(uuid,text) to authenticated;
alter publication supabase_realtime add table public.jobs;
