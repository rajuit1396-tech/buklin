# Buklin — Flutter + Node.js + Neon

The active backend is now `backend/`: a Node.js REST/WebSocket API with Neon
Postgres storage. Flutter no longer uses Supabase. The `supabase/` directory is
retained only as historical migration material; do not apply it to Neon.

## Preview in Chrome

For hosted deployment of the login app and API, see [RENDER.md](RENDER.md).

```powershell
C:\flutter\bin\flutter.bat run -d chrome --web-port 8082
```

Without BACKEND_URL the app runs the labeled, in-memory customer/operator demo.

## Run with Neon

1. Install Node.js LTS (22 or newer).
2. Create a Neon project. Copy `backend/.env.example` to `backend/.env` and set
   DATABASE_URL to your Neon Postgres connection string. Keep it private: never
   put it in Flutter code, a dart-define, GitHub, or chat. Use TLS verification.
3. From `backend`, run:

```powershell
npm install
npm run migrate
npm start
```

4. From the project root:

```powershell
C:\flutter\bin\flutter.bat run -d chrome --web-port 8082 --dart-define=BACKEND_URL=http://localhost:3000
```

5. Create customer accounts in the app. To approve an existing account as an
   operator, run from `backend`:

```powershell
npm run operator -- operator@example.com "Pickup van"
```

Use exactly `Pickup van`, `Big truck`, or `5-finger excavator grapple`. Sign in
again as the operator, then go online. Customers cannot grant themselves roles.
Accounts require passwords of 10–128 characters. Sessions are kept in app memory;
refreshing the browser requires signing in again. Password recovery and email
verification are not implemented yet.

## Phone alerts

Set ONESIGNAL_APP_ID and ONESIGNAL_REST_API_KEY in backend/.env. Launch the Android
app with BACKEND_URL and ONESIGNAL_APP_ID dart defines. Configure Android/FCM in
OneSignal, enable notification permission in the app, and go online. Keep the API
server running: its outbox worker retries failed messages up to eight times.
Monitor notification_outbox for exhausted attempts. No Google/OneSignal credentials
have been provisioned here. Phone notification delivery remains unverified.

Going online requests notification permission. Incoming requests use native Android
sound and vibration in the foreground and the `buklin_work_v1` notification channel
for background push alerts. Closing or swiping away the app keeps the operator's
server-side online status, so push alerts continue while online and available.
Force-stopping the app in Android settings prevents delivery until it is reopened.
Notification permission, phone sound settings and Do Not Disturb still apply.
Install the updated Android build and open it once to create the channel; deploy
the updated backend with the OneSignal configuration to send background alerts.

While an incoming request dialog is open, its tone and vibration repeat every
three seconds. They stop when all pending dialogs are dismissed or accepted,
when refreshed requests are no longer available, or when the user signs out.
Background push notifications still use a single notification tone; the repeating
dialog alert requires the app to be running.

The push payload includes the equipment, loading vehicle and offer amount only.
Exact location and the three-digit store number are returned only to the customer
or assigned operator after acceptance, never to other operators.

## Data and live updates

Requests have a unique sequential reference such as `#BK-10001`. Run `npm run migrate`
before deploying this version; existing requests receive numbers as well. Completed
and cancelled requests disappear from customer/operator history 72 hours after
closing. Billing and admin audit records are retained. Existing closed requests
use their recorded closing activity time, or migration time if none is available.

Neon stores users, hashed passwords, hashed session tokens, jobs, fixed loading
options, offers, private site details, positions, declines and notification outbox.
Images remain bundled Flutter assets; Neon is used for structured application data.
The server checks identity and ownership on every API call. Row locks and unique
indexes prevent double acceptance and multiple active jobs.

Authenticated WebSocket connections receive refresh signals without job contents.
Flutter then fetches its authorized list. Five-second polling reconciles disconnects;
location refreshes every three seconds. The WebSocket broadcaster supports one API
instance; add a shared event bus before scaling to multiple instances. Notifications
use database locking and provider idempotency for retries.

For phones use a reachable HTTPS API URL, configure HOST for your deployment, and
set allowed web origins in CORS_ORIGINS. Never expose Postgres credentials to clients.
Behind a reverse proxy, configure Express trust-proxy and shared rate limiting to
match your deployment. Complete operator identity verification for OneSignal before
production. Session and notification retention/cleanup require deployment policy.

## Validation

```powershell
cd backend
npm test
```

Backend tests use embedded Postgres (PGlite), exercising authentication, required
fields, private-data filtering, competing acceptance, state transitions, locations,
and logout. Run a real Neon concurrency/load test before production deployment.
Flutter checks: `flutter test` and `flutter analyze`.

No Neon connection string was supplied, so hosted database migration, deployment,
and a full two-device test have not been performed. Existing Supabase accounts/data
are not automatically copied; a separate export/import is needed if any exist.

See WORK_FLOW.md for the customer/operator page flow.

References: [Neon pooling](https://neon.com/docs/connect/connection-pooling),
[node-postgres TLS](https://node-postgres.com/features/ssl).

Offer amounts must be whole numbers from 100 to 999 Riyal. Run npm run migrate after updating an existing backend. If older offers fall outside this range, migration stops and rolls back without changing those records; reconcile them before retrying.

## Admin panel

Run `npm run migrate` after updating the backend. This adds profile fields and
admin accounts without deleting existing users. Existing email logins still work;
new admin-created accounts sign in by username.

To create the first admin, add these values to backend/.env locally:

```dotenv
ADMIN_NAME=Your full name
ADMIN_PHONE=Your phone number with country code
ADMIN_USERNAME=your_admin_username
ADMIN_PASSWORD=Choose a private password of at least 10 characters
```

Then run `npm run admin` from backend. Remove ADMIN_PASSWORD from .env afterward.
No default admin account or password is included. This command requires direct
server/database access and cannot be invoked by customers through the app.

Sign in with that username and password in the live app. The admin panel can:
- Create operators or customers with required full name, phone, username and password.
- Assign operators exactly one machine: 5-finger excavator grapple, Pickup van, or Big truck.
- Create customers without machine assignment.
- List and search registered customer/operator accounts (up to 100 per search).

Passwords are hashed server-side and never returned in account listings. Usernames
are unique and case-insensitive, using 3–40 letters, numbers or underscores. Phone
numbers require 7–15 digits, optionally with a leading +. Share new credentials with
the account owner through your chosen private channel; the app does not send them.
The local demo's Admin panel preview does not create real login accounts.

## Arrival and start OTP

Run npm run migrate to add job_start_codes (and generate missing codes for older
accepted jobs). After acceptance, only the customer receives the four-digit OTP.
The operator enters it to start work after selecting Go to work. Codes are consumed
on successful start; five incorrect attempts cause a one-minute retry delay.

Both Start work and Finished work require an operator GPS point no older than
30 seconds and within 100 metres of the pinned site. The app gets a fresh position
before each action; the API independently checks the saved point. Missing, denied,
stale or distant GPS blocks the action. This checks device-reported GPS, not
independent proof of physical presence.

Operators receive no new offers while accepted, on the way, or working. The API
hides open offers and the notification worker excludes busy operators. Notifications
already delivered before acceptance may remain in the phone notification tray;
they cannot be accepted while busy. Offers resume after completion if online.
