import 'dotenv/config';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import request from 'supertest';

/**
 * F2 group ordering + negotiation, end to end on the isolated test database.
 * Every amount is taken from the server; nothing here hard-codes a price.
 */
test('group ordering: invites, shared cart, negotiation, safe checkout, alternatives', { timeout: 300000 }, async (t) => {
  const url = process.env.TEST_DATABASE_URL!;
  assert.equal(new URL(url).pathname, '/food_delivery_test');
  Object.assign(process.env, { DATABASE_URL: url, NODE_ENV: 'test', DEMO_CHECKOUT_ENABLED: 'true', DEMO_FULFILLMENT_ENABLED: 'true' });
  execFileSync(process.execPath, ['node_modules/prisma/build/index.js', 'migrate', 'deploy'], { env: { ...process.env, DIRECT_URL: url }, stdio: 'pipe' });
  const { createDatabase } = require('../dist/src/database/client');
  const { createApp } = require('../dist/src/main');
  const { PasswordService } = require('../dist/src/modules/auth/password.service');
  const db = createDatabase(url);
  const app = await createApp();
  const rid = 'deccan-handi-gachi';
  const password = randomUUID();
  const users: any[] = [];
  const groupIds: string[] = [];
  try {
    const zone = (await db.restaurantDeliveryZone.findFirstOrThrow({ where: { restaurantId: rid, isEligible: true, zone: { isActive: true } } })).zoneId;
    const hash = await new PasswordService().hash(password);
    const mk = async (role: string, displayName: string, restaurantId?: string) => users[users.push(await db.user.create({ data: {
      email: `f2-${randomUUID()}@test.invalid`, displayName, passwordHash: hash, roles: { create: { roleName: role } }, ...(restaurantId ? { memberships: { create: { restaurantId } } } : {}),
    } })) - 1];
    const A = await mk('CUSTOMER', 'Asha'), B = await mk('CUSTOMER', 'Bala'), C = await mk('CUSTOMER', 'Chitra');
    const owner = await mk('RESTAURANT_OWNER', 'Owner', rid), otherOwner = await mk('RESTAURANT_OWNER', 'Other owner', 'tiffin');
    const address = await db.customerAddress.create({ data: { customerId: A.id, label: 'Home', recipientName: 'Asha', contactNumber: '9000000000', addressLine1: '1 Synthetic Lane', postalCode: '500032', city: 'Hyderabad', localityId: zone } });
    const dishes = await db.menuItem.findMany({ where: { restaurantId: rid, availabilityStatus: 'AVAILABLE', variants: { none: {} } }, take: 3, orderBy: { basePricePaise: 'asc' } });
    assert.ok(dishes.length >= 2, 'fixture has dishes');

    await app.init();
    const api = request(app.getHttpServer());
    const tokens = new Map<string, string>();
    for (const u of users) tokens.set(u.id, (await api.post('/api/v1/auth/login').send({ email: u.email, password }).expect(200)).body.data.session.token);
    const as = (u: any) => ({
      get: (path: string) => api.get(`/api/v1/${path}`).set('Authorization', `Bearer ${tokens.get(u.id)}`),
      post: (path: string, body: any = {}) => api.post(`/api/v1/${path}`).set('Authorization', `Bearer ${tokens.get(u.id)}`).send(body),
      patch: (path: string, body: any = {}) => api.patch(`/api/v1/${path}`).set('Authorization', `Bearer ${tokens.get(u.id)}`).send(body),
      del: (path: string) => api.delete(`/api/v1/${path}`).set('Authorization', `Bearer ${tokens.get(u.id)}`),
    });
    const state = async (u: any, id: string) => (await as(u).get(`groups/${id}`).expect(200)).body.data;

    let gid = '', invite: any;
    await t.test('create group with a secure invite; join by code; non-members cannot see it', async () => {
      const r = (await as(A).post('groups', { restaurantId: rid, addressId: address.id, name: 'Friday lunch' }).expect(200)).body.data;
      gid = r.group.id; invite = r.invite; groupIds.push(gid);
      assert.ok(invite.inviteToken.length >= 40 && /^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(invite.joinCode));
      assert.equal(r.group.status, 'OPEN'); assert.equal(r.group.isOrganizer, true);
      const stored = await db.groupOrder.findUniqueOrThrow({ where: { id: gid } });
      assert.ok(!JSON.stringify(stored).includes(invite.inviteToken), 'only a hash of the token is stored');
      await as(C).get(`groups/${gid}`).expect(404);
      await as(C).post('groups/join', { token: 'x'.repeat(43) }).expect(404);
      await as(C).post('groups/join', { code: 'ZZZZ-ZZZZ' }).expect(404);
      const joined = (await as(B).post('groups/join', { code: invite.joinCode.toLowerCase() }).expect(200)).body.data;
      assert.equal(joined.members.length, 2);
      await as(B).post('groups/join', { token: invite.inviteToken }).expect(200); // idempotent
      assert.equal((await state(A, gid)).members.length, 2, 'no duplicate membership');
      await as(B).post('groups', { restaurantId: rid, addressId: address.id }).expect(404); // someone else's address
      await as(owner).get(`groups/${gid}`).expect(403);
    });

    await t.test('shared cart: own items only, optimistic revision, concurrent adds, member contributions', async () => {
      let s = await state(A, gid);
      s = (await as(A).post(`groups/${gid}/items`, { menuItemId: dishes[0].id, quantity: 2, addOnIds: [], expectedRevision: s.cartRevision }).expect(200)).body.data;
      await as(B).post(`groups/${gid}/items`, { menuItemId: dishes[1].id, quantity: 1, addOnIds: [], expectedRevision: s.cartRevision - 1 }).expect(409);
      // Two simultaneous adds against the same revision: exactly one wins (no lost update, no double add).
      const [r1, r2] = await Promise.all([
        as(B).post(`groups/${gid}/items`, { menuItemId: dishes[1].id, quantity: 1, addOnIds: [], expectedRevision: s.cartRevision }),
        as(B).post(`groups/${gid}/items`, { menuItemId: dishes[1].id, quantity: 1, addOnIds: [], expectedRevision: s.cartRevision }),
      ]);
      assert.deepEqual([r1.status, r2.status].sort(), [200, 409]);
      s = await state(B, gid);
      assert.equal(s.items.length, 2);
      assert.equal(s.items.find((i: any) => i.menuItemId === dishes[1].id).quantity, 1);
      const aItem = s.items.find((i: any) => i.memberId === A.id);
      await as(B).patch(`groups/${gid}/items/${aItem.id}`, { quantity: 5, expectedRevision: s.cartRevision }).expect(403);
      await as(B).del(`groups/${gid}/items/${aItem.id}?expectedRevision=${s.cartRevision}`).expect(403);
      await as(B).post(`groups/${gid}/items`, { menuItemId: (await db.menuItem.findFirstOrThrow({ where: { restaurantId: 'tiffin' } })).id, quantity: 1, addOnIds: [], expectedRevision: s.cartRevision }).expect(422);
      const p = s.pricing;
      assert.equal(p.normalTotalPaise, p.itemSubtotalPaise + p.customizationTotalPaise + p.packagingPaise + p.deliveryPaise + p.platformPaise - p.discountPaise + p.taxPaise);
      assert.equal(s.contributions.reduce((n: number, c: any) => n + c.itemTotalPaise, 0), p.itemSubtotalPaise + p.customizationTotalPaise);
    });

    let proposalId = '', normal = 0;
    await t.test('lock and propose: organizer only, validated range, one live proposal', async () => {
      let s = await state(A, gid);
      await as(B).post(`groups/${gid}/lock`, { expectedVersion: s.version }).expect(403);
      s = (await as(A).post(`groups/${gid}/lock`, { expectedVersion: s.version }).expect(200)).body.data;
      assert.equal(s.status, 'LOCKED');
      await as(B).post(`groups/${gid}/items`, { menuItemId: dishes[0].id, quantity: 1, addOnIds: [], expectedRevision: s.cartRevision }).expect(409);
      normal = s.pricing.normalTotalPaise;
      const min = s.negotiationRange.minAllowedTotalPaise;
      await as(A).post(`groups/${gid}/proposals`, { proposedTotalPaise: normal, expectedVersion: s.version }).expect(422);
      await as(A).post(`groups/${gid}/proposals`, { proposedTotalPaise: min - 100, expectedVersion: s.version }).expect(422);
      await as(B).post(`groups/${gid}/proposals`, { proposedTotalPaise: min, expectedVersion: s.version }).expect(403);
      const ask = Math.max(min, Math.round(normal * 0.8));
      s = (await as(A).post(`groups/${gid}/proposals`, { proposedTotalPaise: ask, expectedVersion: s.version }).expect(200)).body.data;
      assert.equal(s.status, 'PROPOSED'); proposalId = s.proposal.id;
      assert.equal(s.proposal.requestedReductionPaise, normal - ask);
      await as(A).post(`groups/${gid}/proposals`, { proposedTotalPaise: ask, expectedVersion: s.version }).expect(409);
    });

    await t.test('owner: only the authorized outlet sees and answers; counteroffer range enforced', async () => {
      const list = (await as(owner).get('restaurant/group-proposals').expect(200)).body.data;
      const mine = list.find((x: any) => x.id === proposalId);
      assert.ok(mine); assert.equal(mine.memberCount, 2); assert.equal(mine.normalTotalPaise, normal); assert.ok(mine.items.length === 2);
      const other = (await as(otherOwner).get('restaurant/group-proposals').expect(200)).body.data;
      assert.ok(!other.some((x: any) => x.id === proposalId));
      await as(otherOwner).get(`restaurant/group-proposals?restaurantId=${rid}`).expect(403);
      await as(otherOwner).post(`restaurant/group-proposals/${proposalId}/accept`).expect(403);
      await as(A).post(`restaurant/group-proposals/${proposalId}/accept`).expect(403);
      await as(owner).post(`restaurant/group-proposals/${proposalId}/counter`, { counterTotalPaise: mine.proposedTotalPaise }).expect(422);
      await as(owner).post(`restaurant/group-proposals/${proposalId}/counter`, { counterTotalPaise: normal }).expect(422);
      const counter = Math.round((mine.proposedTotalPaise + normal) / 2);
      const r = (await as(owner).post(`restaurant/group-proposals/${proposalId}/counter`, { counterTotalPaise: counter, note: 'Best we can do' }).expect(200)).body.data;
      assert.equal(r.status, 'COUNTERED'); assert.equal(r.counterTotalPaise, counter);
      await as(owner).post(`restaurant/group-proposals/${proposalId}/accept`).expect(409);
    });

    let agreed = 0;
    await t.test('organizer accepts the counteroffer; members cannot', async () => {
      let s = await state(A, gid);
      assert.equal(s.status, 'COUNTERED');
      await as(B).post(`groups/${gid}/proposals/${proposalId}/counter`, { answer: 'accept', expectedVersion: s.version }).expect(403);
      s = (await as(A).post(`groups/${gid}/proposals/${proposalId}/counter`, { answer: 'accept', expectedVersion: s.version }).expect(200)).body.data;
      assert.equal(s.status, 'ACCEPTED'); agreed = s.proposal.agreedTotalPaise; assert.equal(agreed, s.proposal.counterTotalPaise);
    });

    let orderId = '';
    await t.test('checkout: bound to organizer, group, revision and price; personal cart untouched; no reuse', async () => {
      // A has an unrelated personal cart item that must survive the group checkout.
      const cart = (await as(A).get('cart').expect(200)).body.data;
      await as(A).post('cart/items', { restaurantId: rid, menuItemId: dishes[2]?.id ?? dishes[0].id, quantity: 1, addOnIds: [], expectedVersion: cart.version }).expect(200);
      const s = await state(A, gid);
      await as(B).post(`groups/${gid}/checkout`, { proposalId, expectedVersion: s.version, idempotencyKey: randomUUID() }).expect(403);
      await as(A).post(`groups/${gid}/checkout`, { proposalId: randomUUID(), expectedVersion: s.version, idempotencyKey: randomUUID() }).expect(409);
      const key = randomUUID();
      const o = (await as(A).post(`groups/${gid}/checkout`, { proposalId, expectedVersion: s.version, idempotencyKey: key }).expect(200)).body.data;
      orderId = o.orderId;
      assert.equal(o.finalPayablePaise, agreed); assert.equal(o.negotiatedDiscountPaise, normal - agreed); assert.equal(o.normalTotalPaise, normal);
      const row = await db.order.findUniqueOrThrow({ where: { id: orderId }, include: { items: true } });
      assert.equal(row.finalPayablePaise, row.itemSubtotalPaise + row.customizationTotalPaise + row.packagingPaise + row.deliveryPaise + row.platformPaise - row.discountPaise + row.taxPaise, 'order amounts reconcile');
      assert.equal(row.negotiatedDiscountPaise, normal - agreed); assert.equal(row.groupProposalId, proposalId); assert.equal(row.restaurantId, rid);
      assert.equal(row.items.reduce((n: number, i: any) => n + i.quantity, 0), 3);
      // Same request again returns the same order; a new request cannot reuse the offer.
      assert.equal((await as(A).post(`groups/${gid}/checkout`, { proposalId, expectedVersion: s.version, idempotencyKey: key }).expect(200)).body.data.orderId, orderId);
      await as(A).post(`groups/${gid}/checkout`, { proposalId, expectedVersion: s.version + 1, idempotencyKey: randomUUID() }).expect(409);
      const after = (await as(A).get('cart').expect(200)).body.data;
      assert.equal(after.items.length, 1, 'personal cart items untouched');
      assert.equal((await state(B, gid)).status, 'ORDERED');
    });

    await t.test('placed group order enters the normal owner queue and kitchen workflow', async () => {
      const q = (await as(owner).get('operations/restaurant/orders').expect(200)).body.data.items;
      const o = q.find((x: any) => x.id === orderId);
      assert.ok(o); assert.equal(o.finalPayablePaise, agreed); assert.ok(o.availableActions.includes('accept'));
      const r = (await as(owner).post(`operations/restaurant/orders/${orderId}/accept`, { expectedVersion: o.version }).expect(200)).body.data;
      assert.equal(r.status, 'ACCEPTED');
      const others = (await as(otherOwner).get('operations/restaurant/orders').expect(200)).body.data.items;
      assert.ok(!others.some((x: any) => x.id === orderId));
    });

    await t.test('rejection, alternatives and an organizer-confirmed switch; expiry blocks late answers', async () => {
      const r = (await as(A).post('groups', { restaurantId: rid, addressId: address.id }).expect(200)).body.data;
      const g2 = r.group.id; groupIds.push(g2);
      let s = (await as(A).post(`groups/${g2}/items`, { menuItemId: dishes[0].id, quantity: 2, addOnIds: [], expectedRevision: r.group.cartRevision }).expect(200)).body.data;
      s = (await as(A).post(`groups/${g2}/lock`, { expectedVersion: s.version }).expect(200)).body.data;
      s = (await as(A).post(`groups/${g2}/proposals`, { proposedTotalPaise: s.negotiationRange.minAllowedTotalPaise, expectedVersion: s.version }).expect(200)).body.data;
      // Late answer: the restaurant's response window has passed.
      await db.groupProposal.update({ where: { id: s.proposal.id }, data: { responseExpiresAt: new Date(Date.now() - 1000) } });
      await as(owner).post(`restaurant/group-proposals/${s.proposal.id}/accept`).expect(410);
      s = await state(A, g2);
      assert.equal(s.status, 'LOCKED'); assert.equal(s.proposal.status, 'EXPIRED');
      s = (await as(A).post(`groups/${g2}/proposals`, { proposedTotalPaise: s.negotiationRange.minAllowedTotalPaise, expectedVersion: s.version }).expect(200)).body.data;
      await as(owner).post(`restaurant/group-proposals/${s.proposal.id}/reject`, { note: 'Too low for us' }).expect(200);
      s = await state(A, g2);
      assert.equal(s.status, 'REJECTED');
      const alts = (await as(A).get(`groups/${g2}/alternatives`).expect(200)).body.data;
      assert.match(alts.note, /No restaurant has agreed/);
      for (const a of alts.alternatives) {
        assert.notEqual(a.restaurantId, rid);
        assert.ok(a.estimatedNormalTotalPaise > 0 && a.lowestProposalPaise <= a.estimatedNormalTotalPaise);
        const served = await db.restaurantDeliveryZone.findFirst({ where: { restaurantId: a.restaurantId, zoneId: zone, isEligible: true } });
        assert.ok(served, 'alternatives serve the group delivery area');
      }
      if (alts.alternatives.length) {
        const alt = alts.alternatives[0];
        await as(B).post(`groups/${g2}/switch`, { restaurantId: alt.restaurantId, expectedVersion: s.version }).expect(404); // B is not a member
        s = (await as(A).post(`groups/${g2}/switch`, { restaurantId: alt.restaurantId, expectedVersion: s.version }).expect(200)).body.data;
        assert.equal(s.restaurant.id, alt.restaurantId); assert.equal(s.status, 'OPEN');
        assert.ok(s.items.every((i: any) => i.menuItemId !== dishes[0].id));
      }
      s = (await as(A).post(`groups/${g2}/cancel`, { expectedVersion: s.version }).expect(200)).body.data;
      assert.equal(s.status, 'CANCELED');
    });

    await t.test('item becomes unavailable after acceptance: checkout is blocked, nothing is ordered', async () => {
      const r = (await as(A).post('groups', { restaurantId: rid, addressId: address.id }).expect(200)).body.data;
      const g3 = r.group.id; groupIds.push(g3);
      let s = (await as(A).post(`groups/${g3}/items`, { menuItemId: dishes[1].id, quantity: 1, addOnIds: [], expectedRevision: r.group.cartRevision }).expect(200)).body.data;
      s = (await as(A).post(`groups/${g3}/lock`, { expectedVersion: s.version }).expect(200)).body.data;
      s = (await as(A).post(`groups/${g3}/proposals`, { proposedTotalPaise: s.negotiationRange.minAllowedTotalPaise, expectedVersion: s.version }).expect(200)).body.data;
      await as(owner).post(`restaurant/group-proposals/${s.proposal.id}/accept`).expect(200);
      s = await state(A, g3);
      await db.menuItem.update({ where: { id: dishes[1].id }, data: { availabilityStatus: 'UNAVAILABLE' } });
      try {
        await as(A).post(`groups/${g3}/checkout`, { proposalId: s.proposal.id, expectedVersion: s.version, idempotencyKey: randomUUID() }).expect(422);
        assert.equal((await state(A, g3)).status, 'ACCEPTED');
      } finally {
        await db.menuItem.update({ where: { id: dishes[1].id }, data: { availabilityStatus: 'AVAILABLE' } });
      }
      // An expired accepted offer cannot be used either.
      await db.groupProposal.update({ where: { id: s.proposal.id }, data: { offerExpiresAt: new Date(Date.now() - 1000) } });
      s = await state(A, g3);
      assert.equal(s.status, 'LOCKED'); assert.equal(s.proposal.status, 'EXPIRED');
    });

    await t.test('invite guessing is rate limited', async () => {
      const D = await mk('CUSTOMER', 'Dev');
      tokens.set(D.id, (await api.post('/api/v1/auth/login').send({ email: D.email, password }).expect(200)).body.data.session.token);
      const codes = [];
      for (let i = 0; i < 11; i++) codes.push((await as(D).post('groups/join', { code: `ZZZZ-ZZZ${i % 9}` })).status);
      assert.ok(codes.includes(429));
    });
  } finally {
    await db.groupOrder.deleteMany({ where: { id: { in: groupIds } } });
    await db.cartItem.deleteMany({ where: { cart: { customerId: { in: users.map((u) => u.id) } } } });
    await db.restaurantMembership.deleteMany({ where: { userId: { in: users.map((u) => u.id) } } });
    await app.close();
    await db.$disconnect();
  }
});
