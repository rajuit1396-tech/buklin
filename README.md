# Buklin — on-demand work

Flutter customer and operator app for 5-finger excavator grapple, pickup van,
and big truck work. Customers request work now; operators accept or decline.
Status flow: Requested → Accepted → On the way → Working → Completed.
Customers can cancel while waiting. One active job per customer/operator.

## Local demo

Install Flutter and the Android toolchain:
https://docs.flutter.dev/platform-integration/android/setup

Run in this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-android.ps1
flutter run
```

Without backend configuration, a LOCAL DEMO banner is shown. Submit a customer
request, switch to Operator, go online, and accept it. Change statuses and switch
back to Customer to see them. Demo data resets when the app restarts.

## Live requests across devices

1. Create a Supabase project and run `supabase/schema.sql` once in its SQL editor.
2. Enable email/password authentication. Customers can register in the app and
   confirm their email before signing in.
3. Create operator accounts through Supabase Auth. From a trusted admin environment,
   set each operator's app_metadata to include `role: operator` and `service` set
   to exactly one of the three service names above. Users must sign in again after
   role changes. Never put an admin/service-role key in the app.
4. Run with your project URL and public anon key:

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY
```

Supabase Realtime triggers a refreshed job list on database changes, with a
five-second refresh as a reconnect/stale-visibility fallback. Requests are filtered
by the operator's equipment category. Atomic server-side acceptance prevents two
operators claiming the same request. Row-level policies restrict customer data;
only approved operators in the matching category can read open requests.
Declines are private to the operator and persisted in the backend.

Reference: https://supabase.com/docs/reference/dart/auth-signinwithpassword
and https://supabase.com/docs/reference/dart/stream

## Current scope and limitations

This is an implementation for an initial foreground work-request flow, not a deployed
production service. Backend setup has not been performed. GPS proximity matching,
live map/location tracking, background push notifications, operator names/contact,
pricing/payments and automatic request expiry are not implemented. Online/offline
controls the foreground offer view; it is not server-managed operator presence.
Waiting requests remain open until accepted or cancelled. Accepted jobs currently
must follow the completion flow; support cancellation is not yet implemented.

Flutter/Dart are unavailable in this workspace environment, so dependency resolution,
static analysis, device execution and APK compilation could not be run. The database
migration also needs validation in your Supabase project before deployment.

## Validation checklist

- Empty/short job details are rejected; all three equipment choices work.
- Demo: submit, accept, advance all statuses, and inspect customer history.
- Customer cancellation removes a request from operator offers.
- Use two real operator accounts to accept the same request simultaneously:
  exactly one succeeds. A second active job must also be rejected.
- A customer cannot read another customer's jobs or advance operator statuses.
- Operators cannot accept another category or change another operator's job.
- Decline persists after sign-out. Restart restores live jobs from the server.
- Disconnect/reconnect both devices and verify status reconciliation.

## Build

After Android setup: `flutter build apk --debug` (include the same dart defines
for a live build). APK: `build/app/outputs/flutter-apk/app-debug.apk`.

Generated logo: `assets/buklin-logo.png`; built-in imagegen prompt:
`assets/logo-prompt.txt`. The logo is embedded in the app, not yet a launcher icon.
