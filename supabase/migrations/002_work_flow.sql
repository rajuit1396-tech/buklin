-- Apply after schema.sql. Run once.
 alter table public.jobs add column loading_vehicle text check (length(loading_vehicle) between 1 and 60);
 create table public.job_sites (
   job_id uuid primary key references public.jobs(id) on delete cascade,
   address text not null,
   lat double precision not null check (lat between -90 and 90),
   lng double precision not null check (lng between -180 and 180)
 );
 create table public.job_locations (
   job_id uuid primary key references public.jobs(id) on delete cascade,
   lat double precision not null check (lat between -90 and 90),
   lng double precision not null check (lng between -180 and 180),
   updated_at timestamptz not null default now()
 );
 create table public.operator_availability (
   operator_id uuid primary key references auth.users(id),
   service text not null,
   online boolean not null default false,
   updated_at timestamptz not null default now()
 );
 create table public.work_notifications (
   id uuid primary key default gen_random_uuid(),
   job_id uuid not null references public.jobs(id),
   created_at timestamptz not null default now(),
   sent_at timestamptz,
   unique(job_id)
 );
 alter table public.job_sites enable row level security;
 alter table public.job_locations enable row level security;
 alter table public.operator_availability enable row level security;
 alter table public.work_notifications enable row level security;
 revoke all on public.job_sites, public.job_locations, public.operator_availability, public.work_notifications from anon, authenticated;
 grant select on public.job_sites, public.job_locations, public.operator_availability to authenticated;
 create policy own_availability on public.operator_availability for select to authenticated using (operator_id = auth.uid());
 create policy site_participants on public.job_sites for select to authenticated using (
   exists(select 1 from public.jobs j where j.id = job_id and
     (j.customer_id = auth.uid() or (j.operator_id = auth.uid() and j.status <> 'requested')))
 );
 create policy location_participants on public.job_locations for select to authenticated using (
   exists(select 1 from public.jobs j where j.id = job_id and j.status in ('accepted','on_the_way','working')
     and (j.customer_id = auth.uid() or j.operator_id = auth.uid()))
 );
 revoke insert on public.jobs from authenticated;
 revoke insert(customer_id,service,address,details) on public.jobs from authenticated;
 create function public.request_work(equipment text, loading text, site_address text, work_details text,
   lat double precision, lng double precision) returns uuid
 language plpgsql security definer set search_path = '' as $$
 declare new_id uuid;
 begin
   if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','') = 'operator' then
     raise exception 'Customer account required'; end if;
   if loading is null or length(trim(loading)) not between 1 and 60 or
      site_address is null or length(trim(site_address)) not between 5 and 300 then
     raise exception 'Loading vehicle and work address are required'; end if;
   insert into public.jobs(customer_id,service,loading_vehicle,address,details)
     values(auth.uid(),equipment,trim(loading),'Work location shared after acceptance',work_details) returning id into new_id;
   insert into public.job_sites values(new_id,site_address,lat,lng);
   insert into public.work_notifications(job_id) values(new_id);
   return new_id;
 end $$;
 create function public.set_availability(available boolean) returns void
 language plpgsql security definer set search_path = '' as $$
 begin
   if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','') <> 'operator' then
     raise exception 'Operator account required'; end if;
   insert into public.operator_availability(operator_id,service,online)
     values(auth.uid(),auth.jwt()->'app_metadata'->>'service',available)
     on conflict(operator_id) do update set online = excluded.online, service = excluded.service, updated_at = now();
 end $$;
 create function public.share_location(job_id uuid,lat double precision,lng double precision) returns void
 language plpgsql security definer set search_path = '' as $$
 begin
   perform 1 from public.jobs j where j.id = job_id and j.operator_id = auth.uid()
     and j.status in ('accepted','on_the_way','working') for update;
   if not found then raise exception 'Only the assigned operator can share an active job location'; end if;
   insert into public.job_locations values(job_id,lat,lng,now())
     on conflict(job_id) do update set lat = excluded.lat,lng = excluded.lng,updated_at = now();
 end $$;
 revoke all on function public.request_work(text,text,text,text,double precision,double precision) from public,anon;
 revoke all on function public.set_availability(boolean) from public,anon;
 revoke all on function public.share_location(uuid,double precision,double precision) from public,anon;
 grant execute on function public.request_work(text,text,text,text,double precision,double precision) to authenticated;
 grant execute on function public.set_availability(boolean) to authenticated;
 grant execute on function public.share_location(uuid,double precision,double precision) to authenticated;
