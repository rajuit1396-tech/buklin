// Database webhook: INSERT public.work_notifications -> this function.
// Deploy with --no-verify-jwt; authentication uses a dedicated webhook secret.
import { createClient } from 'npm:@supabase/supabase-js@2';
Deno.serve(async (request: Request) => {
  const secret = Deno.env.get('WORK_WEBHOOK_SECRET');
  if (!secret || request.headers.get('x-work-secret') !== secret) return new Response('Unauthorized', {status: 401});
  if (request.method !== 'POST') return new Response('Method not allowed', {status: 405});
  try {
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const body = await request.json();
    const {data: event, error: eventError} = await db.from('work_notifications').select('*').eq('id', body.record?.id).single();
    if (eventError || !event) return new Response('Unknown event', {status: 404});
    if (event.sent_at) return new Response('Already processed');
    const {data: job, error: jobError} = await db.from('jobs').select('id,status,service,loading_vehicle,offered_amount').eq('id',event.job_id).single();
    if (jobError) throw jobError;
    if (job.status !== 'requested') return new Response('No longer available');
    const {data: operators, error} = await db.from('operator_availability').select('operator_id')
      .eq('service', job.service).eq('online', true);
    if (error) throw error;
    const ids = operators.map(o => o.operator_id);
    if (ids.length === 0) return new Response('No online operators');
    if (ids.length > 20000) throw new Error('Recipient batching required');
    const appId = Deno.env.get('ONESIGNAL_APP_ID');
    const key = Deno.env.get('ONESIGNAL_REST_API_KEY');
    if (!appId || !key) throw new Error('Push configuration missing');
    const response = await fetch('https://api.onesignal.com/notifications', {
      method: 'POST', headers: {'Content-Type': 'application/json', Authorization: `Key ${key}`},
      body: JSON.stringify({app_id: appId, target_channel: 'push',
        include_aliases: {external_id: ids},
        headings: {en: 'New Buklin work order'},
        contents: {en: `${job.service} • Loading: ${job.loading_vehicle} • Customer offer: ${job.offered_amount == null ? 'Not specified' : Number(job.offered_amount).toFixed(2)}. Open to accept.`},
        data: {job_id: job.id}, idempotency_key: event.id}),
    });
    const result = await response.json();
    if (!response.ok || !result.id) throw new Error('Push provider did not accept notification');
    const {error: updateError} = await db.from('work_notifications').update({sent_at: new Date().toISOString()}).eq('id',event.id);
    if (updateError) throw updateError;
    return Response.json({sent: true});
  } catch (_) { return new Response('Notification delivery failed; retry this event', {status: 500}); }
});
