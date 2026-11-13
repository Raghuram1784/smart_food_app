# Food Delivery catalog backend — Phase 2

A NestJS modular monolith inside the existing Flutter repository. PostgreSQL owns catalog records; NestJS exposes read-only REST; Flutter uses Dio/Riverpod. Ordering, auth, payments and sockets are deliberately deferred.

## Local startup

Prerequisites: Node 22.12+ (verified 22.20.0), npm, PostgreSQL 15+ (verified local 15.10), Flutter 3.47.5 / Dart 3.13.4 for Android. Dependencies are locked. The local Windows service on port 5432 is `postgresql-x64-15`; inspect services before starting anything. Do not change other projects' databases.

From `backend/`:

```powershell
npm ci
Copy-Item .env.example .env # only on first setup; never overwrite an existing .env
# Configure private credentials; see database/PGADMIN_GUIDE.md for a new machine.
npm run db:generate
npm run db:migrate
npm run db:seed
npm run db:verify
npm run dev
```

On this machine `food_delivery_dev`, dedicated role `food_app_user`, and `food_delivery_test` already exist. The untracked `.env` is configured. Do not paste it into logs or commits. This development role is not a PostgreSQL superuser; it owns only this project's databases. Production must split schema-owner/migrator and runtime permissions.

`npm run dev` compiles and runs Node's watcher over compiled output. After editing TypeScript run `npm run build` in a second terminal; the watcher restarts. Compilation is essential because Nest validation relies on emitted decorator metadata. `npm start` runs compiled code without watching.

## Configuration

| Variable | Purpose |
| --- | --- |
| DATABASE_URL | Runtime PostgreSQL connection, never sent to Flutter |
| DIRECT_URL | Prisma CLI/migrations, same as runtime for local direct PostgreSQL |
| TEST_DATABASE_URL | Dedicated `food_delivery_test`; integration tests refuse other database names |
| NODE_ENV | `development`, `test` or `production` |
| PORT | API port, default 5000 |
| API_PREFIX | Default `api/v1` |
| LOG_LEVEL | Request logging level (`info` by default) |
| CORS_ORIGINS | Explicit comma-separated browser origins; default localhost:3000 |

Public read-only catalog endpoints are intentionally unauthenticated. CORS is not authorization. No write, payment or admin endpoints exist. Structured logs contain request IDs, method, status and duration, not credentials, headers or user query strings. Production requires database TLS and HTTPS at the ingress; Swagger is disabled there. Body limit 32 KiB, query timeout 5s, connection timeout 5s, API timeout 8s, pool max 5 per process. See deployment readiness before exposing publicly.

## APIs

Base `http://localhost:5000/api/v1`.

| GET path | Result |
| --- | --- |
| /health | Live database connectivity |
| /categories | Active categories in display order |
| /cuisines | Cuisine records |
| /restaurants | Page of kitchens; q, cuisine, category filters |
| /restaurants/:id | Kitchen details |
| /restaurants/:id/menu | Ordered sections and items |
| /menu-items/:id | Full dish, category, kitchen, variants and add-ons |
| /catalog/search | Database multiword search; category, cuisine, maxPricePaise filters |

Pagination: page 1–10000, limit 1–50 (default 20). Stable sort uses displayOrder then ID. Unknown query parameters, malformed identifiers and invalid values yield 400; absent records 404; database failure 503. Success: `{data: ..., requestId: uuid}`. Page data: `{items, total, page, limit}`. Error: `{error:{code,message},requestId}`. Monetary fields are integer paise; there is no checkout total. Swagger: [interactive docs](http://localhost:5000/api/v1/docs), JSON at `/api/v1/docs-json`. See [contract](docs/API_CONTRACT.md).

## Flutter

From the repository root:

```powershell
flutter pub get
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1/
```

Android emulator's localhost is itself; `10.0.2.2` reaches Windows. For a physical device on the same private LAN set API_BASE_URL to the Windows LAN address and port 5000; allow the port on the private firewall only. Alternatively USB `adb reverse tcp:5000 tcp:5000` and use `http://127.0.0.1:5000/api/v1/`. Debug builds allow local HTTP; release builds explicitly prohibit cleartext and require an HTTPS API URL.

Offline demonstration is an explicit build option: `--dart-define=CATALOG_MODE=offline`. It displays an offline banner. Failed live requests never fall back to fixture prices. Pull down Home/menu/search to refresh. Search debounces for 300ms, cancels superseded/disposed requests and uses server-side pagination/filtering. Home is a curated first page (20 kitchens/items); search provides subsequent catalog pages. The neighbourhood selector remains illustrative and does not claim delivery eligibility.

## Verification

```powershell
npm run build
npm test
npm run test:e2e
npx prisma validate
npx prisma generate
npx prisma migrate status
npm run db:verify
```

Tests apply migrations only to `food_delivery_test`, seed safely, exercise constraints, actual APIs and actual connection refusal. No reset/drop command is used. They expect an isolated baseline test database; never point tests at valuable data. `npm test` consumes compiled Nest code; build first.

Flutter: `dart format lib test integration_test test_driver`, `flutter analyze`, `flutter test`. The Android test requires the live API and host-side controlled price change; see [acceptance runbook](docs/ANDROID_ACCEPTANCE.md). pgAdmin instructions: [database/PGADMIN_GUIDE.md](database/PGADMIN_GUIDE.md).

## Migration safety and troubleshooting

`prisma migrate deploy` applies reviewed committed migrations; it does not generate migrations or detect all drift. For a new schema change use `prisma migrate dev --name <change>` only in an isolated developer database with a dedicated shadow database/appropriate role, inspect SQL, then commit. Do not grant CREATEDB broadly just for convenience. Never reset a shared database or use `db push` as deployment. Stop and investigate drift/destructive changes; back up first. SQL CHECK constraints and pg_trgm indexes are in the migration because they are not fully expressible in Prisma schema.

Connection refused: verify service/port, .env and database existence. Authentication failure: configure the real role password privately; do not reset unknown credentials. 503: inspect database connectivity/migration status. Android error: verify host API health first, then emulator URL. Missing image: API imageKey must match a bundled asset; placeholders are intentional for unknown keys. Port conflict: set PORT and matching Flutter URL. No release deployment, signing, load test or real delivery coverage is claimed.

Architecture: [schema and pricing](docs/DATABASE.md), [future operations](docs/FUTURE_OPERATIONS.md), [Azure readiness](docs/DEPLOYMENT.md). Official implementation references: [Prisma 7 PostgreSQL adapter/config](https://www.prisma.io/docs/orm/v7/core-concepts/supported-databases/postgresql), [NestJS validation](https://docs.nestjs.com/techniques/validation).
