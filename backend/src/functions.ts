import { onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { adminClient, app } from './app.js';
import { purgeDueAccounts } from './services/accounts.js';

// Values live in Secret Manager: `firebase functions:secrets:set <NAME> --project office-gossip`.
const secrets = ['SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'ADMIN_EMAIL', 'ADMIN_PASSWORD', 'ADMIN_TOKEN_SECRET', 'SMTP_PASS'];

export const api = onRequest({ region: 'asia-south1', minInstances: 1, memory: '512MiB', timeoutSeconds: 60, concurrency: 80, secrets }, app);

// Permanently deletes accounts whose deletion grace period has ended.
export const purgeDeletedAccounts = onSchedule({ schedule: 'every day 03:00', timeZone: 'Asia/Kolkata', region: 'asia-south1', timeoutSeconds: 540, secrets: ['SUPABASE_SERVICE_ROLE_KEY'] }, async () => {
  const { purged, failed } = await purgeDueAccounts(adminClient(), 5000);
  console.log(`Purged ${purged} deleted account(s)${failed ? `, ${failed} failed` : ''}.`);
});
