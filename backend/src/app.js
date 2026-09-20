import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import {rateLimit} from 'express-rate-limit';
import {z} from 'zod';
import {randomBytes,randomUUID,randomInt} from 'node:crypto';
import {hasArrived} from './arrival.js';
import {authenticate,hashPassword,checkPassword,tokenHash} from './auth.js';
import {adminAccount,accountLocation} from './account-validation.js';
import {fileURLToPath} from 'node:url';
const publicDirectory=fileURLToPath(new URL('../public/',import.meta.url));
const point = z.object({lat:z.number().min(-90).max(90),lng:z.number().min(-180).max(180)});
const requestSchema = point.partial().extend({equipment:z.enum(['5-finger excavator grapple','Pickup van','Big truck']),
 loading:z.enum(['Dyna','Trailer','Inside store']),store_number:z.string().regex(/^[0-9]{3}$/).optional(),
 offered_amount:z.string().regex(/^(?:[3-9][0-9]|[1-9][0-9]{2})$/),
 site_address:z.string().min(5).max(300).optional(),work_details:z.string().min(10).max(1000)});
const fail = (status,message) => { throw Object.assign(new Error(message),{status}); };
export async function transaction(pool, task) {
 const client=await pool.connect();
 try { await client.query('BEGIN'); const result=await task(client); await client.query('COMMIT'); return result; }
 catch(e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
}
export function createApp(pool, notify=()=>{}, options={}) {
 const app=express();
 // Render terminates HTTPS at its reverse proxy. Keep local requests untrusted.
 if (process.env.TRUST_PROXY_HOPS === '1') app.set('trust proxy',1);
 // The bundled Flutter UI needs WebAssembly and map/font fetches. Scope its
 // policy to /app so the admin panel retains Helmet's stricter defaults.
 app.use('/app',helmet({referrerPolicy:{policy:'strict-origin-when-cross-origin'},contentSecurityPolicy:{directives:{
   scriptSrc:["'self'","'wasm-unsafe-eval'","blob:"],
   connectSrc:["'self'",'https:','wss:'],
   imgSrc:["'self'",'https:','data:','blob:'],
   fontSrc:["'self'",'https:','data:'],
   workerSrc:["'self'",'blob:']
 }}}),express.static(fileURLToPath(new URL('../public/app/',import.meta.url)),{
   maxAge:0,setHeaders:res=>res.setHeader('Cache-Control','no-cache')
 }),(_req,res)=>res.sendStatus(404));
 app.use((req,res,next)=>{
   if(req.path==='/' || req.path==='/admin.html') return helmet({referrerPolicy:{policy:'strict-origin-when-cross-origin'},
     contentSecurityPolicy:{directives:{imgSrc:["'self'",'data:','https://tile.openstreetmap.org']}}})(req,res,next);
   helmet()(req,res,next);
 });
 const origins=(process.env.CORS_ORIGINS ?? 'http://localhost:8082').split(',');
 app.use(cors({origin:(origin,done)=>done(null,!origin || origins.includes(origin))}));
 app.use(express.json({limit:'16kb'}));
 app.use(express.static(publicDirectory));
 if (!options.testing) app.use(rateLimit({windowMs:60000,limit:180}));
 const authLimit=options.testing ? (_q,_s,n)=>n() : rateLimit({windowMs:15*60000,limit:20});
 app.get('/',(_req,res)=>res.sendFile('admin.html',{root:publicDirectory}));
 app.get('/health',async (_req,res)=>{ await pool.query('select 1'); res.json({ok:true}); });
 async function session(res,user) {
   const token=randomBytes(32).toString('hex');
   await pool.query("insert into sessions values($1,$2,now()+interval '7 days')",[tokenHash(token),user.id]);
   res.json({token,user:{id:user.id,email:user.email,name:user.name,phone:user.phone,username:user.username,
     role:user.role,service:user.service,store_number:user.store_number,site_lat:user.site_lat,site_lng:user.site_lng,site_address:user.site_address,online:user.online}});
 }
 app.post('/auth/register',authLimit,async(req,res)=>{
   fail(403,'Self-registration is disabled. Contact the admin to create your account.');
 });
 app.post('/auth/login',authLimit,async(req,res)=>{
   const body=z.object({email:z.string().trim().min(3).max(254).toLowerCase(),password:z.string().min(10).max(128),
     admin_only:z.boolean().optional(),expected_role:z.enum(['customer','operator']).optional()}).parse(req.body);
   const {rows}=await pool.query('select * from users where deleted_at is null and (email=$1 or username=$1)',[body.email]);
   if (!rows[0] || (body.admin_only === true && rows[0].role !== 'admin') ||
     (body.expected_role && rows[0].role !== body.expected_role) ||
     !await checkPassword(body.password,rows[0].password_hash)) fail(401,'Invalid username, password or account type');
   await session(res,rows[0]);
 });
 app.use(async(req,_res,next)=>{
   req.token=req.headers.authorization?.replace(/^Bearer /,'');
   req.user=await authenticate(pool,req.token);
   if (!req.user) fail(401,'Please sign in again');
   next();
 });
 app.get('/me',(req,res)=>res.json(req.user));
 app.use('/admin',(req,_res,next)=>{
   if(req.user.role!=='admin') fail(403,'Admin access required');
   next();
 });
 app.get('/admin/users',async(req,res)=>{
   const search=z.string().max(100).parse(req.query.search ?? '');
   const offset=z.coerce.number().int().min(0).max(10000000).parse(req.query.offset ?? 0);
   const {rows}=await pool.query(`select id,name,phone,username,email,role,service,store_number,site_lat,site_lng,site_address,online,blocked_until,deleted_at,
     (coalesce((select sum(amount) from work_charges where user_id=users.id),0)+
      coalesce((select sum(amount) from balance_adjustments where user_id=users.id),0))::integer as balance from users
     where role in ('customer','operator') and deleted_at is null and
     (coalesce(name,'') ilike $1 or coalesce(username,'') ilike $1 or coalesce(phone,'') ilike $1 or coalesce(email,'') ilike $1)
     order by (deleted_at is not null),coalesce(name,username,email),id limit 101 offset $2`,['%'+search+'%',offset]);
   res.json({users:rows.slice(0,100),has_more:rows.length>100});
 });
 app.get('/admin/dashboard',async(req,res)=>{
   const offset=z.coerce.number().int().min(0).max(10000000).parse(req.query.offset ?? 0);
   const {rows:totals}=await pool.query(`with balances as (
     select u.id,coalesce((select sum(amount) from work_charges where user_id=u.id),0)+
       coalesce((select sum(amount) from balance_adjustments where user_id=u.id),0) as balance
     from users u where role in ('customer','operator') and deleted_at is null)
     select (select count(*) from users where role='customer' and deleted_at is null) as customers,
       (select count(*) from users where role='operator' and deleted_at is null) as operators,
       (select count(*) from users where role='operator' and deleted_at is null and online=true) as online_operators,
       (select count(*) from jobs) as total_requests,
       (select count(*) from jobs where status='requested') as waiting_requests,
       (select count(*) from jobs where status in ('requested','accepted','on_the_way','working')) as active_jobs,
       (select count(*) from jobs where status='completed') as completed_jobs,
       (select coalesce(-sum(amount),0) from work_charges) as fees,
       (select coalesce(sum(amount),0) from balance_adjustments where kind='payment') as received,
       (select coalesce(sum(-balance),0) from balances where balance<0) as owed,
       (select coalesce(sum(balance),0) from balances where balance>0) as credit`);
   const {rows:activities}=await pool.query(`select a.*,coalesce(u.name,u.username,u.email) as account_name,
     u.role,coalesce(o.name,o.username,o.email) as operator_name from activity_log a
     left join users u on u.id=a.user_id left join jobs j on j.id=a.job_id
     left join users o on o.id=j.operator_id order by a.id desc limit 101 offset $1`,[offset]);
   res.json({totals:totals[0],activities:activities.slice(0,100),has_more:activities.length>100});
 });
 app.post('/admin/users/:id/balance',async(req,res)=>{
   const userId=z.uuid().parse(req.params.id);
   const b=z.object({id:z.uuid(),amount:z.number().int().min(-1000000).max(1000000).refine(v=>v!==0),
     reason:z.string().trim().min(3).max(300),kind:z.enum(['payment','adjustment']).default('adjustment')}).parse(req.body);
   if(b.kind==='payment' && b.amount<=0) fail(400,'A payment must add money');
   await transaction(pool,async c=>{
     const target=await c.query("select id from users where id=$1 and role in ('customer','operator')",[userId]);
     if(!target.rowCount) fail(404,'Account unavailable');
     await c.query('insert into balance_adjustments(id,user_id,admin_id,amount,reason,kind) values($1,$2,$3,$4,$5,$6) on conflict(id) do nothing',
       [b.id,userId,req.user.id,b.amount,b.reason,b.kind]);
     const previous=await c.query('select * from balance_adjustments where id=$1',[b.id]);
     const p=previous.rows[0];
     if(p.user_id!==userId || p.admin_id!==req.user.id || p.amount!==b.amount || p.reason!==b.reason || p.kind!==b.kind) fail(409,'Adjustment reference already used');
   });
   notify();res.json({ok:true});
 });
 app.post('/admin/users/:id/balance/set',async(req,res)=>{
   const userId=z.uuid().parse(req.params.id);
   const b=z.object({id:z.uuid(),balance:z.number().int().min(-1000000).max(1000000),
     reason:z.string().trim().min(3).max(300)}).parse(req.body);
   let amount=0;
   await transaction(pool,async c=>{
     const target=await c.query(`select id,(coalesce((select sum(amount) from work_charges where user_id=$1),0)+
       coalesce((select sum(amount) from balance_adjustments where user_id=$1),0))::integer as balance
       from users where id=$1 and role in ('customer','operator') and deleted_at is null for update`,[userId]);
     if(!target.rowCount) fail(404,'Account unavailable');
     amount=b.balance-Number(target.rows[0].balance);
     if(amount!==0) await c.query(`insert into balance_adjustments(id,user_id,admin_id,amount,reason,kind)
       values($1,$2,$3,$4,$5,'adjustment')`,[b.id,userId,req.user.id,amount,b.reason]);
   });
   notify();res.json({ok:true,balance:b.balance,adjustment:amount});
 });
 app.get('/admin/users/:id/balance',async(req,res)=>{
   const id=z.uuid().parse(req.params.id);
   const {rows}=await pool.query(`select amount,reason,created_at,admin_id from balance_adjustments where user_id=$1
     union all select amount,case when amount=-2 then 'Cancellation fee' else 'Completed work fee' end as reason,
       created_at,null::uuid as admin_id from work_charges where user_id=$1
     order by created_at desc limit 100`,[id]);
   res.json({entries:rows});
 });
 app.post('/admin/users/:id/clear-restriction',async(req,res)=>{
   const id=z.uuid().parse(req.params.id);
   const result=await pool.query("update users set blocked_until=null where id=$1 and role in ('customer','operator')",[id]);
   if(!result.rowCount) fail(404,'Account unavailable');
   notify();res.json({ok:true});
 });
 app.get('/admin/users/:id/jobs',async(req,res)=>{
   const id=z.uuid().parse(req.params.id);
   const account=await pool.query("select id from users where id=$1 and role in ('customer','operator')",[id]);
   if(!account.rowCount) fail(404,'Account unavailable');
   const {rows}=await pool.query(`select id,request_number,closed_at,service,loading_vehicle,offered_amount,status,created_at,
     case when customer_id=$1 then 'customer' else 'operator' end as participation
     from jobs where customer_id=$1 or operator_id=$1 order by created_at desc`,[id]);
   res.json({jobs:rows,completed:rows.filter(row=>row.status==='completed').length,total:rows.length});
 });
 app.delete('/admin/users/:id',async(req,res)=>{
   const id=z.uuid().parse(req.params.id);
   await transaction(pool,async c=>{
     const account=await c.query("select id from users where id=$1 and role in ('customer','operator') for update",[id]);
     if(!account.rowCount) fail(404,'Account unavailable');
     await c.query(`update jobs set status='cancelled' where (customer_id=$1 or operator_id=$1)
       and status in ('requested','accepted','on_the_way','working')`,[id]);
     await c.query(`delete from job_start_codes where job_id in
       (select id from jobs where (customer_id=$1 or operator_id=$1) and status='cancelled')`,[id]);
     await c.query(`delete from notification_outbox where job_id in
       (select id from jobs where (customer_id=$1 or operator_id=$1) and status='cancelled')`,[id]);
     await c.query('delete from sessions where user_id=$1',[id]);
     await c.query('delete from declines where operator_id=$1',[id]);
     await c.query('delete from work_charges where user_id=$1',[id]);
     await c.query('delete from balance_adjustments where user_id=$1',[id]);
     await c.query('update activity_log set user_id=null where user_id=$1',[id]);
     await c.query('update jobs set customer_id=null where customer_id=$1',[id]);
     await c.query('update jobs set operator_id=null where operator_id=$1',[id]);
     await c.query('delete from users where id=$1',[id]);
   });
   notify();res.json({ok:true});
 });
 app.post('/admin/users',async(req,res)=>{
   const body=adminAccount.parse(req.body);
   const hash=await hashPassword(body.password);
   const {rows}=await pool.query(`insert into users(id,name,phone,username,password_hash,role,service,store_number,site_lat,site_lng,site_address)
     values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) returning id,name,phone,username,role,service,store_number,site_lat,site_lng,site_address`,
     [randomUUID(),body.name,body.phone,body.username,hash,body.role,body.role==='operator'?body.service:null,body.role==='customer'?body.store_number:null,body.role==='customer'?body.site_lat:null,body.role==='customer'?body.site_lng:null,body.role==='customer'?body.site_address:null]);
   res.status(201).json({user:rows[0]});
 });
 app.post('/admin/users/:id/location',async(req,res)=>{
   const id=z.uuid().parse(req.params.id),location=accountLocation.parse(req.body);
   const {rows}=await pool.query(`update users set site_lat=$2,site_lng=$3,site_address=$4
     where id=$1 and role='customer' and deleted_at is null and site_lat is null and site_lng is null
     returning id,site_lat,site_lng,site_address`,[id,location.site_lat,location.site_lng,location.site_address]);
   if(!rows.length) fail(409,'Location is already fixed or the customer account is unavailable.');
   notify();res.json({user:rows[0]});
 });
 app.post('/admin/users/:id/store-number',async(req,res)=>{
   const id=z.uuid().parse(req.params.id);
   const {store_number}=z.object({store_number:z.string().regex(/^[0-9]{3}$/)}).parse(req.body);
   const {rows}=await pool.query(`update users set store_number=$2
     where id=$1 and role='customer' and deleted_at is null and store_number is null
     returning id,store_number`,[id,store_number]);
   if(!rows.length) fail(409,'Store number is already fixed or the customer account is unavailable.');
   notify();res.json({user:rows[0]});
 });
 app.post('/auth/logout',async(req,res)=>{
   await transaction(pool,async c=>{
     await c.query('delete from sessions where token_hash=$1',[tokenHash(req.token)]);
     await c.query('update users set online=false where id=$1',[req.user.id]);
   });
   notify(); res.json({ok:true});
 });
 app.put('/availability',async(req,res)=>{
   if(req.user.role!=='operator') fail(403,'Operator account required');
   const {available}=z.object({available:z.boolean()}).parse(req.body);
   if(available && new Date(req.user.blocked_until)>new Date()) fail(403,'Work is paused until '+new Date(req.user.blocked_until).toISOString());
   if(available) {
     const {rows}=await pool.query(`select coalesce((select sum(amount) from work_charges where user_id=$1),0)+
       coalesce((select sum(amount) from balance_adjustments where user_id=$1),0) as balance`,[req.user.id]);
     if(Number(rows[0].balance)<=-20) fail(403,'Payment required. Pay your balance to receive new requests.');
   }
   await pool.query('update users set online=$1 where id=$2',[available,req.user.id]);
   notify();res.json({ok:true});
 });
 app.get('/jobs',async(req,res)=>{
   const u=req.user;
   const balanceResult=await pool.query(`select (coalesce((select sum(amount) from work_charges where user_id=$1),0)+
     coalesce((select sum(amount) from balance_adjustments where user_id=$1),0))::integer as balance`,[u.id]);
   const balance=Number(balanceResult.rows[0].balance);
   const {rows}=await pool.query(`select j.*,
    case when j.customer_id=$1 or j.operator_id=$1 then s.address else null end as address,
    case when j.customer_id=$1 or j.operator_id=$1 then s.store_number else null end as store_number,
    case when j.customer_id=$1 and j.status in ('accepted','on_the_way') then codes.code else null end as start_otp,
    customer.phone as private_customer_phone,s.lat as private_site_lat,s.lng as private_site_lng,
    loc.lat as private_operator_lat,loc.lng as private_operator_lng,loc.updated_at as private_location_updated
    from jobs j join job_sites s on s.job_id=j.id
    left join users customer on customer.id=j.customer_id
    left join job_start_codes codes on codes.job_id=j.id
    left join job_locations loc on loc.job_id=j.id
    where (j.status not in ('completed','cancelled') or j.closed_at>now()-interval '3 days')
    and (j.customer_id=$1 or j.operator_id=$1 or
    ($2='operator' and $4 and not exists(select 1 from users where id=$1 and blocked_until>now()) and j.status='requested' and j.service=$3 and j.customer_id<>$1 and
     not exists(select 1 from jobs active where active.operator_id=$1 and active.status in ('accepted','on_the_way','working')) and
     not exists(select 1 from declines d where d.job_id=j.id and d.operator_id=$1)))
    order by j.created_at desc`,[u.id,u.role,u.service,balance>-20]);
   const jobs=rows.map(row=>{
     const {private_customer_phone,private_site_lat,private_site_lng,private_operator_lat,
       private_operator_lng,private_location_updated,...job}=row;
     const arrived=job.operator_id===u.id && ['accepted','on_the_way','working'].includes(job.status) &&
       hasArrived({lat:private_site_lat,lng:private_site_lng},private_operator_lat===null?null:
         {lat:private_operator_lat,lng:private_operator_lng,updated_at:private_location_updated});
     return {...job,customer_phone:arrived?private_customer_phone:null};
   });
   res.json({jobs,store_number:u.store_number,site_lat:u.site_lat,site_lng:u.site_lng,site_address:u.site_address,online:u.online,balance,blocked_until:u.blocked_until,payment_required:balance<=-20});
 });
 app.post('/jobs',async(req,res)=>{
   if(req.user.role!=='customer') fail(403,'Customer account required');
   const b=requestSchema.parse(req.body),id=randomUUID();
   await transaction(pool,async c=>{
    const account=await c.query(`select blocked_until,store_number,site_lat,site_lng,site_address,
      coalesce((select sum(amount) from work_charges where user_id=$1),0)+
      coalesce((select sum(amount) from balance_adjustments where user_id=$1),0) as balance
      from users where id=$1 for update`,[req.user.id]);
    const site=account.rows[0];
    if(site.site_lat===null || site.site_lng===null || !site.site_address) fail(403,'Contact admin to assign your account location.');
    if((b.lat!==undefined && b.lat!==site.site_lat) || (b.lng!==undefined && b.lng!==site.site_lng) ||
      (b.site_address!==undefined && b.site_address!==site.site_address)) fail(400,'Work location is fixed to your account.');
    if(!account.rows[0].store_number) fail(403,'Contact admin to assign your account store number.');
    if(b.store_number !== undefined && b.store_number !== account.rows[0].store_number) fail(400,'Store number is fixed to your account.');
    if(new Date(account.rows[0].blocked_until)>new Date()) fail(403,'New requests are paused until '+new Date(account.rows[0].blocked_until).toISOString());
    if(Number(account.rows[0].balance)<=-20) fail(403,'Payment required. Pay your balance before making a new request.');
    await c.query(`insert into jobs(id,customer_id,service,loading_vehicle,offered_amount,details)
      values($1,$2,$3,$4,$5,$6)`,[id,req.user.id,b.equipment,b.loading,b.offered_amount,b.work_details]);
    await c.query('insert into job_sites values($1,$2,$3,$4,$5)',[id,site.site_address,site.store_number,site.site_lat,site.site_lng]);
    await c.query('insert into notification_outbox(id,job_id) values($1,$2)',[randomUUID(),id]);
   });
   notify();res.status(201).json({id});
 });
 app.post('/jobs/:id/action',async(req,res)=>{
   const id=z.uuid().parse(req.params.id);
   const {action,otp}=z.object({action:z.enum(['accept','decline','cancel','travel','start','complete']),otp:z.string().max(20).optional()}).parse(req.body);
   const actionError=await transaction(pool,async c=>{
    const {rows}=await c.query('select * from jobs where id=$1 for update',[id]);
    const j=rows[0],u=req.user;
    if(!j) fail(404,'Request unavailable');
    if(action==='cancel') {
      if(!['requested','accepted','on_the_way'].includes(j.status) ||
        !(j.customer_id===u.id || j.operator_id===u.id)) fail(409,'Only participants can cancel before work starts');
      await c.query("update jobs set status='cancelled' where id=$1",[id]);
      await c.query(`insert into work_charges(job_id,user_id,amount) values($1,$2,-2)
        on conflict(job_id,user_id) do nothing`,[id,u.id]);
      await c.query(`update users set blocked_until=now()+($2 * interval '1 hour'),
        online=case when role='operator' then false else online end where id=$1`,[u.id,j.customer_id===u.id?72:5]);
      await c.query('delete from job_start_codes where job_id=$1',[id]);
      return;
    }
    if(u.role!=='operator') fail(403,'Approved operator account required');
    if(['accept','decline'].includes(action)) {
      if(j.status!=='requested' || j.customer_id===u.id || j.service!==u.service) fail(409,'Request no longer available');
      if(action==='decline') { await c.query('insert into declines values($1,$2) on conflict do nothing',[id,u.id]); return; }
      if(!u.online) fail(409,'Go online first');
      const account=await c.query(`select blocked_until,
        coalesce((select sum(amount) from work_charges where user_id=$1),0)+
        coalesce((select sum(amount) from balance_adjustments where user_id=$1),0) as balance
        from users where id=$1 for update`,[u.id]);
      if(new Date(account.rows[0].blocked_until)>new Date()) fail(403,'Work acceptance is temporarily paused');
      if(Number(account.rows[0].balance)<=-20) fail(403,'Payment required. Pay your balance to receive new requests.');
      const declined=await c.query('select 1 from declines where job_id=$1 and operator_id=$2',[id,u.id]);
      if(declined.rowCount) fail(409,'You declined this request');
      await c.query("update jobs set operator_id=$1,status='accepted' where id=$2",[u.id,id]);
      await c.query('insert into job_start_codes(job_id,code) values($1,$2)',[id,String(randomInt(10000)).padStart(4,'0')]);
      return;
    }
    if(j.operator_id!==u.id) fail(403,'This is not your job');
    const transitions={travel:['accepted','on_the_way'],start:['on_the_way','working'],complete:['working','completed']};
    const [from,to]=transitions[action];
    if(j.status!==from) fail(409,'Invalid work status change');
    if(action==='start' || action==='complete') {
      const {rows:sites}=await c.query('select * from job_sites where job_id=$1',[id]);
      const {rows:locations}=await c.query('select * from job_locations where job_id=$1',[id]);
      if(!hasArrived(sites[0],locations[0])) fail(409,'Arrive within 100 metres of the work site and update your GPS location first');
    }
    if(action==='start') {
      const {rows:codes}=await c.query('select * from job_start_codes where job_id=$1',[id]);
      const secret=codes[0];
      if(!secret) fail(409,'Start code unavailable. Contact support.');
      const reset=Date.now()-new Date(secret.window_started).getTime()>=60000;
      if(!reset && secret.failures>=5) fail(429,'Too many incorrect codes. Try again in one minute');
      if(!/^[0-9]{4}$/.test(otp ?? '') || otp!==secret.code) {
        await c.query(`update job_start_codes set failures=$2,
          window_started=case when $3 then now() else window_started end where job_id=$1`,[id,reset?1:secret.failures+1,reset]);
        return 'Incorrect four-digit customer OTP';
      }
      await c.query('delete from job_start_codes where job_id=$1',[id]);
    }
    await c.query('update jobs set status=$1 where id=$2',[to,id]);
    if(action==='complete') {
      await c.query(`insert into work_charges(job_id,user_id,amount) values($1,$2,-4),($1,$3,-4)
        on conflict(job_id,user_id) do nothing`,[id,j.customer_id,j.operator_id]);
    }
   });
   if(actionError) fail(400,actionError);
   notify();res.json({ok:true});
 });
 app.get('/jobs/:id/location',async(req,res)=>{
   const id=z.uuid().parse(req.params.id);
   const {rows}=await pool.query(`select s.*,l.lat as operator_lat,l.lng as operator_lng,l.updated_at
    from jobs j join job_sites s on s.job_id=j.id left join job_locations l on l.job_id=j.id
    where j.id=$1 and j.status in ('accepted','on_the_way','working') and (j.customer_id=$2 or j.operator_id=$2)`,[id,req.user.id]);
   const row=rows[0];if(!row) fail(404,'Location unavailable');
   res.json({site:{lat:row.lat,lng:row.lng,address:row.address,store_number:row.store_number},
     position:row.operator_lat===null ? null : {lat:row.operator_lat,lng:row.operator_lng,updated_at:row.updated_at}});
 });
 app.put('/jobs/:id/location',async(req,res)=>{
   const id=z.uuid().parse(req.params.id),b=point.parse(req.body);
   await transaction(pool,async c=>{
     const {rowCount}=await c.query(`select id from jobs where id=$1 and operator_id=$2
       and status in ('accepted','on_the_way','working') for update`,[id,req.user.id]);
     if(!rowCount) fail(403,'Only your active job location can be updated');
     await c.query(`insert into job_locations values($1,$2,$3,now()) on conflict(job_id)
       do update set lat=excluded.lat,lng=excluded.lng,updated_at=now()`,[id,b.lat,b.lng]);
   });
   notify();res.json({ok:true});
 });
 app.use((error,_req,res,_next)=>{
   if(error instanceof z.ZodError) return res.status(400).json({error:'Check required fields: '+error.issues.map(i=>i.path.join('.')).join(', ')});
   if(error.code==='23505') return res.status(409).json({error:'Account already exists or an active job conflicts with this request'});
   if(error.code==='23514') return res.status(400).json({error:'Invalid work details'});
   const status=error.status || 500;
   res.status(status).json({error:status<500 ? error.message : 'Server error. Please try again.'});
 });
 return app;
}
