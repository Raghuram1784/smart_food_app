# Deployment Plan — SAMORI by Team NeuroX

**Selected platform: Microsoft Azure.** Status: **not deployed yet.** No resources have been purchased or created, and there is no live URL. Every paid item and API key below needs approval first.

## 1. Selected architecture (Azure)

| Part | Azure service | Notes |
|---|---|---|
| NestJS API + Socket.IO | **Azure App Service** (Linux, Node 22, Central India) | Turn on Always On and Web sockets. HTTPS-only; a managed TLS certificate covers `https://` and `wss://`. Run **one instance**: the outbox dispatcher, F3 scheduler and F4 tracking sweep are single-process components |
| Database | **Azure Database for PostgreSQL – Flexible Server** (Burstable tier, Central India) | A separate deployment database; never the dev or test DB. Enforce TLS and allow only App Service outbound IPs or a private endpoint |
| Secrets | App Service **Application settings** (optionally backed by Azure Key Vault) | Never commit values. Names are listed in `backend/.env.production.example` |
| Mobile app | **Flutter release APK** | Signed with a private upload keystore; points at the App Service URL |
| Map tiles | Approved provider with a key (e.g. MapTiler / Stadia) | The public OpenStreetMap tile server is not for production app traffic |
| Road routing | `ROUTING_PROVIDER=none` (labelled estimates) or an approved provider | The public OSRM demo server is development-only |

## 2. Configuration (names only)

Set these as App Service Application settings:

| Variable | Deployment value |
|---|---|
| `NODE_ENV` | `production` |
| `WEBSITES_PORT` / `PORT` | Provided by App Service |
| `API_PREFIX` | `api/v1` |
| `CORS_ORIGINS` | The deployed domain(s) only |
| `APP_LINK_BASE` | `https://<app>.azurewebsites.net` |
| `DATABASE_URL`, `DIRECT_URL` | The Azure PostgreSQL connection string with `sslmode=require` |
| `HANDOVER_HMAC_KEY`, `HANDOVER_ENCRYPTION_KEY` | **New**, different 64-hex keys |
| `HANDOVER_KEY_VERSION`, `HANDOVER_TTL_SECONDS`, `HANDOVER_REGENERATE_SECONDS` | Unchanged |
| `GEMINI_API_KEY` (+ model settings) | A new key restricted to this project |
| `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` | **Test mode** keys |
| `ROUTING_PROVIDER`, `ROUTING_BASE_URL` | `none`, or an approved provider |
| `DEMO_AUTH_ENABLED`, `DEMO_CHECKOUT_ENABLED`, `DEMO_FULFILLMENT_ENABLED` | `false` (see the decision below) |

**Decision needed: live-demo payments.** Demo no-payment checkout is refused when `NODE_ENV=production`. The recommended option is Razorpay **test mode**, where no real money moves. Production-scale payment processing has **not** been verified.

## 3. Build and release steps (after approval)

1. **Create** the resource group, the PostgreSQL Flexible Server (database `samori`) and the App Service plan + web app (Node 22, Always On, Web sockets on).
2. **Build and migrate** from `backend/`:
   ```bash
   npm ci && npx prisma generate && npm run build && npx prisma migrate deploy
   ```
   `migrate deploy` applies all 19 forward-only migrations.
3. **Deploy** the `backend` folder (zip deploy or GitHub Actions) with startup command `node dist/src/main.js`. Set the health check path to `/api/v1/health`.
4. **Seed** the catalog and demo role accounts with **new** passwords. Owners confirm their restaurant pickup points in the app.
5. **Android:** build the release APK.
   ```bash
   flutter build apk --release --dart-define=API_BASE_URL=https://<app>.azurewebsites.net/api/v1/ --dart-define=MAP_TILE_URL=<approved tile URL>
   ```
6. **Smoke test:** health, `wss://` Socket.IO, then order → kitchen → rider invitation → live tracking → OTP.
7. **Two-phone GPS test:** run the **simultaneous two-phone GPS movement test**, with the rider and customer on separate phones. It is still pending after development.

## 4. Alternative (not selected)

A Render Blueprint (`render.yaml`) was prepared earlier as a lower-effort alternative. It is **not** the selected architecture. It remains in the repository for reference only.

## 5. Checklist

- [ ] Approve Azure subscription, region and tiers
- [ ] Create the PostgreSQL Flexible Server and App Service; set Application settings
- [ ] Deploy, migrate, seed with new demo passwords
- [ ] Choose map-tile and routing providers (and keys)
- [ ] Build the signed release APK; smoke test end to end
- [ ] Two-phone live GPS test
