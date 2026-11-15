# Deployment configuration (ready, not applied)

This folder and the files it references put [docs/DEPLOYMENT_PLAN.md](../docs/DEPLOYMENT_PLAN.md) into practice. **Nothing has been purchased, created or deployed.** Every step below needs explicit approval first.

| File | Purpose |
|---|---|
| [`render.yaml`](../render.yaml) | Render Blueprint: one always-on Node web service in Singapore, build/migrate/start commands, `/api/v1/health` check, secrets marked `sync: false` |
| [`backend/.env.production.example`](../backend/.env.production.example) | Every production variable, by name, with safe defaults and no secret values |

## Steps once approved

1. **Database.** Create a new Postgres (Neon free tier or Render Postgres, Singapore). Copy its pooled URL into `DATABASE_URL` and its direct URL into `DIRECT_URL`.
2. **Secrets.** Generate two different handover keys, then create new Gemini and Razorpay **test** keys. Enter everything in the Render dashboard; never commit any of it.
   ```bash
   node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```
3. **Service.** In Render, choose New → Blueprint, select this repository and branch `main`, and review the plan (Starter, about $7/month) before confirming.
4. **Deploy.** The build runs, then `prisma migrate deploy` applies all 19 migrations to the new database. Then seed the catalog and the demo role accounts with new passwords, using the existing seed scripts against `DIRECT_URL`.
5. **Smoke test.** Check `GET https://<service>.onrender.com/api/v1/health` and a Socket.IO connection over `wss://`.
6. **Android APK.** Build with a private upload keystore. Keep `android/key.properties` and the keystore out of Git.
   ```bash
   flutter build apk --release --dart-define=API_BASE_URL=https://<service>.onrender.com/api/v1/ --dart-define=MAP_TILE_URL=<approved tile URL> --dart-define=MAP_ATTRIBUTION="<provider> © OpenStreetMap contributors"
   ```
7. **Pickup points.** Owners of the demo outlets confirm their pickup points in the app (Set pickup location).
8. **Two-phone check.** Install the APK on two phones (customer and rider) and do the **simultaneous two-phone GPS movement test**. It was planned for after deployment, because only one phone was available during development.

## Decisions still needed

- Host plan and database provider.
- Map tile provider and key (MapTiler or Stadia free tier).
- Routing: keep `none` (labelled estimates) or approve a provider key (for example OpenRouteService free tier).
- Live-demo payment mode: Razorpay test mode (recommended), or a separate, explicitly marked staging deployment with demo checkout. That second option needs a small code change.
