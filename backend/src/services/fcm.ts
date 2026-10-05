import { applicationDefault, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging, type MulticastMessage } from 'firebase-admin/messaging';
import { createClient } from '@supabase/supabase-js';

function db() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error('Supabase database access is not configured');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

function messaging() {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    throw new Error('Firebase messaging is not configured. Set GOOGLE_APPLICATION_CREDENTIALS.');
  }
  const app = getApps()[0] ?? initializeApp({
    credential: process.env.FIREBASE_SERVICE_ACCOUNT_JSON
      ? cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON))
      : applicationDefault(),
    projectId: process.env.FIREBASE_PROJECT_ID || 'office-gossip',
  });
  return getMessaging(app);
}

export type NotificationCategory = 'comments' | 'reactions' | 'company_updates';
export async function sendUserNotification(input: {
  userId: string;
  category: NotificationCategory;
  title: string;
  body: string;
  data?: Record<string, string>;
}) {
  const client = db();
  const [{ data: preferences, error: prefError }, { data: devices, error: devicesError }] = await Promise.all([
    client.from('notification_preferences').select('comments,reactions,company_updates').eq('user_id', input.userId).maybeSingle(),
    client.from('user_devices').select('id,push_token').eq('user_id', input.userId),
  ]);
  if (prefError) throw prefError;
  if (devicesError) throw devicesError;
  if (preferences?.[input.category] === false || !devices?.length) return { sent: 0 };

  const fcm = messaging();
  let sent = 0;
  let failed = 0;
  const expiredIds: string[] = [];
  for (let offset = 0; offset < devices.length; offset += 500) {
    const batch = devices.slice(offset, offset + 500);
    const message: MulticastMessage = {
      tokens: batch.map((device) => device.push_token),
      notification: { title: input.title, body: input.body },
      data: input.data ?? {},
      webpush: { notification: { title: input.title, body: input.body, icon: '/favicon.svg' } },
    };
    const result = await fcm.sendEachForMulticast(message);
    sent += result.successCount;
    failed += result.failureCount;
    result.responses.forEach((response, index) => {
      const code = response.error?.code;
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
        expiredIds.push(batch[index].id);
      }
    });
  }
  if (expiredIds.length) {
    const { error } = await client.from('user_devices').delete().in('id', expiredIds);
    if (error) throw error;
  }
  return { sent, failed };
}

export async function notifyCompanyMembers(input: {
  companyId: string;
  excludeUserId: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}) {
  const client = db();
  const { data: memberships, error } = await client.from('company_memberships').select('user_id')
    .eq('company_id', input.companyId).eq('status', 'active').neq('user_id', input.excludeUserId);
  if (error) throw error;
  const recipients = (memberships ?? []).map((row) => row.user_id);
  for (let offset = 0; offset < recipients.length; offset += 50) {
    await Promise.all(recipients.slice(offset, offset + 50).map((userId) => sendUserNotification({
      userId,
      category: 'company_updates',
      title: input.title,
      body: input.body,
      data: input.data,
    })));
  }
}
