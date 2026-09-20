# Current work flow

Backend: Node.js in backend/, with Neon Postgres. Follow README.md for setup.
The old supabase/ files are inactive historical artifacts.

1. Choose work equipment: 5-finger excavator grapple, Pickup van, or Big truck.
2. Choose Dyna, Trailer, or Inside store. Custom names are not allowed.
   A three-digit whole amount from 100 to 999 Riyal is required.
3. The admin assigns a fixed three-digit store number when creating the customer
   account (007 is valid), and selects the exact customer location on the admin map
   or using GPS. Customers see these fixed account details and cannot edit them.
   Every request uses the saved account location. Existing customers need a one-time
   location assignment in the admin panel before requesting new work.
4. Search for an operator. Waiting requests may be cancelled by the customer.
5. Available operators see equipment, loading type and offer amount. Exact location
   and store number stay hidden until acceptance. Only one operator can accept.
6. Assigned operator sees the location, navigates to work and explicitly starts
   location sharing. Customer sees the marker and last-update timestamp.
7. Go to work → Start work → Complete work. Completed jobs reject location writes.

GPS sharing stops when the job widget closes, the job completes or the app exits.
Android uses a foreground-service notification while sharing. Browser background
tracking is not guaranteed. The app displays stale positions as last known.
Maps currently use OpenStreetMap; a Google Maps SDK integration requires a key.
Offers are displayed in Riyal, with no decimals.

Node.js processes notification_outbox and sends OneSignal alerts with equipment,
loading choice and offer. Android push requires OneSignal/FCM configuration. No
background phone alerts are simulated in the Chrome demo.

Remaining deployment work: Neon connection string and schema migration, HTTPS hosting,
OneSignal credentials/identity verification, device tests and production rate limiting.


The assigned operator's accepted-job screen now starts GPS sharing automatically, including when reopened. Device location permission is still required. Customers receive position updates from the configured backend; the local demo cannot track a second phone. Operators can stop or retry sharing.

Start now requires arrival (within 100 metres, GPS no older than 30 seconds) and the customer's automatically generated four-digit OTP. Finished work also requires fresh arrival confirmation. New work requests and push sends are paused from acceptance until completion. Run the Node migration to create private start-code storage.
