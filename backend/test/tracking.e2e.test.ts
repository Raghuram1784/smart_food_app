import 'dotenv/config';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import request from 'supertest';
import { io, Socket } from 'socket.io-client';

/**
 * F4 live tracking and smart ETA on the isolated test database.
 * Coordinates below are synthetic test fixtures sent through the real API; they are never
 * used by the application itself (the app only publishes real device fixes).
 */
test('live rider tracking: GPS-independent dispatch, authorized fixes, private reads, ETA labels, termination', { timeout: 240000 }, async (t) => {
  const url = process.env.TEST_DATABASE_URL!;
  assert.equal(new URL(url).pathname, '/food_delivery_test');
  Object.assign(process.env, { DATABASE_URL: url, NODE_ENV: 'test', DEMO_AUTH_ENABLED: 'true', ROUTING_PROVIDER: 'none',
    HANDOVER_HMAC_KEY: randomBytes(32).toString('hex'), HANDOVER_ENCRYPTION_KEY: randomBytes(32).toString('hex') });
  execFileSync(process.execPath, ['node_modules/prisma/build/index.js', 'migrate', 'deploy'], { env: { ...process.env, DIRECT_URL: url }, stdio: 'pipe' });
  const { createDatabase } = require('../dist/src/database/client');
  const { createApp } = require('../dist/src/main');
  const { PasswordService } = require('../dist/src/modules/auth/password.service');
  const { HandoverRateGuard } = require('../dist/src/modules/operations/handover.controller');
  const { TrackingService } = require('../dist/src/modules/tracking/tracking.service');

  const db = createDatabase(url);
  const app = await createApp();
  const password = randomBytes(24).toString('base64url');
  const rid = 'deccan-handi-gachi';
  const u: Record<string, any> = {}, tok: Record<string, string> = {};
  const orders: string[] = [];
  const sockets: Socket[] = [];
  const before = await db.restaurant.findUniqueOrThrow({ where: { id: rid }, select: { latitude: true, longitude: true, pickupLocationVerifiedAt: true } });
  try {
    const hash = await new PasswordService().hash(password);
    await db.riderPresence.updateMany({ where: { isOnline: true }, data: { isOnline: false } });
    const roles: Record<string, [string, string?]> = { customer: ['CUSTOMER'], other: ['CUSTOMER'], owner: ['RESTAURANT_OWNER', rid], otherOwner: ['RESTAURANT_OWNER', 'tiffin'], admin: ['ADMIN'], r1: ['DELIVERY_PARTNER'], r2: ['DELIVERY_PARTNER'] };
    for (const [key, [role, restaurantId]] of Object.entries(roles)) {
      await db.role.upsert({ where: { name: role }, update: {}, create: { name: role } });
      u[key] = await db.user.create({ data: { email: `f4-${key.toLowerCase()}-${randomUUID()}@test.invalid`, displayName: `Track ${key}`, passwordHash: hash, roles: { create: { roleName: role } },
        ...(restaurantId ? { memberships: { create: { restaurantId } } } : {}) } });
    }
    await app.listen(0, '127.0.0.1');
    const base = (await app.getUrl()).replace('[::1]', '127.0.0.1');
    const api = request(app.getHttpServer());
    app.get(HandoverRateGuard).buckets.clear();
    for (const [key, user] of Object.entries(u)) tok[key] = (await api.post('/api/v1/auth/login').send({ email: user.email, password }).expect(200)).body.data.session.token;
    const call = (method: string, path: string, who: string) => (api as any)[method](`/api/v1/${path}`).set('Authorization', `Bearer ${tok[who]}`);
    const fix = (over: Record<string, unknown> = {}, ageMs = 0) => ({ latitude: 17.4483, longitude: 78.3915, accuracyMeters: 8, headingDegrees: 90, speedMps: 6, recordedAt: new Date(Date.now() - ageMs).toISOString(), ...over });
    const connect = (who: string) => new Promise<Socket>((resolve, reject) => {
      const s = io(base, { auth: { token: tok[who] }, transports: ['websocket'], forceNew: true, reconnection: false, timeout: 3000 }); sockets.push(s);
      s.once('connect', () => resolve(s)); s.once('connect_error', reject); setTimeout(() => reject(Error('socket timeout')), 4000).unref();
    });

    // Synthetic order with a confirmed drop pin in the address snapshot, marked Ready by the real owner API.
    const cart = await db.cart.upsert({ where: { customerId: u.customer.id }, update: {}, create: { customerId: u.customer.id } });
    const item = await db.menuItem.findFirstOrThrow({ where: { restaurantId: rid } });
    const o0 = await db.order.create({ data: {
      orderNumber: 'FD-F4-' + randomBytes(4).toString('hex').toUpperCase(), customerId: u.customer.id, restaurantId: rid, restaurantName: 'Deccan Handi & Dum',
      cartId: cart.id, cartVersion: 7000 + Math.floor(Math.random() * 1000), idempotencyKey: randomUUID(), requestHash: '0'.repeat(64),
      deliveryAddressSnapshot: { recipientName: 'Synthetic', addressLine1: '1 Test Lane', localityName: 'Madhapur', postalCode: '500081', location: { latitude: 17.4401, longitude: 78.3489, source: 'MAP' } },
      pricingPolicyVersion: 'v1', pricingSnapshot: {}, itemSubtotalPaise: 20000, customizationTotalPaise: 0, packagingPaise: 0, deliveryPaise: 0, platformPaise: 0, discountPaise: 0, taxPaise: 0, finalPayablePaise: 20000,
      status: 'PREPARING', items: { create: { menuItemId: item.id, name: item.name, imageKey: item.imageKey, baseUnitPaise: 20000, quantity: 1, lineTotalPaise: 20000 } } } });
    orders.push(o0.id);
    let order = (await call('post', `operations/restaurant/orders/${o0.id}/ready`, 'owner').send({ expectedVersion: o0.version }).expect(200)).body.data;
    const id = order.id;

    await t.test('dispatch stays GPS-free: go online and accept an invitation without any location', async () => {
      await call('post', 'rider/presence/online', 'r1').send({}).expect(200);
      const offers = (await call('get', 'operations/delivery/offers', 'r1').expect(200)).body.data.offers;
      const mine = offers.find((x: any) => x.orderId === id);
      assert.ok(mine, 'invitation arrives without location permission');
      await call('post', `operations/delivery/offers/${mine.id}/accept`, 'r1').send({}).expect(200);
      const view = (await call('get', `tracking/orders/${id}`, 'customer').expect(200)).body.data;
      assert.equal(view.trackingActive, true);
      assert.equal(view.rider.freshness, 'WAITING', 'no fix yet: waiting, not live');
      assert.equal(view.rider.location, null);
    });

    await t.test('only the assigned rider can publish; invalid, future, stale and inaccurate fixes are rejected', async () => {
      await api.post(`/api/v1/tracking/orders/${id}/location`).send(fix()).expect(401);
      await call('post', `tracking/orders/${id}/location`, 'r2').send(fix()).expect(403);
      for (const who of ['customer', 'owner', 'admin']) await call('post', `tracking/orders/${id}/location`, who).send(fix()).expect(403);
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({ latitude: 95 })).expect(400);
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({ latitude: 0, longitude: 0 })).expect(422);
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({ accuracyMeters: 5000 })).expect(422);
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({ speedMps: 500 })).expect(422);
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({ recordedAt: new Date(Date.now() + 120000).toISOString() })).expect(422);
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({}, 5 * 60000)).expect(422);
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({ recordedAt: 'yesterday' })).expect(400);
      assert.equal(await db.deliveryTracking.count({ where: { orderId: id, latitude: { not: null } } }), 0, 'nothing stored from rejected fixes');
    });

    await t.test('valid fix is stored once (latest only), pushed only to the authorized customer socket', async () => {
      const mineSock = await connect('customer'), otherSock = await connect('other');
      const got: any[] = [], leaked: any[] = [];
      mineSock.on('delivery.location', (e: any) => got.push(e)); otherSock.on('delivery.location', (e: any) => leaked.push(e));
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({}, 6000)).expect(200);
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({}, 7000)).expect(409); // out of order
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({}, 5500)).expect(429); // too frequent
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({ latitude: 17.4470, longitude: 78.3900 }, 1000)).expect(200);
      await new Promise((r) => setTimeout(r, 400));
      assert.ok(got.length >= 1 && got.every((e) => e.orderId === id));
      assert.equal(got.at(-1).latitude, 17.447);
      assert.equal(leaked.length, 0, 'another customer never receives this rider location');
      assert.equal(await db.deliveryTracking.count({ where: { orderId: id } }), 1, 'no location history rows');
    });

    await t.test('reads: customer, assigned rider, outlet owner and admin only; ETA and freshness', async () => {
      const v = (await call('get', `tracking/orders/${id}`, 'customer').expect(200)).body.data;
      assert.equal(v.rider.freshness, 'LIVE');
      assert.equal(v.rider.location.latitude, 17.447);
      assert.equal(v.destination.source, 'SAVED_ADDRESS');
      assert.equal(v.eta.phase, 'TO_RESTAURANT');
      assert.equal(v.eta.source, 'ESTIMATE');
      assert.equal(v.restaurant.location, null, 'no fabricated restaurant coordinates');
      for (const who of ['r1', 'owner', 'admin']) await call('get', `tracking/orders/${id}`, who).expect(200);
      for (const who of ['other', 'r2', 'otherOwner']) await call('get', `tracking/orders/${id}`, who).expect(404);
    });

    await t.test('owner confirms the pickup point; other outlets cannot; imprecise GPS refused', async () => {
      await call('put', `tracking/restaurants/${rid}/pickup-location`, 'otherOwner').send({ latitude: 17.45, longitude: 78.38 }).expect(403);
      await call('put', `tracking/restaurants/${rid}/pickup-location`, 'owner').send({ latitude: 17.45, longitude: 78.38, accuracyMeters: 400 }).expect(422);
      await call('put', `tracking/restaurants/${rid}/pickup-location`, 'owner').send({ latitude: 17.4502, longitude: 78.3811, accuracyMeters: 12 }).expect(200);
      const v = (await call('get', `tracking/orders/${id}`, 'customer').expect(200)).body.data;
      assert.deepEqual(v.restaurant.location, { latitude: 17.4502, longitude: 78.3811 });
    });

    await t.test('in transit without a routing service: ETA is a labeled estimate, never road distance', async () => {
      order = (await call('get', `operations/delivery/orders/${id}`, 'r1').expect(200)).body.data;
      order = (await call('post', `operations/delivery/orders/${id}/pickup`, 'r1').send({ expectedVersion: order.version }).expect(200)).body.data;
      order = (await call('post', `operations/delivery/orders/${id}/out-for-delivery`, 'r1').send({ expectedVersion: order.version }).expect(200)).body.data;
      await new Promise((r) => setTimeout(r, 2100));
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix({ latitude: 17.4440, longitude: 78.3700 })).expect(200);
      const v = (await call('get', `tracking/orders/${id}`, 'customer').expect(200)).body.data;
      assert.equal(v.eta.phase, 'TO_CUSTOMER');
      assert.equal(v.eta.source, 'ESTIMATE');
      assert.equal(v.eta.distanceMeters, null, 'no road distance claimed');
      assert.ok(v.eta.straightLineMeters > 1000 && v.eta.seconds > 0);
      assert.match(v.eta.basis, /no road route/);
      assert.equal(v.route, null);
      assert.equal(v.routing.configured, false);
    });

    await t.test('customer can confirm a drop pin for this order only', async () => {
      await call('put', `tracking/orders/${id}/destination`, 'other').send({ latitude: 17.44, longitude: 78.35 }).expect(404);
      const v = (await call('put', `tracking/orders/${id}/destination`, 'customer').send({ latitude: 17.4395, longitude: 78.3495 }).expect(200)).body.data;
      assert.equal(v.destination.source, 'CUSTOMER_PIN');
    });

    await t.test('stale and unavailable fixes are labeled; no LIVE badge on old data', async () => {
      await db.deliveryTracking.update({ where: { orderId: id }, data: { recordedAt: new Date(Date.now() - 60000) } });
      let v = (await call('get', `tracking/orders/${id}`, 'customer').expect(200)).body.data;
      assert.equal(v.rider.freshness, 'STALE'); assert.ok(v.rider.ageSeconds >= 59);
      await db.deliveryTracking.update({ where: { orderId: id }, data: { recordedAt: new Date(Date.now() - 300000) } });
      v = (await call('get', `tracking/orders/${id}`, 'customer').expect(200)).body.data;
      assert.equal(v.rider.freshness, 'UNAVAILABLE');
      assert.match(v.eta.basis, /rider location unavailable/);
    });

    await t.test('OTP delivery ends tracking: further fixes refused, location hidden, row removed', async () => {
      const pin = (await call('get', `orders/${id}/handover`, 'customer').expect(200)).body.data.pin;
      order = (await call('get', `operations/delivery/orders/${id}`, 'r1').expect(200)).body.data;
      await call('post', `operations/delivery/orders/${id}/complete-handover`, 'r1').send({ pin, expectedVersion: order.version }).expect(200);
      await call('post', `tracking/orders/${id}/location`, 'r1').send(fix()).expect(410);
      const v = (await call('get', `tracking/orders/${id}`, 'customer').expect(200)).body.data;
      assert.equal(v.trackingActive, false); assert.equal(v.rider.location, null); assert.equal(v.rider.freshness, 'ENDED'); assert.equal(v.eta.phase, 'DELIVERED');
      await app.get(TrackingService).sweep();
      assert.equal(await db.deliveryTracking.count({ where: { orderId: id } }), 0, 'latest fix and drop pin are not retained');
    });
  } finally {
    for (const s of sockets) s.close();
    await db.restaurant.update({ where: { id: rid }, data: before });
    await db.deliveryTracking.deleteMany({ where: { orderId: { in: orders } } });
    await db.deliveryOffer.deleteMany({ where: { orderId: { in: orders } } });
    await db.riderPresence.updateMany({ where: { userId: { in: Object.values(u).map((x: any) => x.id) } }, data: { isOnline: false } });
    await app.close();
    await db.$disconnect();
  }
});
