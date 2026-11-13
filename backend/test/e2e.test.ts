import 'dotenv/config';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import request from 'supertest';

test('real PostgreSQL migrations, invariants, seed and catalog API', { timeout: 120000 }, async (t) => {
  const url = process.env.TEST_DATABASE_URL;
  assert.ok(url, 'Configure TEST_DATABASE_URL for a dedicated test database');
  assert.equal(new URL(url).pathname, '/food_delivery_test', 'Refusing mutations outside food_delivery_test');
  process.env.DATABASE_URL = url;
  process.env.NODE_ENV = 'test';
  execFileSync(process.execPath, ['node_modules/prisma/build/index.js', 'migrate', 'deploy'], {
    env: { ...process.env, DIRECT_URL: url }, stdio: 'pipe',
  });
  const { createDatabase } = require('../dist/src/database/client');
  const { seed } = require('../dist/prisma/seed');
  const { seedHyd } = require('../dist/prisma/seed_hyd');
  const { createApp } = require('../dist/src/main');
  const { DatabaseService } = require('../dist/src/database/database.module');
  const db = createDatabase(url);
  const app = await createApp();
  try {
    await seed(db);
    await seedHyd(db);
    const counts = async () => Promise.all([db.restaurant.count(), db.menuItem.count(), db.category.count()]);
    const [rc, mc, cc] = await counts();
    assert.ok(rc >= 4, `Expected at least 4 restaurants, got ${rc}`);
    assert.ok(mc >= 8, `Expected at least 8 menu items, got ${mc}`);
    assert.ok(cc >= 8, `Expected at least 8 categories, got ${cc}`);
    await seed(db);
    await seedHyd(db);
    const [rc2, mc2, cc2] = await counts();
    assert.ok(rc2 >= 4, `Expected at least 4 restaurants, got ${rc2}`);
    assert.ok(mc2 >= 8, `Expected at least 8 menu items, got ${mc2}`);
    assert.ok(cc2 >= 8, `Expected at least 8 categories, got ${cc2}`);
    assert.deepEqual([rc2, mc2, cc2], [rc, mc, cc]);
    await t.test('seed does not overwrite local edits', async () => {
      const original = await db.menuItem.findUniqueOrThrow({ where: { id: 'dosa' } });
      try {
        await db.menuItem.update({ where: { id: 'dosa' }, data: { basePricePaise: 14937 } });
        await seed(db);
        await seedHyd(db);
        assert.equal((await db.menuItem.findUniqueOrThrow({ where: { id: 'dosa' } })).basePricePaise, 14937);
      } finally {
        await db.menuItem.update({ where: { id: 'dosa' }, data: { basePricePaise: original.basePricePaise } });
      }
    });
    await t.test('foreign keys, unique keys, price and section ownership constraints', async () => {
      await assert.rejects(db.menuItem.update({ where: { id: 'dosa' }, data: { basePricePaise: -1 } }));
      await assert.rejects(db.menuItem.update({ where: { id: 'dosa' }, data: { categoryId: 'missing' } }));
      await assert.rejects(db.category.update({ where: { id: 'dosa' }, data: { slug: 'pizza' } }));
      await assert.rejects(db.menuItem.update({ where: { id: 'dosa' }, data: { sectionId: 'hearth-from-the-oven' } }));
      await assert.rejects(db.restaurant.delete({ where: { id: 'tiffin' } }));
    });
    await app.init();
    const api = request(app.getHttpServer());
    const get = async (path: string) => (await api.get(`/api/v1/${path}`).expect(200)).body.data;
    await t.test('all read endpoints return preserved records and exact paise', async () => {
      assert.deepEqual(await get('health'), { status: 'ok', database: 'up' });
      assert.ok((await get('categories')).length >= 16);
      assert.ok((await get('cuisines')).length >= 6);
      const list = await get('restaurants?limit=2&page=2');
      assert.ok(list.total >= 28); assert.equal(list.items.length, 2);
      assert.equal(list.items[0].id, 'table');
      assert.equal((await get('restaurants/tiffin')).name, 'The Tiffin Room');
      assert.equal((await get('restaurants/tiffin/menu')).sections.flatMap((s: any) => s.items).length, 4);
      const dish = await get('menu-items/dosa');
      assert.equal(dish.basePricePaise, 14900); assert.equal(dish.imageKey, 'dosa');
      assert.equal(dish.restaurant.id, 'tiffin'); assert.deepEqual(dish.variants, []);
    });
    await t.test('areas endpoint and area filtering enforce Hyderabad locality isolation', async () => {
      const areas = await get('areas');
      assert.ok(areas.length >= 10);
      const gachibowli = areas.find((a: any) => a.id === 'gachibowli');
      assert.ok(gachibowli);
      assert.ok(gachibowli.serviceableRestaurantCount > 0);

      const gachiRestaurants = await get('restaurants?area=gachibowli&limit=50');
      assert.ok(gachiRestaurants.total > 0);
      assert.ok(gachiRestaurants.items.every((r: any) => r.serviceAreas.some((sa: any) => sa.id === 'gachibowli')));
      assert.ok(!gachiRestaurants.items.some((r: any) => r.id === 'dakshin-sunrise-secund'));
      assert.ok(!gachiRestaurants.items.some((r: any) => r.id === 'clock-tower-secund'));

      const dosaSearch = await get('catalog/search?q=dosa&area=madhapur');
      assert.ok(dosaSearch.total >= 1);
      assert.ok(dosaSearch.items.some((d: any) => d.id === 'dosa'));
      assert.ok(dosaSearch.items.every((d: any) => d.restaurant.serviceAreas.some((sa: any) => sa.id === 'madhapur')));

      const biryani = await get('menu-items/dhd-chicken-dum-biryani');
      assert.ok(biryani.variants.length >= 2);
      assert.ok(biryani.addOns.length >= 2);
      const haleem = await get('menu-items/dhd-shahi-haleem');
      assert.equal(haleem.availabilityStatus, 'UNAVAILABLE');
      assert.ok(haleem.availabilityReason.includes('Ramzan'));
    });
    await t.test('database search intersects words, category, cuisine and paise filter', async () => {
      assert.ok((await get('catalog/search?q=%20ITALIAN%20')).total >= 2);
      assert.ok((await get('catalog/search?q=tomato%20basil&category=pasta')).items.some((i: any) => i.id === 'pasta'));
      assert.ok((await get('catalog/search?q=green%20table')).items.some((i: any) => i.id === 'salad'));
      assert.equal((await get('catalog/search?q=pizza&category=bowls')).total, 0);
      const affordable = await get('catalog/search?maxPricePaise=25000');
      assert.ok(affordable.items.every((d: any) => d.basePricePaise <= 25000));
      assert.ok((await get('catalog/search?cuisine=south-indian')).total >= 4);
      assert.equal((await get('catalog/search?limit=1&page=2')).items.length, 1);
      assert.equal((await get('catalog/search?q=%27%20OR%201=1--')).total, 0);
    });
    await t.test('invalid queries and missing records have safe, correlated errors', async () => {
      for (const path of ['restaurants?limit=51', 'restaurants?area=INVALID', 'catalog/search?page=0', 'catalog/search?extra=true', 'menu-items/INVALID', 'catalog/search?maxPricePaise=-1']) {
        const response = await api.get(`/api/v1/${path}`).expect(400);
        assert.equal(response.body.error.code, 'INVALID_REQUEST');
        assert.equal(response.body.requestId, response.headers['x-request-id']);
      }
      await api.get('/api/v1/menu-items/missing').expect(404);
      await api.get('/api/v1/restaurants/missing/menu').expect(404);
      await api.post('/api/v1/menu-items/dosa').send({ basePricePaise: 1 }).expect(404);
    });
    await t.test('representative real query plan is available', async () => {
      const plan = await db.$queryRawUnsafe('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT id FROM "MenuItem" WHERE "categoryId" = $1 ORDER BY "displayOrder", id LIMIT 20', 'dosa');
      assert.ok(plan[0]['QUERY PLAN'][0]['Execution Time'] >= 0);
      console.log(JSON.stringify({ queryPlan: plan[0]['QUERY PLAN'][0] }));
    });
    await t.test('actual connection refusal becomes a safe API 503', async () => {
      const service = app.get(DatabaseService);
      const original = service.client;
      const unavailable = new URL(url); unavailable.port = '1';
      const failed = createDatabase(unavailable.toString());
      service.client = failed;
      try {
        const response = await api.get('/api/v1/health').expect(503);
        assert.equal(response.body.error.message, 'Database unavailable');
        const catalogResponse = await api.get('/api/v1/restaurants').expect(503);
        assert.equal(catalogResponse.body.error.message, 'Service temporarily unavailable');
      } finally { service.client = original; await failed.$disconnect(); }
    });
  } finally { await app.close(); await db.$disconnect(); }
});
