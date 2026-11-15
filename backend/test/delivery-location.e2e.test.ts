import 'dotenv/config';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import request from 'supertest';

// Synthetic test coordinates only (isolated test database). Not real customer or restaurant locations.
const PIN = { latitude: 17.448123, longitude: 78.391456 };

test('customer delivery location, ownership and server-side serviceability', { timeout: 120000 }, async (t) => {
  const url = process.env.TEST_DATABASE_URL!;
  assert.equal(new URL(url).pathname, '/food_delivery_test');
  process.env.DATABASE_URL = url;
  process.env.NODE_ENV = 'test';
  process.env.DEMO_CHECKOUT_ENABLED = 'true';
  execFileSync(process.execPath, ['node_modules/prisma/build/index.js', 'migrate', 'deploy'], {
    env: { ...process.env, DIRECT_URL: url },
    stdio: 'pipe',
  });
  const { createDatabase } = require('../dist/src/database/client');
  const { createApp } = require('../dist/src/main');
  const { PasswordService } = require('../dist/src/modules/auth/password.service');
  const { evaluateServiceability, haversineMeters } = require('../dist/src/modules/commerce/serviceability');

  const db = createDatabase(url);
  const app = await createApp();
  const password = randomUUID();
  const rid = 'deccan-handi-gachi';
  const original = await db.restaurant.findUniqueOrThrow({
    where: { id: rid },
    select: { latitude: true, longitude: true, pickupLocationVerifiedAt: true, deliveryRadiusMeters: true },
  });
  const covered = (await db.restaurantDeliveryZone.findFirstOrThrow({ where: { restaurantId: rid, isEligible: true, zone: { isActive: true } } })).zoneId;
  const uncovered = (await db.locality.findFirstOrThrow({
    where: { isActive: true, id: { notIn: (await db.restaurantDeliveryZone.findMany({ where: { restaurantId: rid, isEligible: true } })).map((z: any) => z.zoneId) } },
  })).id;
  const users: any[] = [];
  const tokens: string[] = [];
  // One fixed fixture item (upserted) so repeated runs never accumulate catalog rows in the test DB.
  const itemId = 'c1-loc-fixture';

  try {
    const hash = await new PasswordService().hash(password);
    for (const role of ['CUSTOMER', 'CUSTOMER', 'DELIVERY_PARTNER', 'RESTAURANT_OWNER']) {
      users.push(await db.user.create({
        data: {
          email: `c1-${randomUUID()}@test.invalid`, displayName: 'Synthetic Location Test', passwordHash: hash,
          roles: { create: { roleName: role } },
          ...(role === 'RESTAURANT_OWNER' ? { memberships: { create: { restaurantId: rid } } } : {}),
        },
      }));
    }
    const section = await db.menuSection.findFirstOrThrow({ where: { restaurantId: rid } });
    const fixture = { restaurantId: rid, sectionId: section.id, categoryId: 'dosa', name: 'Synthetic location meal', description: 'C1 fixture', imageKey: 'dosa', basePricePaise: 12000, isVegetarian: true, availabilityStatus: 'AVAILABLE' as const };
    await db.menuItem.upsert({ where: { id: itemId }, create: { id: itemId, ...fixture }, update: fixture });

    await app.init();
    const api = request(app.getHttpServer());
    for (const u of users) tokens.push((await api.post('/api/v1/auth/login').send({ email: u.email, password }).expect(200)).body.data.session.token);
    const call = (method: string, path: string, i = 0) => (api as any)[method](`/api/v1/${path}`).set('Authorization', `Bearer ${tokens[i]}`);
    const base = { label: 'Home', recipientName: 'Test Customer', contactNumber: '9999999999', addressLine1: '1 Synthetic Test Lane', postalCode: '500081', city: 'Hyderabad', isDefault: true };

    let gps: any, pin: any, legacy: any, outside: any, uncov: any;

    await t.test('saves an address with device GPS coordinates; map pins carry no GPS accuracy', async () => {
      gps = (await call('post', 'addresses').send({ ...base, localityId: covered, ...PIN, locationAccuracyMeters: 12.5, locationSource: 'DEVICE_GPS' }).expect(201)).body.data;
      assert.equal(gps.latitude, PIN.latitude);
      assert.equal(gps.longitude, PIN.longitude);
      assert.equal(typeof gps.latitude, 'number');
      assert.equal(gps.locationSource, 'DEVICE_GPS');
      assert.equal(gps.locationAccuracyMeters, 12.5);
      assert.equal(gps.hasConfirmedLocation, true);
      assert.ok(gps.locationConfirmedAt);
      pin = (await call('post', 'addresses').send({ ...base, label: 'Family', addressLine1: '2 Synthetic Test Lane', isDefault: false, localityId: covered, latitude: 17.45, longitude: 78.38, locationAccuracyMeters: 30, locationSource: 'CUSTOMER_MAP_PIN' }).expect(201)).body.data;
      assert.equal(pin.locationSource, 'CUSTOMER_MAP_PIN');
      assert.equal(pin.locationAccuracyMeters, null);
    });

    await t.test('rejects invalid or inconsistent coordinates', async () => {
      const bad = [
        [{ latitude: 95, longitude: 78, locationSource: 'DEVICE_GPS' }, 400],
        [{ latitude: 17, longitude: 190, locationSource: 'DEVICE_GPS' }, 400],
        [{ latitude: 'NaN', longitude: 78, locationSource: 'DEVICE_GPS' }, 400],
        [{ latitude: 17.4, longitude: 78.3, locationSource: 'DEVICE_GPS', locationAccuracyMeters: 900 }, 400],
        [{ latitude: 17.4, longitude: 78.3, locationSource: 'SATELLITE' }, 400],
        [{ latitude: 17.4, locationSource: 'DEVICE_GPS' }, 422],
        [{ latitude: 17.4, longitude: 78.3 }, 422],
        [{ locationSource: 'DEVICE_GPS' }, 422],
        [{ localityId: 'missing-area' }, 422],
      ] as const;
      for (const [extra, status] of bad) {
        await call('post', 'addresses').send({ ...base, label: 'Bad', localityId: covered, ...extra }).expect(status);
      }
    });

    await t.test('legacy payloads (no city, no coordinates) still work and are flagged unverified', async () => {
      const { city: _c, ...old } = base;
      legacy = (await call('post', 'addresses').send({ ...old, label: 'Legacy', addressLine1: '3 Synthetic Test Lane', isDefault: false, localityId: covered }).expect(201)).body.data;
      assert.equal(legacy.latitude, null);
      assert.equal(legacy.hasConfirmedLocation, false);
      assert.equal(legacy.locationSource, null);
      outside = (await call('post', 'addresses').send({ ...base, label: 'Outside', addressLine1: '4 Synthetic Test Lane', isDefault: false, localityId: null, latitude: 17.55, longitude: 78.37, locationSource: 'CUSTOMER_MAP_PIN' }).expect(201)).body.data;
      assert.equal(outside.localityId, null);
      uncov = (await call('post', 'addresses').send({ ...base, label: 'Uncovered', addressLine1: '5 Synthetic Test Lane', isDefault: false, localityId: uncovered }).expect(201)).body.data;
    });

    await t.test('editing moves the pin, keeps confirmation time for unchanged pins, and can remove coordinates', async () => {
      const unchanged = (await call('patch', `addresses/${gps.id}`).send({ ...base, localityId: covered, ...PIN, locationAccuracyMeters: 12.5, locationSource: 'DEVICE_GPS', landmark: 'Near synthetic park' }).expect(200)).body.data;
      assert.equal(unchanged.locationConfirmedAt, gps.locationConfirmedAt);
      assert.equal(unchanged.landmark, 'Near synthetic park');
      const moved = (await call('patch', `addresses/${pin.id}`).send({ ...base, label: 'Family', addressLine1: '2 Synthetic Test Lane', isDefault: false, localityId: covered, latitude: 17.4512, longitude: 78.3811, locationSource: 'CUSTOMER_MAP_PIN' }).expect(200)).body.data;
      assert.equal(moved.latitude, 17.4512);
      assert.notEqual(moved.locationConfirmedAt, pin.locationConfirmedAt);
      const cleared = (await call('patch', `addresses/${pin.id}`).send({ ...base, label: 'Family', addressLine1: '2 Synthetic Test Lane', isDefault: false, localityId: covered, latitude: null, longitude: null, locationSource: null }).expect(200)).body.data;
      assert.equal(cleared.latitude, null);
      assert.equal(cleared.locationConfirmedAt, null);
      assert.equal((await call('get', 'addresses').expect(200)).body.data.length, 5);
    });

    await t.test('ownership and role isolation: no cross-customer or cross-role access to addresses', async () => {
      await call('patch', `addresses/${gps.id}`, 1).send({ ...base, localityId: covered }).expect(404);
      await call('delete', `addresses/${gps.id}`, 1).expect(404);
      await call('get', `addresses/${gps.id}/serviceability`, 1).expect(404);
      assert.equal((await call('get', 'addresses', 1).expect(200)).body.data.length, 0);
      await call('get', 'addresses', 2).expect(403); // rider
      await call('get', 'addresses', 3).expect(403); // owner
      await call('get', `addresses/${gps.id}/serviceability`, 2).expect(403);
      await api.get(`/api/v1/addresses/${gps.id}/serviceability`).expect(401);
      // Customer cannot use rider presence; rider presence never exposes customer addresses.
      await call('post', 'rider/presence/online', 0).send({ latitude: 17.4, longitude: 78.3, accuracy: 10 }).expect(403);
      const stored = await db.customerAddress.findUniqueOrThrow({ where: { id: gps.id } });
      assert.equal(Number(stored.latitude), PIN.latitude);
    });

    await t.test('serviceability endpoint: service-area coverage is labelled distance-unverified; uncovered and outside areas are not serviceable', async () => {
      const ok = (await call('get', `addresses/${gps.id}/serviceability`).expect(200)).body.data;
      const r = ok.restaurants.find((x: any) => x.restaurantId === rid);
      assert.equal(r.eligible, true);
      assert.equal(r.status, 'SERVICEABLE_UNVERIFIED_DISTANCE');
      assert.equal(r.basis, 'SERVICE_AREA');
      assert.equal(r.straightLineMeters, null, 'no distance may be claimed without a verified pickup point');
      assert.match(r.reason, /not verified/);
      assert.equal(ok.serviceArea.id, covered);
      const no = (await call('get', `addresses/${uncov.id}/serviceability`).expect(200)).body.data.restaurants.find((x: any) => x.restaurantId === rid);
      assert.equal(no.eligible, false);
      assert.equal(no.status, 'NOT_SERVICEABLE');
      const out = (await call('get', `addresses/${outside.id}/serviceability`).expect(200)).body.data;
      assert.equal(out.serviceArea, null);
      assert.ok(out.restaurants.every((x: any) => x.eligible === false), 'no restaurant may claim to serve an address outside configured service areas');
    });

    let cart: any;
    await t.test('cart add without a preview area is accepted; quote enforces serviceability and snapshots the confirmed point', async () => {
      cart = (await call('get', 'cart').expect(200)).body.data;
      cart = (await call('post', 'cart/items').send({ restaurantId: rid, menuItemId: itemId, quantity: 1, addOnIds: [], expectedVersion: cart.version }).expect(200)).body.data;
      const rejected = await call('post', 'cart/quote').send({ addressId: uncov.id, expectedVersion: cart.version }).expect(422);
      assert.match(rejected.body.error.message, /does not deliver/);
      await call('post', 'cart/quote').send({ addressId: outside.id, expectedVersion: cart.version }).expect(422);
      const quote = (await call('post', 'cart/quote').send({ addressId: gps.id, expectedVersion: cart.version }).expect(200)).body.data;
      assert.deepEqual(quote.address.location, { ...PIN, source: 'DEVICE_GPS' });
      assert.equal(quote.address.serviceability.basis, 'SERVICE_AREA');
      assert.match(quote.notice, /not verified/);
      // Another customer's address can never be used for a quote.
      const foreign = await call('post', 'cart/quote', 1).send({ addressId: gps.id, expectedVersion: 1 });
      assert.ok([404, 409, 422].includes(foreign.status), `foreign address quote status ${foreign.status}`);
      assert.equal(foreign.body.data, undefined, 'no quote may be produced for another customer address');
    });

    await t.test('checkout re-validates: an address moved out of coverage after quoting is rejected', async () => {
      const quote = (await call('post', 'cart/quote').send({ addressId: legacy.id, expectedVersion: cart.version }).expect(200)).body.data;
      await call('patch', `addresses/${legacy.id}`).send({ ...base, label: 'Legacy', addressLine1: '3 Synthetic Test Lane', isDefault: false, localityId: uncovered }).expect(200);
      const res = await call('post', 'orders').send({ cartId: cart.id, addressId: legacy.id, quoteId: quote.quoteId, idempotencyKey: randomUUID(), paymentMethod: 'DEMO_NO_PAYMENT' });
      assert.equal(res.status, 422);
      assert.equal(await db.order.count({ where: { customerId: users[0].id } }), 0);
    });

    await t.test('verified restaurant pickup point + radius: straight-line distance is authoritative over service-area coverage', async () => {
      // Test-DB only: give the restaurant a synthetic verified pickup point 1.0 km from PIN.
      await db.restaurant.update({ where: { id: rid }, data: { latitude: 17.448123, longitude: 78.400900, pickupLocationVerifiedAt: new Date(), deliveryRadiusMeters: 3000 } });
      const near = (await call('get', `addresses/${gps.id}/serviceability`).expect(200)).body.data.restaurants.find((x: any) => x.restaurantId === rid);
      assert.equal(near.basis, 'VERIFIED_DISTANCE');
      assert.equal(near.status, 'SERVICEABLE');
      assert.ok(near.straightLineMeters > 900 && near.straightLineMeters < 1100, `distance ${near.straightLineMeters}`);
      assert.match(near.reason, /straight line/);
      // Same covered service area, but the confirmed point is ~20 km away: rejected despite zone coverage.
      const far = (await call('post', 'addresses').send({ ...base, label: 'Far', addressLine1: '6 Synthetic Test Lane', isDefault: false, localityId: covered, latitude: 17.628, longitude: 78.401, locationSource: 'CUSTOMER_MAP_PIN' }).expect(201)).body.data;
      const farS = (await call('get', `addresses/${far.id}/serviceability`).expect(200)).body.data.restaurants.find((x: any) => x.restaurantId === rid);
      assert.equal(farS.eligible, false);
      assert.equal(farS.basis, 'VERIFIED_DISTANCE');
      await call('post', 'cart/quote').send({ addressId: far.id, expectedVersion: cart.version }).expect(422);
      // An address without coordinates falls back to service-area coverage, still labelled unverified.
      const leg = (await call('get', `addresses/${pin.id}/serviceability`).expect(200)).body.data.restaurants.find((x: any) => x.restaurantId === rid);
      assert.equal(leg.basis, 'SERVICE_AREA');
      assert.match(leg.reason, /no confirmed map location/);
      const ok = (await call('post', 'cart/quote').send({ addressId: gps.id, expectedVersion: cart.version }).expect(200)).body.data;
      assert.match(ok.notice, /straight-line/);
      const order = (await call('post', 'orders').send({ cartId: cart.id, addressId: gps.id, quoteId: ok.quoteId, idempotencyKey: randomUUID(), paymentMethod: 'DEMO_NO_PAYMENT' }).expect(200)).body.data;
      const stored = await db.order.findUniqueOrThrow({ where: { id: order.id } });
      assert.equal((stored.deliveryAddressSnapshot as any).location.latitude, PIN.latitude, 'checkout uses the selected destination, not any device position');
      // Restaurant owner never receives the delivery snapshot (coordinates included).
      const ownerView = (await call('get', `operations/restaurant/orders/${order.id}`, 3).expect(200)).body.data;
      assert.equal(ownerView.deliveryAddressSnapshot, undefined);
    });

    await t.test('policy unit checks', () => {
      const d = haversineMeters(17.385, 78.4867, 17.4401, 78.3489);
      assert.ok(d > 15000 && d < 16500);
      const r = { id: 'x', name: 'X', latitude: null, longitude: null, pickupLocationVerifiedAt: null, deliveryRadiusMeters: 5000, zones: [] };
      assert.equal(evaluateServiceability(r, { localityId: null, latitude: 17, longitude: 78 }).eligible, false);
      // Unverified coordinates are ignored for distance claims.
      const unverified = { ...r, latitude: 17, longitude: 78, zones: [{ zoneId: 'a', isEligible: true }] };
      const res = evaluateServiceability(unverified, { localityId: 'a', latitude: 17, longitude: 78 });
      assert.equal(res.basis, 'SERVICE_AREA');
      assert.equal(res.straightLineMeters, null);
    });
  } finally {
    await db.restaurant.update({ where: { id: rid }, data: original });
    await app.close();
    await db.$disconnect();
  }
});
