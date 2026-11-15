import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeEta, freshness, haversineMeters, travelLeg } from '../src/modules/tracking/eta';
import { NoRoutingProvider, OsrmRoutingProvider, routingFromEnv } from '../src/modules/tracking/routing';

const now = new Date('2026-11-15T10:00:00Z');
const rider = { latitude: 17.4483, longitude: 78.3915 }, home = { latitude: 17.4401, longitude: 78.3489 }, kitchen = { latitude: 17.4502, longitude: 78.3811 };
const base = { now, rider, riderFresh: true, restaurant: kitchen, destination: home, kitchenReadyAt: null, fallbackTravelSeconds: 1200, windowEnd: null, routeToCustomer: null, routeToRestaurant: null };

test('freshness: waiting, live, stale, unavailable and ended', () => {
  assert.equal(freshness(null, now, false).state, 'WAITING');
  assert.equal(freshness(new Date(now.getTime() - 10_000), now, false).state, 'LIVE');
  assert.equal(freshness(new Date(now.getTime() - 60_000), now, false).state, 'STALE');
  assert.equal(freshness(new Date(now.getTime() - 300_000), now, false).state, 'UNAVAILABLE');
  assert.equal(freshness(new Date(now.getTime() - 1_000), now, true).state, 'ENDED');
});

test('fallback travel is a labeled estimate and never reports road distance', () => {
  const straight = haversineMeters(rider, home);
  assert.ok(straight > 4000 && straight < 5000);
  const leg = travelLeg(rider, home, null);
  assert.equal(leg.source, 'ESTIMATE'); assert.equal(leg.distanceMeters, null); assert.equal(leg.straightLineMeters, Math.round(straight));
  const routed = travelLeg(rider, home, { distanceMeters: 6100, durationSeconds: 900, geometry: [] });
  assert.deepEqual([routed.source, routed.distanceMeters, routed.seconds], ['ROUTED', 6100, 900]);
});

test('in transit: routed ETA uses provider duration; schedule window drives on-track / at-risk / delayed', () => {
  const routed = computeEta({ ...base, status: 'OUT_FOR_DELIVERY', routeToCustomer: { distanceMeters: 6100, durationSeconds: 900, geometry: [] } });
  assert.equal(routed.phase, 'TO_CUSTOMER'); assert.equal(routed.source, 'ROUTED'); assert.equal(routed.distanceMeters, 6100);
  assert.equal(routed.seconds, 900 + 120);
  const onTrack = computeEta({ ...base, status: 'OUT_FOR_DELIVERY', windowEnd: new Date(now.getTime() + 30 * 60_000), routeToCustomer: { distanceMeters: 6100, durationSeconds: 900, geometry: [] } });
  assert.equal(onTrack.scheduleStatus, 'ON_TRACK');
  const atRisk = computeEta({ ...base, status: 'OUT_FOR_DELIVERY', windowEnd: new Date(now.getTime() + 5 * 60_000), routeToCustomer: { distanceMeters: 6100, durationSeconds: 900, geometry: [] } });
  assert.equal(atRisk.scheduleStatus, 'AT_RISK');
  const late = computeEta({ ...base, status: 'OUT_FOR_DELIVERY', windowEnd: new Date(now.getTime() - 60_000) });
  assert.equal(late.scheduleStatus, 'DELAYED');
});

test('missing or unavailable rider fix falls back to restaurant timing, clearly labeled', () => {
  const noFix = computeEta({ ...base, status: 'OUT_FOR_DELIVERY', rider: null });
  assert.equal(noFix.seconds, 1200); assert.match(noFix.basis, /rider location unavailable/);
  const noPin = computeEta({ ...base, status: 'OUT_FOR_DELIVERY', destination: null });
  assert.match(noPin.basis, /delivery pin not confirmed/);
});

test('before pickup: kitchen time and rider travel overlap; customer leg is an estimate', () => {
  const prep = computeEta({ ...base, status: 'PREPARING', rider: null, kitchenReadyAt: new Date(now.getTime() + 10 * 60_000) });
  assert.equal(prep.phase, 'PREPARING'); assert.equal(prep.source, 'ESTIMATE'); assert.match(prep.basis, /^kitchen preparation/);
  const toKitchen = computeEta({ ...base, status: 'READY_FOR_PICKUP' });
  assert.equal(toKitchen.phase, 'TO_RESTAURANT');
  assert.equal(computeEta({ ...base, status: 'DELIVERED' }).phase, 'DELIVERED');
  assert.equal(computeEta({ ...base, status: 'CANCELED' }).seconds, null);
});

test('routing provider: disabled by default, OSRM parsed, failures and rate limit fall back to null', async () => {
  assert.ok(routingFromEnv({}) instanceof NoRoutingProvider);
  assert.ok(routingFromEnv({ ROUTING_PROVIDER: 'osrm', ROUTING_BASE_URL: 'not-a-url' }) instanceof NoRoutingProvider);
  let calls = 0;
  const ok = (async () => { calls++; return new Response(JSON.stringify({ code: 'Ok', routes: [{ distance: 6100.4, duration: 899.6, geometry: { coordinates: [[78.3915, 17.4483], [78.3489, 17.4401]] } }] })); }) as typeof fetch;
  const p = new OsrmRoutingProvider('https://osrm.example.test', 1000, 1100, ok);
  const r = await p.route([rider, home]);
  assert.deepEqual(r, { distanceMeters: 6100, durationSeconds: 900, geometry: [[17.4483, 78.3915], [17.4401, 78.3489]] });
  assert.equal(await p.route([rider, home]), null, 'second call within the rate-limit interval is skipped');
  assert.equal(calls, 1);
  const broken = new OsrmRoutingProvider('https://osrm.example.test', 1000, 0, (async () => { throw new Error('network'); }) as typeof fetch);
  assert.equal(await broken.route([rider, home]), null);
  const bad = new OsrmRoutingProvider('https://osrm.example.test', 1000, 0, (async () => new Response('{"code":"NoRoute"}')) as typeof fetch);
  assert.equal(await bad.route([rider, home]), null);
});
