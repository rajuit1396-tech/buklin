create table if not exists users (
 id uuid primary key, email text unique, password_hash text not null,
 name text, phone text, username text unique,
 role text not null default 'customer' check(role in ('customer','operator','admin')),
 service text check(service in ('5-finger excavator grapple','Pickup van','Big truck')),
 online boolean not null default false,
 check(role <> 'operator' or service is not null)
);
create table if not exists sessions (
 token_hash text primary key, user_id uuid not null references users(id), expires_at timestamptz not null
);
alter table users add column if not exists blocked_until timestamptz;
alter table users add column if not exists deleted_at timestamptz;
create table if not exists jobs (
 id uuid primary key, customer_id uuid not null references users(id), operator_id uuid references users(id),
 service text not null check(service in ('5-finger excavator grapple','Pickup van','Big truck')),
 loading_vehicle text not null check(loading_vehicle in ('Dyna','Trailer','Inside store')),
 offered_amount numeric(11,2) not null check(offered_amount between 30 and 999 and offered_amount = trunc(offered_amount)),
 details text not null,
 status text not null default 'requested' check(status in ('requested','accepted','on_the_way','working','completed','cancelled')),
 created_at timestamptz not null default now(), check(operator_id is null or operator_id <> customer_id)
);
create unique index if not exists one_customer_job on jobs(customer_id) where status in ('requested','accepted','on_the_way','working');
create unique index if not exists one_operator_job on jobs(operator_id) where status in ('accepted','on_the_way','working');
create table if not exists job_sites (
 job_id uuid primary key references jobs(id), address text not null,
 store_number text not null check(store_number ~ '^[0-9]{3}$'),
 lat double precision not null check(lat between -90 and 90), lng double precision not null check(lng between -180 and 180)
);
create table if not exists job_locations (
 job_id uuid primary key references jobs(id), lat double precision not null check(lat between -90 and 90),
 lng double precision not null check(lng between -180 and 180), updated_at timestamptz not null default now()
);
create table if not exists declines (
 job_id uuid references jobs(id), operator_id uuid references users(id), primary key(job_id,operator_id)
);
create table if not exists notification_outbox (
 id uuid primary key, job_id uuid not null references jobs(id), attempts integer not null default 0,
 next_attempt timestamptz not null default now(), sent_at timestamptz
);
create table if not exists job_start_codes (
 job_id uuid primary key references jobs(id),
 code text not null check(code ~ '^[0-9]{4}$'),
 failures integer not null default 0,
 window_started timestamptz not null default now()
);
create table if not exists work_charges (
 job_id uuid not null references jobs(id),
 user_id uuid not null references users(id),
 amount integer not null check(amount in (-4,-2)),
 created_at timestamptz not null default now(),
 primary key(job_id,user_id)
);
create table if not exists balance_adjustments (
 id uuid primary key,
 user_id uuid not null references users(id),
 admin_id uuid not null references users(id),
 amount integer not null check(amount<>0 and abs(amount)<=1000000),
 reason text not null check(length(reason) between 3 and 300),
 created_at timestamptz not null default now()
);
alter table balance_adjustments add column if not exists kind text not null default 'adjustment'
 check(kind in ('payment','adjustment'));
create table if not exists activity_log (
 id bigserial primary key,
 user_id uuid references users(id),
 job_id uuid references jobs(id),
 description text not null,
 created_at timestamptz not null default now()
);
create or replace function log_work_activity() returns trigger language plpgsql as $$
begin
 if TG_TABLE_NAME='jobs' then
  if TG_OP='INSERT' then
   insert into activity_log(user_id,job_id,description) values(new.customer_id,new.id,'Work requested');
  elsif new.status is distinct from old.status then
   insert into activity_log(user_id,job_id,description) values(new.customer_id,new.id,'Work status: ' || new.status);
  end if;
 elsif TG_TABLE_NAME='users' then
  if TG_OP='INSERT' then
   insert into activity_log(user_id,description) values(new.id,'Account created: ' || new.role);
  else
   if new.online is distinct from old.online then
    insert into activity_log(user_id,description) values(new.id,case when new.online then 'Operator online' else 'Operator offline' end);
   end if;
   if new.blocked_until is distinct from old.blocked_until then
    insert into activity_log(user_id,description) values(new.id,case when new.blocked_until is null then 'Restriction cleared' else 'Work restriction updated' end);
   end if;
  end if;
 elsif TG_TABLE_NAME='balance_adjustments' then
  insert into activity_log(user_id,description) values(new.user_id,new.kind || ': ' || new.amount || ' Riyal — ' || new.reason);
 end if;
 return new;
end $$;
create or replace trigger jobs_activity after insert or update on jobs for each row execute function log_work_activity();
create or replace trigger users_activity after insert or update on users for each row execute function log_work_activity();
create or replace trigger payments_activity after insert on balance_adjustments for each row execute function log_work_activity();
