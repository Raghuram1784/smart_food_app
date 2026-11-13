# Repeatable live Android acceptance

Use only the dedicated `food_delivery_dev` database with its baseline dosa price of 14900 paise. Start NestJS on port 5000 and the Android emulator. The integration test uses the real app, Dio, NestJS, Prisma and PostgreSQL; no repository override is installed.

From the root:

```powershell
flutter drive --driver=test_driver/live_catalog.dart --target=integration_test/live_catalog_test.dart -d emulator-5554
```

The test opens Home, The Tiffin Room and Masala dosa and captures the actual original image/price. When it prints `PHASE2_READY_FOR_CHANGE`, run in another terminal from backend:

```powershell
npx tsx scripts/acceptance-change.ts change
```

This guarded development-only script changes dosa from 14900 to 14937 paise and checks the actual API. The Android test waits for the database-backed API, pulls down the menu, verifies ₹149.37 in the menu and detail sheet and captures it. When it prints `PHASE2_READY_FOR_RESTORE`, run:

```powershell
npx tsx scripts/acceptance-change.ts restore
```

The script restores 14900 and verifies the API. The test verifies the restored sheet and checks Light/Dark appearance navigation. Screenshots are saved by the host driver to `docs/phase2/screenshots/`. The mutable price is restored; monotonic version and updatedAt correctly retain evidence that changes occurred. The script refuses production/other databases and unexpected existing prices. **Always run restore after an interrupted test if change was applied.** No admin/write HTTP endpoint is introduced and no DB credentials enter Android.
