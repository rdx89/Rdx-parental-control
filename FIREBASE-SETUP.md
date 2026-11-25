# RDX SafeGuard cloud setup

The two Android apps use one Firebase project for Authentication and FCM. The
Worker API and command database are hosted on Cloudflare. This build uses
Firebase Spark and Cloudflare Workers/D1 Free.

## Firebase

1. Register `com.safeguard.app.parent` and `com.safeguard.app.child` as separate
   Android apps in the same Firebase project.
2. Store their Android configurations in GitHub Actions as
   `FIREBASE_PARENT_CONFIG` and `FIREBASE_CHILD_CONFIG`.
3. Deploy the Firebase Authentication settings from `firebase.json` with
   `firebase deploy --only auth --project YOUR_PROJECT_ID`. Parent uses a
   server-generated login alias internally and the UI asks for a mobile number
   and password. Child uses anonymous Firebase auth.
4. Configure the Worker to send push notifications using a service account
   limited to the Firebase project's Cloud Messaging API. Store its JSON in the
   Worker secret `FCM_ACCOUNT`.

## Cloudflare

1. Create a D1 database and put its identifier in `worker/wrangler.jsonc`.
2. Apply the D1 migrations and deploy the Worker as described in the README.
3. Configure `FIREBASE_API_KEY` and `LOGIN_ALIAS_SECRET` as Worker secrets. Keep
   the alias secret stable because changing it changes the account lookup.
4. Set GitHub Actions repository variable `SAFEGUARD_API_URL` to the HTTPS
   Worker address and dispatch **Build SafeGuard APKs**.

The current deployments use Firebase `safeguard-4c4fa` and Cloudflare Worker
`https://rdx-safeguard.afe-uard.workers.dev`. The GitHub workflow includes that
URL in each debug-signed APK. The legacy Firebase Cloud Functions code is
available in `functions/` for the earlier Firestore architecture.
