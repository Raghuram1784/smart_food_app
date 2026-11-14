import 'dotenv/config';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import request from 'supertest';

test('GPS-free rider presence, automatic invitations, atomic accept and automatic delivery OTP', { timeout: 180000 }, async (t) => {
  const url = process.env.TEST_DATABASE_URL!;
  assert.equal(new URL(url).pathname, '/food_delivery_test');
  process.env.DATABASE_URL = url;
  process.env.NODE_ENV = 'test';
  process.env.DEMO_AUTH_ENABLED = 'true';
  process.env.HANDOVER_HMAC_KEY = randomBytes(32).toString('hex');
  process.env.HANDOVER_ENCRYPTION_KEY = randomBytes(32).toString('hex');
  execFileSync(process.execPath, ['node_modules/prisma/build/index.js', 'migrate', 'deploy'], { env: { ...process.env, DIRECT_URL: url }, stdio: 'pipe' });

  const { createDatabase } = require('../dist/src/database/client');
  const { createApp } = require('../dist/src/main');
  const { PasswordService } = require('../dist/src/modules/auth/password.service');
  const { HandoverRateGuard } = require('../dist/src/modules/operations/handover.controller');
  const crypto = require('../dist/src/modules/operations/handover.crypto');

  const db = createDatabase(url);
  const app = await createApp();
  const password = randomBytes(24).toString('base64url');
  const rid = 'deccan-handi-gachi';
  const u: Record<string, any> = {};
  const tok: Record<string, string> = {};
  const orders: string[] = [];

  try {
    const hash = await new PasswordService().hash(password);
    // Riders already online in the shared test DB would also receive offers; isolate them.
    await db.riderPresence.updateMany({ where: { isOnline: true }, data: { isOnline: false } });
    const roles: Record<string, string> = { customer: 'CUSTOMER', owner: 'RESTAURANT_OWNER', admin: 'ADMIN', r1: 'DELIVERY_PARTNER', r2: 'DELIVERY_PARTNER', r3: 'DELIVERY_PARTNER' };
    for (const [key, role] of Object.entries(roles)) {
      await db.role.upsert({ where: { name: role }, update: {}, create: { name: role } });
      u[key] = await db.user.create({
        data: {
          email: `dispatch-${key}-${randomUUID()}@test.invalid`, displayName: `Dispatch ${key}`, passwordHash: hash,
          roles: { create: { roleName: role } },
          ...(role === 'RESTAURANT_OWNER' ? { memberships: { create: { restaurantId: rid } } } : {}),
        },
      });
    }
    await app.init();
    const api = request(app.getHttpServer());
    const guard = app.get(HandoverRateGuard);
    for (const [key, user] of Object.entries(u)) tok[key] = (await api.post('/api/v1/auth/login').send({ email: user.email, password }).expect(200)).body.data.session.token;
    const call = (method: string, path: string, who: string) => (api as any)[method](`/api/v1/${path}`).set('Authorization', `Bearer ${tok[who]}`);
    const online = (who: string) => call('post', 'rider/presence/online', who).send({}).expect(200);
    const offline = (who: string) => call('post', 'rider/presence/offline', who).send({}).expect(200);
    const offersOf = async (who: string) => (await call('get', 'operations/delivery/offers', who).expect(200)).body.data;

    const cart = await db.cart.upsert({ where: { customerId: u.customer.id }, update: {}, create: { customerId: u.customer.id } });
    let cartVersion = 1000;
    /** A synthetic order in PREPARING with one item, then marked Ready by the real owner API. */
    const readyOrder = async () => {
      const item = await db.menuItem.findFirstOrThrow({ where: { restaurantId: rid } });
      const o = await db.order.create({
        data: {
          orderNumber: 'FD-DISPATCH-' + randomBytes(4).toString('hex').toUpperCase(), customerId: u.customer.id, restaurantId: rid, restaurantName: 'Deccan Handi & Dum',
          cartId: cart.id, cartVersion: ++cartVersion, idempotencyKey: randomUUID(), requestHash: '0'.repeat(64),
          deliveryAddressSnapshot: { recipientName: 'Synthetic', contactNumber: '9999999999', addressLine1: '1 Test Lane', localityName: 'Madhapur', postalCode: '500081' },
          pricingPolicyVersion: 'v1', pricingSnapshot: {}, itemSubtotalPaise: 20000, customizationTotalPaise: 0, packagingPaise: 0, deliveryPaise: 0, platformPaise: 0, discountPaise: 0, taxPaise: 0, finalPayablePaise: 20000,
          status: 'PREPARING', items: { create: { menuItemId: item.id, name: item.name, imageKey: item.imageKey, baseUnitPaise: 20000, quantity: 2, lineTotalPaise: 40000 } },
        },
      });
      orders.push(o.id);
      return (await call('post', `operations/restaurant/orders/${o.id}/ready`, 'owner').send({ expectedVersion: o.version }).expect(200)).body.data;
    };

    await t.test('presence is a plain Online/Offline toggle: no GPS fields accepted or required', async () => {
      await api.post('/api/v1/rider/presence/online').expect(401);
      for (const who of ['customer', 'owner', 'admin']) await call('post', 'rider/presence/online', who).send({}).expect(403);
      // Location is neither required nor stored, even if an old client sends it.
      await call('post', 'rider/presence/online', 'r1').send({ latitude: 17.4, longitude: 78.3, accuracy: 5 }).expect(200);
      const row = await db.riderPresence.findUniqueOrThrow({ where: { userId: u.r1.id } });
      assert.equal(row.latitude, null);
      assert.equal(row.locationTimestamp, null);
      await call('post', 'rider/presence/location', 'r1').send({}).expect(404);
      const on = (await online('r1')).body.data;
      assert.equal(on.isOnline, true);
      assert.equal(on.isAvailable, true);
      assert.equal('latitude' in on, false);
      assert.equal((await offline('r1')).body.data.isAvailable, false);
    });

    let order: any;
    await t.test('Ready for Pickup invites every eligible online rider; offline riders get nothing', async () => {
      await online('r1');
      await online('r2');
      await offline('r3');
      order = await readyOrder();
      assert.equal(order.status, 'READY_FOR_PICKUP');
      const o1 = await offersOf('r1');
      const mine = o1.offers.find((x: any) => x.orderId === order.id);
      assert.ok(mine, 'online rider r1 is invited');
      assert.equal(mine.restaurantName, 'Deccan Handi & Dum');
      assert.equal(mine.orderNumber, order.orderNumber);
      assert.equal(mine.items[0].quantity, 2);
      assert.equal(mine.dropArea, 'Madhapur');
      assert.equal(JSON.stringify(mine).includes('contactNumber'), false, 'no customer contact before acceptance');
      assert.ok((await offersOf('r2')).offers.some((x: any) => x.orderId === order.id));
      assert.equal(await db.deliveryOffer.count({ where: { orderId: order.id, riderId: u.r3.id } }), 0, 'offline rider is not invited');
      assert.equal((await offersOf('r3')).offers.length, 0);
    });

    await t.test('two riders accepting simultaneously: exactly one wins, no duplicate assignment', async () => {
      const a = (await offersOf('r1')).offers.find((x: any) => x.orderId === order.id);
      const b = (await offersOf('r2')).offers.find((x: any) => x.orderId === order.id);
      const results = await Promise.all([
        call('post', `operations/delivery/offers/${a.id}/accept`, 'r1').send({}),
        call('post', `operations/delivery/offers/${b.id}/accept`, 'r2').send({}),
      ]);
      assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
      assert.equal(await db.deliveryAssignment.count({ where: { orderId: order.id } }), 1);
      assert.equal(await db.deliveryOffer.count({ where: { orderId: order.id, status: 'ACCEPTED' } }), 1);
      assert.equal(await db.deliveryOffer.count({ where: { orderId: order.id, status: 'OFFERED' } }), 0, 'other invitations closed');
      const winner = results[0].status === 200 ? 'r1' : 'r2';
      order.winner = winner;
      order.loser = winner === 'r1' ? 'r2' : 'r1';
      const assignment = await db.deliveryAssignment.findUniqueOrThrow({ where: { orderId: order.id } });
      assert.equal(assignment.riderId, u[winner].id);
      assert.equal(assignment.assignedById, u[winner].id, 'no admin involved');
      // Re-accepting a closed invitation is rejected.
      const loserOffer = winner === 'r1' ? b : a;
      await call('post', `operations/delivery/offers/${loserOffer.id}/accept`, order.loser).send({}).expect(409);
    });

    await t.test('OTP issued automatically at acceptance: customer reads it, rider/owner/admin cannot', async () => {
      guard.buckets.clear();
      const otp = (await call('get', `orders/${order.id}/handover`, 'customer').expect(200)).body.data;
      assert.equal(otp.state, 'ACTIVE');
      assert.match(otp.pin, /^\d{6}$/);
      order.pin = otp.pin;
      const h = await db.deliveryHandover.findUniqueOrThrow({ where: { orderId: order.id } });
      assert.equal(h.boundRiderId, u[order.winner].id);
      assert.equal(await db.handoverAudit.count({ where: { handoverId: h.id, action: 'AUTO_ISSUED' } }), 1);
      for (const who of [order.winner, 'owner', 'admin']) await call('get', `orders/${order.id}/handover`, who).expect(403);
      const riderView = (await call('get', `operations/delivery/orders/${order.id}`, order.winner).expect(200)).body;
      assert.equal(JSON.stringify(riderView).includes(otp.pin), false);
      assert.equal(JSON.stringify(riderView).includes('encryptedPin'), false);
      // The PIN-free notification event exists for the customer app.
      assert.ok(await db.orderEvent.findFirst({ where: { orderId: order.id, eventType: 'HANDOVER_ISSUED_1' } }));
      assert.equal(JSON.stringify(await db.orderEvent.findMany({ where: { orderId: order.id } })).includes(otp.pin), false);
    });

    await t.test('busy rider is not eligible for new invitations; wrong rider cannot touch the delivery', async () => {
      const second = await readyOrder();
      assert.equal(await db.deliveryOffer.count({ where: { orderId: second.id, riderId: u[order.winner].id } }), 0, 'busy rider not invited');
      assert.equal((await offersOf(order.winner)).offers.length, 0);
      assert.ok((await offersOf(order.loser)).offers.some((x: any) => x.orderId === second.id));
      await call('get', `operations/delivery/orders/${order.id}`, order.loser).expect(403);
      await call('post', `operations/delivery/orders/${order.id}/pickup`, order.loser).send({ expectedVersion: 99 }).expect(403);
      order.second = second;
    });

    await t.test('expired invitation cannot be accepted; decline removes it; a rider coming online later sees open offers', async () => {
      const inv = (await offersOf(order.loser)).offers.find((x: any) => x.orderId === order.second.id);
      await db.deliveryOffer.update({ where: { id: inv.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
      await call('post', `operations/delivery/offers/${inv.id}/accept`, order.loser).send({}).expect(410);
      const renewed = (await offersOf(order.loser)).offers.find((x: any) => x.orderId === order.second.id);
      assert.ok(renewed, 'refreshing re-invites an eligible rider while the order is still open');
      await call('post', `operations/delivery/offers/${renewed.id}/decline`, order.loser).send({}).expect(200);
      assert.equal((await offersOf(order.loser)).offers.some((x: any) => x.orderId === order.second.id), false);
      // r3 was offline when the order became ready; once online it sees the open order.
      await online('r3');
      assert.ok((await offersOf('r3')).offers.some((x: any) => x.orderId === order.second.id));
      // Going offline withdraws offers immediately.
      await offline('r3');
      assert.equal(await db.deliveryOffer.count({ where: { riderId: u.r3.id, status: 'OFFERED' } }), 0);
      await call('post', `operations/delivery/offers/${(await db.deliveryOffer.findFirstOrThrow({ where: { riderId: u.r3.id, orderId: order.second.id } })).id}/accept`, 'r3').send({}).expect(409);
      // Another rider's invitation id is not usable.
      await call('post', `operations/delivery/offers/${renewed.id}/accept`, order.winner).send({}).expect(404);
    });

    await t.test('pickup, out for delivery, arrival keeps a valid OTP, wrong OTP rejected, correct OTP delivers', async () => {
      guard.buckets.clear();
      const w = order.winner;
      let o = (await call('get', `operations/delivery/orders/${order.id}`, w).expect(200)).body.data;
      await call('post', `operations/delivery/orders/${o.id}/arrived`, w).send({}).expect(409); // not out for delivery yet
      o = (await call('post', `operations/delivery/orders/${o.id}/pickup`, w).send({ expectedVersion: o.version }).expect(200)).body.data;
      o = (await call('post', `operations/delivery/orders/${o.id}/out-for-delivery`, w).send({ expectedVersion: o.version }).expect(200)).body.data;
      const arrived = (await call('post', `operations/delivery/orders/${o.id}/arrived`, w).send({}).expect(200)).body.data;
      assert.equal(arrived.reissued, false, 'a still-valid OTP is kept');
      assert.equal(JSON.stringify(arrived).includes(order.pin), false, 'rider never receives the PIN');
      await call('post', `operations/delivery/orders/${o.id}/arrived`, order.loser).send({}).expect(403);
      const wrong = order.pin === '000000' ? '000001' : '000000';
      await call('post', `operations/delivery/orders/${o.id}/complete-handover`, w).send({ pin: wrong, expectedVersion: o.version }).expect(400);
      await call('post', `operations/delivery/orders/${o.id}/complete-handover`, order.loser).send({ pin: order.pin, expectedVersion: o.version }).expect(403);
      o = (await call('post', `operations/delivery/orders/${o.id}/complete-handover`, w).send({ pin: order.pin, expectedVersion: o.version }).expect(200)).body.data;
      assert.equal(o.status, 'DELIVERED');
      assert.equal((await call('get', `orders/${o.id}/handover`, 'customer').expect(200)).body.data.pin, undefined);
      assert.equal((await call('get', 'rider/presence/me', w).expect(200)).body.data.isAvailable, true, 'free again after delivery');
    });

    await t.test('expired OTP: rejected at verification, re-issued on arrival, old code invalid, used code cannot complete another order', async () => {
      guard.buckets.clear();
      const w = order.winner;
      const inv = (await offersOf(w)).offers.find((x: any) => x.orderId === order.second.id);
      await call('post', `operations/delivery/offers/${inv.id}/accept`, w).send({}).expect(200);
      let o = (await call('get', `operations/delivery/orders/${order.second.id}`, w).expect(200)).body.data;
      o = (await call('post', `operations/delivery/orders/${o.id}/pickup`, w).send({ expectedVersion: o.version }).expect(200)).body.data;
      o = (await call('post', `operations/delivery/orders/${o.id}/out-for-delivery`, w).send({ expectedVersion: o.version }).expect(200)).body.data;
      const old = (await call('get', `orders/${o.id}/handover`, 'customer').expect(200)).body.data.pin;
      // Expire it (re-seal so the stored binding stays consistent), cooldown elapsed.
      const keys = crypto.handoverConfig();
      const rec = await db.deliveryHandover.findUniqueOrThrow({ where: { orderId: o.id } });
      const expired = { ...rec, issuedAt: new Date(Date.now() - 700000), expiresAt: new Date(Date.now() - 1000) };
      await db.deliveryHandover.update({ where: { orderId: o.id }, data: { issuedAt: expired.issuedAt, expiresAt: expired.expiresAt, nextIssueAt: new Date(0), verifier: crypto.pinVerifier(old, expired, keys.verifyKey), encryptedPin: crypto.sealPin(old, expired, keys.encryptionKey) } });
      assert.equal((await call('get', `orders/${o.id}/handover`, 'customer').expect(200)).body.data.state, 'EXPIRED');
      await call('post', `operations/delivery/orders/${o.id}/complete-handover`, w).send({ pin: old, expectedVersion: o.version }).expect(409);
      // The first order's used PIN cannot complete this order.
      if (order.pin !== old) await call('post', `operations/delivery/orders/${o.id}/complete-handover`, w).send({ pin: order.pin, expectedVersion: o.version }).expect(409);
      const arrival = (await call('post', `operations/delivery/orders/${o.id}/arrived`, w).send({}).expect(200)).body.data;
      assert.equal(arrival.reissued, true);
      const fresh = (await call('get', `orders/${o.id}/handover`, 'customer').expect(200)).body.data;
      assert.equal(fresh.state, 'ACTIVE');
      assert.notEqual(fresh.pin, old);
      assert.ok(await db.orderEvent.findFirst({ where: { orderId: o.id, eventType: 'HANDOVER_ISSUED_2' } }));
      // Rapid re-issue is blocked by the existing cooldown/limits.
      const live = await db.deliveryHandover.findUniqueOrThrow({ where: { orderId: o.id } });
      await db.deliveryHandover.update({ where: { orderId: o.id }, data: { issuedAt: new Date(Date.now() - 700000), expiresAt: new Date(Date.now() - 1000) } });
      await call('post', `operations/delivery/orders/${o.id}/arrived`, w).send({}).expect(429);
      await db.deliveryHandover.update({ where: { orderId: o.id }, data: { issuedAt: live.issuedAt, expiresAt: live.expiresAt } });
      await call('post', `operations/delivery/orders/${o.id}/complete-handover`, w).send({ pin: old, expectedVersion: o.version }).expect(400);
      o = (await call('post', `operations/delivery/orders/${o.id}/complete-handover`, w).send({ pin: fresh.pin, expectedVersion: o.version }).expect(200)).body.data;
      assert.equal(o.status, 'DELIVERED');
    });

    await t.test('admin dispatch remains a fallback and also issues the OTP automatically', async () => {
      guard.buckets.clear();
      for (const r of ['r1', 'r2']) await offline(r);
      const fallback = await readyOrder();
      assert.equal(await db.deliveryOffer.count({ where: { orderId: fallback.id } }), 0, 'nobody online, no invitations');
      const o = (await call('post', `operations/dispatch/orders/${fallback.id}/assign`, 'admin').send({ expectedVersion: fallback.version, riderId: u.r1.id }).expect(200)).body.data;
      assert.equal(o.status, 'READY_FOR_PICKUP');
      assert.equal((await call('get', `orders/${fallback.id}/handover`, 'customer').expect(200)).body.data.state, 'ACTIVE');
    });
  } finally {
    await db.deliveryOffer.deleteMany({ where: { orderId: { in: orders } } });
    await app.close();
    await db.$disconnect();
  }
});
