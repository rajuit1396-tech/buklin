-- Apply after 003_store_number.sql. Keep store numbers in the private site table.
-- Existing site_participants RLS permits only customer and assigned operator.
begin;
alter table public.job_sites add column store_number text check (store_number ~ '^[0-9]{3}$');
update public.job_sites s set store_number = j.store_number from public.jobs j where j.id = s.job_id;
alter table public.jobs drop column store_number;
create or replace function public.request_work(equipment text, loading text, site_address text,
  work_details text, lat double precision, lng double precision, store_number text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','') = 'operator' then
    raise exception 'Customer account required'; end if;
  if store_number is null or store_number !~ '^[0-9]{3}$' then
    raise exception 'Store number must contain exactly 3 digits'; end if;
  if loading is null or loading not in ('Dyna','Trailer','Inside store') then
    raise exception 'Select Dyna, Trailer or Inside store'; end if;
  if site_address is null or length(trim(site_address)) not between 5 and 300 then
    raise exception 'Work location is required'; end if;
  insert into public.jobs(customer_id,service,loading_vehicle,address,details)
    values(auth.uid(),equipment,loading,'Work location shared after acceptance',work_details)
    returning id into new_id;
  insert into public.job_sites(job_id,address,lat,lng,store_number) values(new_id,site_address,lat,lng,store_number);
  insert into public.work_notifications(job_id) values(new_id);
  return new_id;
end $$;
revoke all on function public.request_work(text,text,text,text,double precision,double precision,text) from public,anon;
grant execute on function public.request_work(text,text,text,text,double precision,double precision,text) to authenticated;

commit;
