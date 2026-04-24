/**
 * reminder-dispatch — service-role worker: send pending reminder_jobs
 *
 * Invoke via pg_cron with service role, or manual POST with
 * Header: Authorization: Bearer SERVICE_ROLE_KEY
 *
 * Optional secrets: RESEND_API_KEY, TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const authHeader = req.headers.get('authorization') ?? '';
  const jwt = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';
  if (!serviceKey || jwt !== serviceKey) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }

  const svc = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const now = new Date().toISOString();

  const { data: jobs, error: qerr } = await svc
    .from('reminder_jobs')
    .select('id, channel, payload, user_id')
    .eq('status', 'pending')
    .lte('scheduled_at', now)
    .limit(50);

  if (qerr) {
    return new Response(JSON.stringify({ error: qerr.message }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }

  const resendKey = Deno.env.get('RESEND_API_KEY');
  const twilioSid = Deno.env.get('TWILIO_ACCOUNT_SID');
  const twilioToken = Deno.env.get('TWILIO_AUTH_TOKEN');
  const twilioFrom = Deno.env.get('TWILIO_FROM_NUMBER');

  let sent = 0;
  let skipped = 0;

  for (const job of jobs ?? []) {
    const id = job.id as string;
    const channel = job.channel as string;
    const payload = (job.payload ?? {}) as Record<string, string>;
    const toEmail = payload.to_email;
    const toPhone = payload.to_phone;
    const subject = payload.subject ?? 'Huddle reminder';
    const bodyText = payload.body ?? '';

    try {
      if (channel === 'email' && resendKey && toEmail) {
        const r = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${resendKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: 'Huddle <onboarding@resend.dev>',
            to: [toEmail],
            subject,
            text: bodyText,
          }),
        });
        if (!r.ok) throw new Error(await r.text());
        await svc.from('reminder_jobs').update({ status: 'sent' }).eq('id', id);
        sent++;
      } else if (channel === 'sms' && twilioSid && twilioToken && twilioFrom && toPhone) {
        const auth = btoa(`${twilioSid}:${twilioToken}`);
        const form = new URLSearchParams({ To: toPhone, From: twilioFrom, Body: bodyText });
        const r = await fetch(
          `https://api.twilio.com/2010-04-01/Accounts/${twilioSid}/Messages.json`,
          {
            method: 'POST',
            headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
            body: form.toString(),
          },
        );
        if (!r.ok) throw new Error(await r.text());
        await svc.from('reminder_jobs').update({ status: 'sent' }).eq('id', id);
        sent++;
      } else if (channel === 'voice' && twilioSid && twilioToken && twilioFrom && toPhone) {
        const auth = btoa(`${twilioSid}:${twilioToken}`);
        const twiml = `<Response><Say>${bodyText.replace(/&/g, 'and')}</Say></Response>`;
        const form = new URLSearchParams({
          To: toPhone,
          From: twilioFrom,
          Twiml: twiml,
        });
        const r = await fetch(
          `https://api.twilio.com/2010-04-01/Accounts/${twilioSid}/Calls.json`,
          {
            method: 'POST',
            headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
            body: form.toString(),
          },
        );
        if (!r.ok) throw new Error(await r.text());
        await svc.from('reminder_jobs').update({ status: 'sent' }).eq('id', id);
        sent++;
      } else {
        await svc.from('reminder_jobs').update({ status: 'failed' }).eq('id', id);
        skipped++;
      }
    } catch {
      await svc.from('reminder_jobs').update({ status: 'failed' }).eq('id', id);
      skipped++;
    }
  }

  return new Response(JSON.stringify({ processed: (jobs ?? []).length, sent, skipped }), {
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
});
