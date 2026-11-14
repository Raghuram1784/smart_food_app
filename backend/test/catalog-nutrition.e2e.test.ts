import 'dotenv/config';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import request from 'supertest';

test('diet filter, nutrition provenance and idempotent catalog expansion', { timeout: 120000 }, async (t) => {
  const url = process.env.TEST_DATABASE_URL!;
  assert.equal(new URL(url).pathname, '/food_delivery_test');
  process.env.DATABASE_URL = url;
  process.env.NODE_ENV = 'test';
  execFileSync(process.execPath, ['node_modules/prisma/build/index.js', 'migrate', 'deploy'], { env: { ...process.env, DIRECT_URL: url }, stdio: 'pipe' });
  const { createDatabase } = require('../dist/src/database/client');
  const { createApp } = require('../dist/src/main');
  const { expandCatalog, DISHES, NUTRITION_REF, BASE_DISH_FACTS } = require('../dist/prisma/seed_catalog_expansion');
  assert.equal(new URL(process.env.DATABASE_URL!).pathname, '/food_delivery_test');
  const db = createDatabase(url);
  const app = await createApp();
  try {
    await app.init();
    const api = request(app.getHttpServer());

    await t.test('seed data: explicit classification is consistent with listed ingredients; every reference exists', () => {
      const meat = /\b(chicken|mutton|lamb|fish|prawns?|egg|eggs|keema|beef|pork|bacon|pepperoni|gosht|murgh)\b/i;
      for (const [, key, name, description, , , , , veg, ref] of DISHES) {
        const text = `${name} ${description}`;
        assert.equal(veg, !meat.test(text), `${key}: classification must match ingredients (${text})`);
        if (ref) assert.ok(NUTRITION_REF[ref], `${key}: unknown nutrition reference ${ref}`);
      }
      assert.equal(BASE_DISH_FACTS.pizza.veg, false);
      assert.equal(BASE_DISH_FACTS.burger.veg, false);
      for (const n of Object.values(NUTRITION_REF) as any[]) {
        assert.ok(n.kcal > 0 && n.grams > 0 && n.serving.length > 3, 'every estimate states a serving');
        assert.equal(n.kcal % 10, 0, 'calories are rounded, not falsely precise');
      }
    });

    await t.test('expansion is idempotent and never overwrites edited items', async () => {
      const first = await expandCatalog(db);
      const before = await db.menuItem.count();
      const anyNew = await db.menuItem.findFirst({ where: { id: { startsWith: 'x-' } } });
      if (anyNew) await db.menuItem.update({ where: { id: anyNew.id }, data: { name: anyNew.name + ' (edited)' } });
      const second = await expandCatalog(db);
      assert.equal(second.created, 0);
      assert.equal(second.nutrition, 0);
      assert.equal(await db.menuItem.count(), before);
      if (anyNew) {
        assert.match((await db.menuItem.findUniqueOrThrow({ where: { id: anyNew.id } })).name, /\(edited\)$/);
        await db.menuItem.update({ where: { id: anyNew.id }, data: { name: anyNew.name } });
      }
      assert.ok(first.created >= 0);
    });

    await t.test('diet=veg / diet=nonveg filter real MenuItem records server-side; Both is unfiltered', async () => {
      const veg = (await api.get('/api/v1/catalog/search?diet=veg&limit=50').expect(200)).body.data;
      const non = (await api.get('/api/v1/catalog/search?diet=nonveg&limit=50').expect(200)).body.data;
      const both = (await api.get('/api/v1/catalog/search?limit=50').expect(200)).body.data;
      assert.ok(veg.items.length > 0 && non.items.length > 0);
      assert.ok(veg.items.every((i: any) => i.isVegetarian === true));
      assert.ok(non.items.every((i: any) => i.isVegetarian === false));
      assert.equal(veg.total + non.total, both.total);
      await api.get('/api/v1/catalog/search?diet=vegan').expect(400);
      const vegKitchens = (await api.get('/api/v1/restaurants?diet=veg&limit=50').expect(200)).body.data.items;
      const allKitchens = (await api.get('/api/v1/restaurants?limit=50').expect(200)).body.data.items;
      assert.ok(vegKitchens.length > 0 && vegKitchens.length <= allKitchens.length);
      // A pure-veg kitchen never appears for non-veg.
      const nonKitchens = (await api.get('/api/v1/restaurants?diet=nonveg&limit=50').expect(200)).body.data.items;
      assert.ok(!nonKitchens.some((r: any) => r.id === 'kaveri-veg-biryani-kuka'));
      // Category + diet must match on the same dish.
      const vegBiryani = (await api.get('/api/v1/restaurants?diet=veg&category=biryani&limit=50').expect(200)).body.data.items;
      for (const r of vegBiryani) {
        assert.ok(await db.menuItem.findFirst({ where: { restaurantId: r.id, categoryId: 'biryani', isVegetarian: true } }));
      }
    });

    await t.test('nutrition: labelled estimate with serving + source when present; null (unavailable) otherwise', async () => {
      const withN = await db.menuItemNutrition.findFirstOrThrow();
      const item = (await api.get(`/api/v1/menu-items/${withN.menuItemId}`).expect(200)).body.data;
      assert.equal(item.nutrition.basis, 'ESTIMATE');
      assert.ok(item.nutrition.caloriesKcal > 0);
      assert.equal(typeof item.nutrition.proteinG, 'number');
      assert.ok(item.nutrition.servingDescription.length > 0);
      assert.match(item.nutrition.source, /Estimate/);
      assert.equal(item.nutrition.appliesTo, 'BASE_SERVING_ONLY');
      const without = await db.menuItem.findFirstOrThrow({ where: { nutrition: { is: null } } });
      const plain = (await api.get(`/api/v1/menu-items/${without.id}`).expect(200)).body.data;
      assert.equal(plain.nutrition, null, 'missing nutrition is null, never zeros');
      const menu = (await api.get(`/api/v1/restaurants/${withN.menuItemId.startsWith('x-') ? (await db.menuItem.findUniqueOrThrow({ where: { id: withN.menuItemId } })).restaurantId : 'tiffin'}/menu`).expect(200)).body.data;
      assert.ok(JSON.stringify(menu).includes('"nutrition"'));
    });
  } finally {
    // Test DB only: remove what the expansion added so other suites keep their
    // exact base-fixture invariants (e.g. Tiffin menu = 4 items).
    const added = (await db.menuItem.findMany({ where: { id: { startsWith: 'x-' } }, select: { id: true } })).map((r: any) => r.id);
    await db.menuItemNutrition.deleteMany({ where: { OR: [{ menuItemId: { in: added } }, { menuItemId: { in: Object.keys(BASE_DISH_FACTS) } }] } });
    await db.menuItem.deleteMany({ where: { id: { in: added }, cartItems: { none: {} }, orderItems: { none: {} } } });
    await app.close();
    await db.$disconnect();
  }
});
