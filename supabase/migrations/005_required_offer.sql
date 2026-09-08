-- Apply after 004. Existing orders may have no offer; all new orders require one.
begin;
alter table public.jobs add column offered_amount numeric(11,2)
  check (offered_amount > 0 and offered_amount <= 999999999.99);
drop function public.request_work(text,text,text,text,double precision,double precision,text);
create function public.request_work(equipment text, loading text, site_address text,
  work_details text, lat double precision, lng double precision, store_number text, offered_amount numeric)
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
  if offered_amount is null or offered_amount <= 0 or offered_amount > 999999999.99
    or offered_amount <> round(offered_amount, 2) then
    raise exception 'A positive offer with up to 2 decimal places is required'; end if;
  insert into public.jobs(customer_id,service,loading_vehicle,address,details,offered_amount)
    values(auth.uid(),equipment,loading,'Work location shared after acceptance',work_details,offered_amount)
    returning id into new_id;
  insert into public.job_sites(job_id,address,lat,lng,store_number) values(new_id,site_address,lat,lng,store_number);
  insert into public.work_notifications(job_id) values(new_id);
  return new_id;
end $$;
revoke all on function public.request_work(text,text,text,text,double precision,double precision,text,numeric) from public,anon;
grant execute on function public.request_work(text,text,text,text,double precision,double precision,text,numeric) to authenticated;

commit;

