import 'dotenv/config';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import request from 'supertest';
import { removeF1TestData } from './f1-test-data';

/** Brand outlets give every Hyderabad locality real Veg and Non-Veg choices (isolated test DB only). */
test('locality coverage: brand outlets, menus, owner routing', { timeout: 240000 }, async (t) => {
  const url = process.env.TEST_DATABASE_URL!;
  assert.equal(new URL(url).pathname, '/food_delivery_test');
  process.env.DATABASE_URL = url;
  process.env.NODE_ENV = 'test';
  execFileSync(process.execPath, ['node_modules/prisma/build/index.js', 'migrate', 'deploy'], { env: { ...process.env, DIRECT_URL: url }, stdio: 'pipe' });
  const { createDatabase } = require('../dist/src/database/client');
  const { createApp } = require('../dist/src/main');
  const { PasswordService } = require('../dist/src/modules/auth/password.service');
  const { seedF1All } = require('../dist/prisma/seed_f1_all');
  const { OUTLETS, outletItemId } = require('../dist/prisma/seed_outlets');
  const db = createDatabase(url);
  const app = await createApp();
  const users: any[] = [];
  try {
    // A fresh owner of the Deccan Handi flagship, before seeding, must also own its new outlets.
    const password = randomUUID();
    const hash = await new PasswordService().hash(password);
    users.push(await db.user.create({ data: { email: `cov-${randomUUID()}@test.invalid`, displayName: 'Synthetic Owner', passwordHash: hash, roles: { create: { roleName: 'RESTAURANT_OWNER' } }, memberships: { create: { restaurantId: 'deccan-handi-gachi' } } } }));
    users.push(await db.user.create({ data: { email: `cov-${randomUUID()}@test.invalid`, displayName: 'Other Owner', passwordHash: hash, roles: { create: { roleName: 'RESTAURANT_OWNER' } }, memberships: { create: { restaurantId: 'tiffin' } } } }));
    const first = await seedF1All(db);
    assert.equal(first.outlets.outlets + (await db.restaurant.count({ where: { id: { in: OUTLETS.map((o: any) => o[0]) } } })) >= OUTLETS.length, true);
    const again = await seedF1All(db);
    assert.deepEqual([again.outlets.outlets, again.outlets.items, again.catalog.created], [0, 0, 0], 'idempotent');

    await t.test('every active Hyderabad locality has 6+ outlets with real Veg and Non-Veg choices', async () => {
      const zones = await db.deliveryZone.findMany({ where: { isActive: true, id: { in: (await db.locality.findMany({ where: { city: 'Hyderabad', isActive: true } })).map((l: any) => l.id) } } });
      assert.ok(zones.length >= 10);
      for (const z of zones) {
        const outlets = await db.restaurant.findMany({ where: { operatingStatus: 'OPEN', deliveryAvailability: true, zones: { some: { zoneId: z.id, isEligible: true } } }, include: { items: { where: { availabilityStatus: 'AVAILABLE' }, include: { profile: true } } } });
        const vegOutlets = outlets.filter((r: any) => r.items.filter((i: any) => i.isVegetarian && !['beverage', 'dessert'].includes(i.profile?.dishGroup)).length >= 3);
        const nonVegOutlets = outlets.filter((r: any) => r.items.filter((i: any) => !i.isVegetarian).length >= 3);
        assert.ok(outlets.length >= 6, `${z.id}: ${outlets.length} outlets`);
        assert.ok(vegOutlets.length >= 3, `${z.id}: ${vegOutlets.length} veg outlets`);
        assert.ok(nonVegOutlets.length >= 3, `${z.id}: ${nonVegOutlets.length} non-veg outlets`);
      }
      const kphb = await db.menuItem.count({ where: { availabilityStatus: 'AVAILABLE', profile: { foodFamily: 'chicken-biryani' }, restaurant: { zones: { some: { zoneId: 'kukatpally', isEligible: true } } } } });
      assert.ok(kphb >= 3, 'KPHB has chicken biryani choices');
    });

    await t.test('outlets: same brand, own locality and address, own menu ids, no invented coordinates', async () => {
      for (const [id, flagship, zone] of OUTLETS) {
        const o = await db.restaurant.findUniqueOrThrow({ where: { id }, include: { zones: true } });
        const f = await db.restaurant.findUniqueOrThrow({ where: { id: flagship } });
        assert.equal(o.brandId, f.brandId); assert.ok(o.brandId);
        assert.equal(o.localityId, zone); assert.equal(o.latitude, null); assert.equal(o.longitude, null);
        assert.deepEqual(o.zones.map((z: any) => z.zoneId), [zone]);
        const fItems = await db.menuItem.findMany({ where: { restaurantId: flagship } });
        for (const it of fItems) {
          const copy = await db.menuItem.findUniqueOrThrow({ where: { id: outletItemId(id, it.id) }, include: { nutrition: true } });
          assert.equal(copy.restaurantId, id); assert.equal(copy.basePricePaise, it.basePricePaise); assert.equal(copy.isVegetarian, it.isVegetarian);
        }
      }
      // An outlet never introduces duplicate dish names beyond what its flagship menu already has.
      for (const [id, flagship] of OUTLETS) {
        const count = async (rid: string) => Object.fromEntries((await db.$queryRawUnsafe(`SELECT lower(name) n, count(*)::int c FROM "MenuItem" WHERE "restaurantId" = $1 GROUP BY 1`, rid)).map((r: any) => [r.n, r.c]));
        assert.deepEqual(await count(id), await count(flagship), `${id} menu mirrors ${flagship} without extra duplicates`);
      }
    });

    await t.test('owner routing: brand owner sees the outlet inbox; another owner cannot', async () => {
      await app.init();
      const api = request(app.getHttpServer());
      const tok = async (u: any) => (await api.post('/api/v1/auth/login').send({ email: u.email, password }).expect(200)).body.data.session.token;
      const [owner, other] = [await tok(users[0]), await tok(users[1])];
      await api.get('/api/v1/restaurants/deccan-handi-kphb/orders').set('Authorization', `Bearer ${owner}`).expect(200);
      await api.get('/api/v1/restaurants/deccan-handi-kphb/orders').set('Authorization', `Bearer ${other}`).expect(403);
      const menu = (await api.get('/api/v1/restaurants/deccan-handi-kphb/menu').expect(200)).body.data;
      assert.ok(JSON.stringify(menu).includes('Kukatpally'), 'outlet locality shown');
    });
  } finally {
    await db.restaurantMembership.deleteMany({ where: { userId: { in: users.map((u) => u.id) } } });
    await removeF1TestData(db);
    await app.close();
    await db.$disconnect();
  }
});
