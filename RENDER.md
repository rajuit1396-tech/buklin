# Deploy Buklin on Render

## Existing service: buklin-1

The existing service serves the admin panel at https://buklin-1.onrender.com/
and the customer/operator app at https://buklin-1.onrender.com/app/.
The production Flutter bundle is committed in `backend/public/app/` so the
existing Node service can deploy it without installing Flutter on Render.
After Flutter source changes, run `scripts/package-render-app.ps1`, then commit
the source and updated bundle together. The app uses the same live backend.

## Optional separate web and API services

`render.yaml` defines the Flutter customer/operator site and the Node API/admin
site. The web build requires a backend URL, so it cannot silently deploy demo mode.
The API uses the existing Neon Postgres database; no database is created by this
Blueprint. Never commit credentials or put database/admin secrets in the web service.

1. Push this project to your GitHub repository, including `render.yaml` and `scripts/`.
2. In Render, select **New > Blueprint** and connect that repository.
3. Set these API service variables in Render:
   - `DATABASE_URL`: your private Neon Postgres URL with verified TLS.
   - `CORS_ORIGINS`: the web site's exact HTTPS origin (no trailing slash).
   - `ADMIN_EMAIL` and `ADMIN_PASSWORD`: the administrator login; use a password
     of at least 10 characters. Optionally set `ADMIN_NAME`.
4. Set the web site's `BACKEND_URL` to the API's actual HTTPS origin, without a
   trailing slash. Use the URLs assigned by Render, not assumed service names.
   If the URLs are assigned after creation, update these variables and redeploy.
5. Check the API `/health` endpoint returns `{"ok":true}`. The startup command runs
   database migrations before starting the API and stops if migration fails.
6. Open the API root URL to sign in as admin and create customer/operator accounts.
   Remove `ADMIN_PASSWORD` from Render after successfully signing in; leaving it
   configured resets the administrator password on each server restart.
7. Open the web site URL. Check both login roles with accounts created by the admin.

The Blueprint selects the free API plan. It can sleep while idle, causing slow
initial requests and interrupting background notification processing. Choose an
always-on plan in Render for continuous operation. Only one API instance should
run because live WebSocket broadcasts are currently local to the process.

For an existing Render API, retain its database and service URL. Apply the backend
build/start commands and environment variables above, and create only the static
site if needed. Review any Blueprint proposal before adopting existing services.

Optional phone notifications require `ONESIGNAL_APP_ID` and
`ONESIGNAL_REST_API_KEY` on the API service. The web deployment does not provision
Android push credentials.

References: https://render.com/docs/blueprint-spec and
https://render.com/docs/free
