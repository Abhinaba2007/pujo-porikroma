# Pujo Parikrama – private pandal-hopping map for your friend group

Everything used here is free: Supabase free plan (database, login, realtime, photo storage),
Leaflet + OpenStreetMap (map), and any free static host.

## Who sees what
| | Friend | Admin (you) |
|---|---|---|
| Pandal map | all pandals | all pandals, **only you can add/edit/delete** |
| Live location | only their own dot | **every friend, live** + permanent history |
| Name | chosen once at join, **only you can change it** | can rename anyone |
| Photos at a pandal | only their own | **all photos** |
| Chat | only their own conversations | **all conversations** |

Friends cannot delete messages, photos or history, so your audit record stays complete.
Joining needs a secret **join code**, so strangers who find the link cannot enter.
The join screen tells every friend, in plain words, that you can see their location, photos and messages, and they must tick a box to agree. They also get a **Pause sharing** button. Keep this: it is what makes the "ethical / audit" purpose honest, and your friends will trust the app more.

## Setup (about 15 minutes)
1. **Supabase project** – sign up free at supabase.com > New project (pick the Mumbai/Singapore region).
2. **Database** – SQL Editor > paste all of `schema.sql` > Run.
3. **Anonymous sign-ins** – Authentication > Providers (or Sign In / Providers) > turn on **Anonymous Sign-Ins**.
4. **Your admin account** – Authentication > Users > Add user > your email + password, tick *Auto Confirm User*.
5. In the SQL Editor run (edit the values):
   ```sql
   insert into public.app_settings (key, value) values ('join_code', 'PUJO2026')
     on conflict (key) do update set value = excluded.value;
   insert into public.admins (user_id)
     select id from auth.users where email = 'YOUR-ADMIN-EMAIL@example.com';
   ```
6. **Keys** – Project Settings > API. Copy *Project URL* and the *anon public* key into the two lines at the top of the script in `index.html`. (The anon key is meant to be public; the security rules in `schema.sql` protect the data.)
7. **Host it free (HTTPS is required for GPS)** – drag the folder to Netlify Drop, or use GitHub Pages / Cloudflare Pages.
8. Open the link on your phone. Tap **I am the admin**, sign in, tap **＋** on the map, tap where a pandal is, fill the name, save.
9. Send friends the link + join code. On a phone they can "Add to Home Screen".

## Getting the most accurate live location
* Location comes from the phone's GPS (`enableHighAccuracy`) and the app shows the live error radius (e.g. "GPS ±8 m"). Outdoors this is usually 3–10 m; between tall buildings or in dense crowds it can drift, which is a hardware limit, not a bug.
* **A web app only updates while it is open on screen.** The app asks the phone to keep the screen awake, but if a friend locks the phone or switches app, tracking pauses until they come back. Google Find Hub works in the background because it is a native Android app with special permission. To get true background tracking you would need a native app (for example Expo/React Native with background location, free to build and run on your own phones). Tell friends to keep the app open while hopping.
* Ask friends to allow **Precise location** when the browser asks.

## Free-plan limits to know
* 500 MB database, 1 GB photo storage, 200 simultaneous realtime connections: plenty for a friend group over the Puja days.
* A free Supabase project pauses after about 7 days of no use; open the dashboard and click Restore if that happens.
* Map tiles come from OpenStreetMap's public server, which is fine for a small group.

## Notes
* Friends can only take a photo within 150 m of a pandal (change `PHOTO_RADIUS_M` in `index.html`). This check runs in the app; the database rules still keep every photo private to its owner and you.
* Do not publish this app to the public. It is built for a group that all know and agree to the admin visibility described above.
