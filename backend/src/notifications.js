import {transaction} from './app.js';
export function startNotifications(pool) {
 if (!process.env.ONESIGNAL_APP_ID || !process.env.ONESIGNAL_REST_API_KEY) {
   console.log('Phone push disabled: configure OneSignal server secrets to enable it.');return ()=>{};
 }
 let running=false;
 const timer=setInterval(async()=>{
  if(running)return;running=true;
  try { await transaction(pool,async c=>{
    const {rows}=await c.query(`select * from notification_outbox where sent_at is null
      and attempts<8 and next_attempt<=now() order by next_attempt for update skip locked limit 1`);
    const event=rows[0];if(!event)return;
    const {rows:jobs}=await c.query('select * from jobs where id=$1',[event.job_id]);
    const job=jobs[0];
    if(job.status!=='requested') {await c.query('update notification_outbox set sent_at=now() where id=$1',[event.id]);return;}
    const {rows:operators}=await c.query(`select id from users where role='operator' and service=$1 and online=true
      and (blocked_until is null or blocked_until<=now())
      and not exists(select 1 from declines d where d.operator_id=users.id and d.job_id=$2)
      and not exists(select 1 from jobs j where j.operator_id=users.id and j.status in ('accepted','on_the_way','working'))`,[job.service,job.id]);
    try {
      if(!operators.length) {await c.query("update notification_outbox set next_attempt=now()+interval '30 seconds' where id=$1",[event.id]);return;}
      if(operators.length>20000)throw new Error('Recipient batching required');
      const response=await fetch('https://api.onesignal.com/notifications',{method:'POST',signal:AbortSignal.timeout(10000),
        headers:{'Content-Type':'application/json',Authorization:`Key ${process.env.ONESIGNAL_REST_API_KEY}`},
        body:JSON.stringify({app_id:process.env.ONESIGNAL_APP_ID,target_channel:'push',
         include_aliases:{external_id:operators.map(o=>o.id)},idempotency_key:event.id,
         headings:{en:'New Buklin work order'},
         contents:{en:`${job.service} • ${job.loading_vehicle} • Customer offer: ${Number(job.offered_amount).toFixed(0)} Riyal. Open to accept.`},
         data:{job_id:job.id}})});
      const result=await response.json();if(!response.ok || !result.id)throw new Error('Push rejected');
      await c.query('update notification_outbox set sent_at=now() where id=$1',[event.id]);
    }catch(_){await c.query("update notification_outbox set attempts=attempts+1,next_attempt=now()+interval '60 seconds' where id=$1",[event.id]);}
  }); }catch(_){console.error('Notification worker unavailable; retrying.');}finally{running=false;}
 },5000);
 timer.unref();return ()=>clearInterval(timer);
}
