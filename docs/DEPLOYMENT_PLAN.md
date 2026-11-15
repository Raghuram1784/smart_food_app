# Deployment Plan — Team NeuroX (proposal, nothing purchased or deployed)

The goal is an affordable, always-on hackathon deployment of the NestJS API, PostgreSQL and Socket.IO, with an Android release APK pointing at it. **Every paid item and every API key below needs your approval before it is set up.**

## 1. Recommended setup

| Part | Recommendation | Approx. cost | Why |
|---|---|---|---|
| NestJS API + Socket.IO | **Render Web Service** (Starter, 1 instance, Singapore region) | about $7/month | Always on (no sleeping), managed HTTPS, WebSockets supported, deploys from GitHub |
| PostgreSQL | **Neon** (free tier, Singapore) or **Render Postgres** Basic | $0 (Neon free) / about $6–7/month | Hosted Postgres 16, separate deployment database, pooled + direct URLs |
| Map tiles | **MapTiler** or **Stadia Maps** free tier (API key) | $0 within free quota | The OpenStreetMap public tile server is not for production app traffic |
| Road routing (ETA) | **OpenRouteService** free key (about 2,000 directions/day) or keep `ROUTING_PROVIDER=none` | $0 | The public OSRM demo is for development only. ETAs stay clearly labeled estimates without routing |
| Android APK | `flutter build apk --release` with a private signing key | $0 | Sideloaded to the demo phones |

Alternatives:
- **Railway:** about $5/month usage, also supports WebSockets.
- **Fly.io:** one shared-CPU machine.

Keep **exactly one API instance**. The outbox dispatcher, scheduler (F3) and tracking sweep are single-process components. Scaling to several instances requires a Socket.IO Redis adapter and job claiming first.

## 2. Backend configuration (names only; values go in the host's secret store)

| Variable | Deployment value |
|---|---|
| `NODE_ENV` | `production` |
| `PORT` | Set by the host |
| `DATABASE_URL` | Pooled URL of the **new** deployment database |
| `DIRECT_URL` | Direct URL, for migrations |
| `API_PREFIX` | Unchanged |
| `CORS_ORIGINS` | The deployed domains only |
| `APP_LINK_BASE` | `https://<domain>` |
| `AUTH_SESSION_HOURS` | Unchanged |
| `HANDOVER_HMAC_KEY`, `HANDOVER_ENCRYPTION_KEY` | **New** random 32-byte keys (never reuse development keys) |
| `HANDOVER_KEY_VERSION`, `HANDOVER_TTL_SECONDS`, `HANDOVER_REGENERATE_SECONDS` | Unchanged |
| `GEMINI_API_KEY` | A new key restricted to this project |
| `GEMINI_MODEL`, `GEMINI_FALLBACK_MODEL`, `GEMINI_TIMEOUT_MS`, `FINDER_RATE_PER_MINUTE` | Unchanged |
| `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` | **Test mode** keys for the hackathon |
| `ROUTING_PROVIDER`, `ROUTING_BASE_URL` | `none`, or an approved provider |
| `SCHEDULE_DEMO_FAST` | Unset (production ignores it anyway) |
| `DEMO_AUTH_ENABLED`, `DEMO_CHECKOUT_ENABLED`, `DEMO_FULFILLMENT_ENABLED` | See the decision below |
| `DEMO_PASSWORD`, `DEMO_*_PASSWORD` | New strong values, or omitted if demo seeding is off |

**Decision needed: demo checkout.** In `production`, demo (no-payment) checkout is refused by design (`checkout` requires `development` or `test`). For a live judge demo, choose one:
1. Use Razorpay **test mode**. This is the real payment flow with test cards; no real money moves. **Recommended.**
2. Run a clearly marked `staging` deployment with demo checkout. This requires a small code change to allow a `staging` environment explicitly, plus banner text, so production stays locked.

Development-only credentials:
- Never copy the development `.env`. Generate new secrets.
- Seed only the catalog and the demo role accounts, with new passwords.
- Leave development test accounts and synthetic device users behind.

## 3. Database

- Create a **separate** deployment database. Never point the deployment at `food_delivery_dev` or `food_delivery_test`.
- Apply schema: `npx prisma migrate deploy` (all 19 forward-only migrations).
- Load the catalog and seeds with the existing seed scripts: 38 outlets, 737 dishes, 10 localities. Restaurant pickup coordinates stay empty until each owner confirms them in the app.
- Backups: Neon point-in-time restore (free tier keeps a short history), or Render's daily backups.

## 4. Build and run

Render settings:

| Setting | Value |
|---|---|
| Build command | `cd backend && npm ci && npx prisma generate && npm run build` |
| Pre-deploy command | `cd backend && npx prisma migrate deploy` |
| Start command | `cd backend && node dist/src/main.js` |
| Health check path | `/api/v1/health` |

HTTPS and WebSocket (wss) are terminated by the host. The Flutter client already connects Socket.IO to the API origin.

## 5. Android release APK

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://<domain>/api/v1/ --dart-define=MAP_TILE_URL=<approved tile URL with key> --dart-define=MAP_ATTRIBUTION="<provider> © OpenStreetMap contributors"
```

- **Signing:** create an upload keystore. Keep it and its passwords outside Git, configured in `android/key.properties`, which is ignored.
- **Phone setup:** install on the Samsung (customer) and a second Android phone (rider). Allow location, plus notifications for the rider's foreground tracking notification.
- **Never ship:** the integration-test APK or its private defines.

## 6. Go-live checklist

- [ ] Approve the host, database and tile/routing providers (and any keys)
- [ ] Create the deployment DB; apply migrations and seed with new demo passwords
- [ ] Set secrets on the host; check `/api/v1/health` and a WebSocket connection over wss
- [ ] Owners confirm pickup points for the demo outlets
- [ ] Build the signed release APK with the deployed URL; run an end-to-end smoke test (order → kitchen → rider invitation → live tracking → OTP)
- [ ] Confirm CORS, rate limits and that demo flags match the chosen option

Nothing in this plan has been purchased, created or deployed.
