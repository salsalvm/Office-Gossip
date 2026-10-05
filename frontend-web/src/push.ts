import { getApps, initializeApp } from 'firebase/app';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
};
const vapidKey = import.meta.env.VITE_FIREBASE_VAPID_KEY;

async function getPushClient() {
  if (!('Notification' in window) || !('serviceWorker' in navigator)) {
    throw new Error('Push notifications are not supported in this browser.');
  }
  if (!vapidKey) throw new Error('Set VITE_FIREBASE_VAPID_KEY from Firebase Console to enable web push.');
  if (!firebaseConfig.apiKey || !firebaseConfig.projectId || !firebaseConfig.messagingSenderId || !firebaseConfig.appId) {
    throw new Error('Firebase web configuration is incomplete.');
  }
  const sdk = await import('firebase/messaging');
  if (!(await sdk.isSupported())) throw new Error('Firebase push is not supported in this browser.');
  const app = getApps()[0] ?? initializeApp(firebaseConfig);
  return { sdk, messaging: sdk.getMessaging(app) };
}

export async function requestWebPushToken(): Promise<string> {
  const { sdk, messaging } = await getPushClient();
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') throw new Error('Allow notifications in your browser to enable push.');
  const serviceWorkerRegistration = await navigator.serviceWorker.register('/firebase-messaging-sw.js');
  const token = await sdk.getToken(messaging, { vapidKey, serviceWorkerRegistration });
  if (!token) throw new Error('Firebase did not return a registration token.');
  return token;
}

export async function listenForPushMessages(
  listener: (message: { title?: string; body?: string }) => void,
): Promise<() => void> {
  const { sdk, messaging } = await getPushClient();
  return sdk.onMessage(messaging, (payload) => listener({
    title: payload.notification?.title,
    body: payload.notification?.body,
  }));
}

export async function removeWebPushToken(): Promise<string | null> {
  const { sdk, messaging } = await getPushClient();
  if (Notification.permission !== 'granted') return null;
  const token = await sdk.getToken(messaging, { vapidKey });
  if (token) await sdk.deleteToken(messaging);
  return token || null;
}
