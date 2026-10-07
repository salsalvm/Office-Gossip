import { onRequest } from 'firebase-functions/v2/https';
import { app } from './app.js';

// Values live in Secret Manager: `firebase functions:secrets:set <NAME> --project office-gossip`.
const secrets = ['SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'ADMIN_EMAIL', 'ADMIN_PASSWORD', 'ADMIN_TOKEN_SECRET'];

export const api = onRequest({ region: 'asia-south1', minInstances: 1, memory: '512MiB', timeoutSeconds: 60, concurrency: 80, secrets }, app);
