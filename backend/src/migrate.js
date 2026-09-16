import {readFile} from 'node:fs/promises';
import {pool} from './db.js';
import {randomInt} from 'node:crypto';
const client = await pool.connect();
try {
 await client.query('BEGIN');
 await client.query(await readFile(new URL('../schema.sql',import.meta.url),'utf8'));
 await client.query(`alter table users alter column email drop not null;
   alter table users add column if not exists name text;
   alter table users add column if not exists phone text;
   alter table users add column if not exists username text;
   alter table users add column if not exists deleted_at timestamptz;
   create unique index if not exists users_username_unique on users(username);
   alter table users drop constraint if exists users_role_check;
   alter table users add constraint users_role_check check(role in ('customer','operator','admin'));`);
 await client.query(`alter table jobs drop constraint if exists jobs_offered_amount_check;
   alter table jobs add constraint jobs_offered_amount_check
   check (offered_amount between 30 and 999 and offered_amount = trunc(offered_amount));`);
 await client.query(`alter table work_charges drop constraint if exists work_charges_amount_check;
   alter table work_charges add constraint work_charges_amount_check check(amount in (-4,-2));`);
 const {rows:waiting} = await client.query(`select id from jobs where status in ('accepted','on_the_way')
   and not exists(select 1 from job_start_codes codes where codes.job_id=jobs.id)`);
 for (const job of waiting) await client.query('insert into job_start_codes(job_id,code) values($1,$2)',
   [job.id,String(randomInt(10000)).padStart(4,'0')]);
 await client.query('COMMIT');
 console.log('Neon schema ready');
} catch(e) { await client.query('ROLLBACK'); throw e; }
finally { client.release(); await pool.end(); }
