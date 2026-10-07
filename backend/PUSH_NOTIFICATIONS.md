# Push notification setup

The web client obtains an FCM registration token after the signed-in user chooses **Enable push** in Profile. The API stores it in `public.user_devices` and sends push messages for new company posts, comments, and reactions. Notification preference flags are checked before sending. Invalid device registrations are removed after FCM reports them as expired.

## Supabase

Apply `../database/scheme.sql` from the repository root if it has not already been run. It creates `notification_preferences` and `user_devices`.

Set `SUPABASE_SERVICE_ROLE_KEY` in `backend/.env.local`. Keep this key server-side; never add it to the frontend. The API uses it to store device registrations and read company membership/preferences.

## Firebase Cloud Messaging

1. In Firebase Console, open **Project settings → Cloud Messaging** and enable the Cloud Messaging API if it is not enabled.
2. Under **Web configuration → Web Push certificates**, generate a VAPID key pair.
3. Set the public key as `VITE_FIREBASE_VAPID_KEY` in `frontend-web/.env.local`. The other public Firebase web config values are already in `frontend-web/.env.example`.
4. Keep the service account JSON outside the repository. Locally, `backend/.env.local` points `GOOGLE_APPLICATION_CREDENTIALS` at the supplied file. In production, provide the credential through the hosting platform's secret manager or workload identity instead of using this local path.
5. Restart the backend and frontend. Serve the web app over HTTPS outside localhost; service workers and web push require a secure origin.

The current Flutter app is a UI preview without authentication or API calls, so it does not yet register mobile devices. The API accepts `ios` and `android` device registrations once the mobile app is connected to Supabase Auth and Firebase Messaging.
