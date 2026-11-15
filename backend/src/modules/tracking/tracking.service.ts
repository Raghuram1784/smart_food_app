/**
 * F4 live rider tracking and smart ETA.
 *
 * - Only the rider assigned to an active delivery can publish, and only with a real device fix.
 *   Invalid, future, stale, out-of-order and too-frequent fixes are rejected.
 * - Only the latest fix is stored (no history). Rows are removed once the order is terminal.
 * - Readers: the ordering customer, the assigned rider, an active owner of the restaurant, admin.
 * - Live fixes are pushed on `delivery.location` to that order's authorized rooms only.
 * - Road routing is requested at most once per refresh interval per order, never per GPS update.
 */
import { ConflictException, ForbiddenException, GoneException, HttpException, Inject, Injectable, NotFoundException, OnModuleDestroy, OnModuleInit, UnprocessableEntityException } from '@nestjs/common';
import { DatabaseService } from '../../database/database.module';
import { Prisma } from '../../generated/prisma/client';
import type { AuthenticatedPrincipal } from '../auth/auth.types';
import { OrderGateway } from '../operations/realtime';
import { computeEta, ETA_RULES, freshness, type EtaResult } from './eta';
import { routingFromEnv, type LatLng, type RouteResult, type RoutingProvider } from './routing';

export const TRACKING_RULES = { maxFutureSkewMs: 30_000, maxAgeMs: 120_000, minIntervalMs: 2_000, maxAccuracyMeters: 1000, maxSpeedMps: 70 };
const ACTIVE = ['READY_FOR_PICKUP', 'PICKED_UP', 'OUT_FOR_DELIVERY'];
const TERMINAL = ['DELIVERED', 'CANCELED', 'REJECTED'];
const num = (d: Prisma.Decimal | null | undefined) => (d == null ? null : Number(d));

export interface FixInput { latitude: number; longitude: number; accuracyMeters: number; headingDegrees?: number | null; speedMps?: number | null; recordedAt: string }

@Injectable()
export class TrackingService implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  readonly routing: RoutingProvider;
  private readonly preRouteCache = new Map<string, { at: number; eta: EtaResult }>();
  constructor(@Inject(DatabaseService) private readonly database: DatabaseService, @Inject(OrderGateway) private readonly gateway: OrderGateway) {
    this.routing = routingFromEnv();
  }
  onModuleInit() { this.timer = setInterval(() => { void this.sweep(); }, 60_000); this.timer.unref(); }
  onModuleDestroy() { if (this.timer) clearInterval(this.timer); }

  /** Removes tracking rows (latest fix and drop pin) for orders that are no longer active. */
  async sweep() {
    try { await this.database.client.deliveryTracking.deleteMany({ where: { order: { status: { in: TERMINAL as any } } } }); } catch { /* retried next sweep */ }
  }

  private async active(userId: string) {
    const u = await this.database.client.user.findFirst({ where: { id: userId, status: 'ACTIVE' }, select: { id: true } });
    if (!u) throw new ForbiddenException('Session is no longer active');
  }

  // ------------------------------------------------------------ rider publishes a real GPS fix
  async publish(p: AuthenticatedPrincipal, orderId: string, f: FixInput) {
    await this.active(p.userId);
    const valid = Number.isFinite(f.latitude) && Number.isFinite(f.longitude) && Math.abs(f.latitude) <= 90 && Math.abs(f.longitude) <= 180 && !(f.latitude === 0 && f.longitude === 0);
    if (!valid) throw new UnprocessableEntityException('Invalid GPS coordinates');
    if (!Number.isFinite(f.accuracyMeters) || f.accuracyMeters < 0 || f.accuracyMeters > TRACKING_RULES.maxAccuracyMeters) throw new UnprocessableEntityException('GPS accuracy is too low to share');
    if (f.headingDegrees != null && !(f.headingDegrees >= 0 && f.headingDegrees <= 360)) throw new UnprocessableEntityException('Invalid heading');
    if (f.speedMps != null && !(f.speedMps >= 0 && f.speedMps <= TRACKING_RULES.maxSpeedMps)) throw new UnprocessableEntityException('Invalid speed');
    const recordedAt = new Date(f.recordedAt), now = Date.now();
    if (Number.isNaN(recordedAt.getTime())) throw new UnprocessableEntityException('Invalid location timestamp');
    if (recordedAt.getTime() > now + TRACKING_RULES.maxFutureSkewMs) throw new UnprocessableEntityException('Location timestamp is in the future');
    if (recordedAt.getTime() < now - TRACKING_RULES.maxAgeMs) throw new UnprocessableEntityException('Location is too old to share');

    const out = await this.database.client.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id = ${orderId}::uuid FOR UPDATE`;
      const o = await tx.order.findUnique({ where: { id: orderId }, select: { id: true, status: true, customerId: true, restaurantId: true, assignment: { select: { riderId: true } }, tracking: true } });
      if (!o || o.assignment?.riderId !== p.userId) throw new ForbiddenException('You are not assigned to this delivery');
      if (TERMINAL.includes(o.status)) throw new GoneException('Tracking has ended for this delivery');
      if (!ACTIVE.includes(o.status)) throw new ConflictException('This delivery is not active');
      const prev = o.tracking?.recordedAt;
      if (prev && recordedAt <= prev) throw new ConflictException('A newer location was already received');
      if (prev && recordedAt.getTime() - prev.getTime() < TRACKING_RULES.minIntervalMs) throw new HttpException('Location updates are too frequent', 429);
      const data = { riderId: p.userId, latitude: new Prisma.Decimal(f.latitude).toDecimalPlaces(6), longitude: new Prisma.Decimal(f.longitude).toDecimalPlaces(6), accuracyMeters: f.accuracyMeters,
        headingDegrees: f.headingDegrees ?? null, speedMps: f.speedMps ?? null, recordedAt, receivedAt: new Date() };
      await tx.deliveryTracking.upsert({ where: { orderId }, create: { orderId, ...data }, update: data });
      return o;
    }, { isolationLevel: 'ReadCommitted', timeout: 10_000 });

    const payload = { orderId, latitude: Number(f.latitude.toFixed(6)), longitude: Number(f.longitude.toFixed(6)), accuracyMeters: Math.round(f.accuracyMeters), headingDegrees: f.headingDegrees ?? null, speedMps: f.speedMps ?? null, recordedAt: recordedAt.toISOString() };
    this.gateway.emitLocation({ customerId: out.customerId, riderId: p.userId }, payload);
    return { accepted: true, recordedAt: payload.recordedAt };
  }

  // ------------------------------------------------------------ customer confirms the drop pin for this order
  async setDestination(p: AuthenticatedPrincipal, orderId: string, pin: LatLng) {
    await this.active(p.userId);
    if (!Number.isFinite(pin.latitude) || !Number.isFinite(pin.longitude) || Math.abs(pin.latitude) > 90 || Math.abs(pin.longitude) > 180 || (pin.latitude === 0 && pin.longitude === 0)) throw new UnprocessableEntityException('Invalid location');
    const o = await this.database.client.order.findUnique({ where: { id: orderId }, select: { customerId: true, status: true } });
    if (!o || o.customerId !== p.userId) throw new NotFoundException('Order not found');
    if (TERMINAL.includes(o.status)) throw new GoneException('This order is no longer active');
    const data = { destLatitude: new Prisma.Decimal(pin.latitude).toDecimalPlaces(6), destLongitude: new Prisma.Decimal(pin.longitude).toDecimalPlaces(6), destConfirmedAt: new Date(), etaComputedAt: null };
    await this.database.client.deliveryTracking.upsert({ where: { orderId }, create: { orderId, ...data }, update: data });
    return this.view(p, orderId);
  }

  // ------------------------------------------------------------ owner confirms the restaurant pickup point
  async setPickupLocation(p: AuthenticatedPrincipal, restaurantId: string, pin: LatLng & { accuracyMeters?: number | null }) {
    await this.active(p.userId);
    if (!Number.isFinite(pin.latitude) || !Number.isFinite(pin.longitude) || Math.abs(pin.latitude) > 90 || Math.abs(pin.longitude) > 180 || (pin.latitude === 0 && pin.longitude === 0)) throw new UnprocessableEntityException('Invalid location');
    if (pin.accuracyMeters != null && pin.accuracyMeters > 100) throw new UnprocessableEntityException('Location is not precise enough for a pickup point. Move the pin on the map instead.');
    const m = await this.database.client.restaurantMembership.findFirst({ where: { userId: p.userId, restaurantId, status: 'ACTIVE', membershipRole: 'OWNER' } });
    if (!m) throw new ForbiddenException('No active owner membership for this restaurant');
    const r = await this.database.client.restaurant.update({ where: { id: restaurantId }, data: { latitude: new Prisma.Decimal(pin.latitude).toDecimalPlaces(6), longitude: new Prisma.Decimal(pin.longitude).toDecimalPlaces(6), pickupLocationVerifiedAt: new Date() }, select: { id: true, latitude: true, longitude: true, pickupLocationVerifiedAt: true } });
    return { restaurantId: r.id, latitude: num(r.latitude), longitude: num(r.longitude), verifiedAt: r.pickupLocationVerifiedAt };
  }

  // ------------------------------------------------------------ authorized tracking view (REST; also used for socket recovery)
  async view(p: AuthenticatedPrincipal, orderId: string) {
    await this.active(p.userId);
    const o = await this.database.client.order.findUnique({
      where: { id: orderId },
      include: { assignment: { include: { rider: { select: { displayName: true } } } }, tracking: true,
        restaurant: { select: { id: true, name: true, latitude: true, longitude: true, pickupLocationVerifiedAt: true, estimatedDeliveryMaxMinutes: true, schedulePrepMinutes: true } } },
    });
    if (!o) throw new NotFoundException('Order not found');
    const roles = p.roles;
    const allowed = (roles.includes('CUSTOMER') && o.customerId === p.userId) || (roles.includes('DELIVERY_PARTNER') && o.assignment?.riderId === p.userId) || roles.includes('ADMIN')
      || (roles.includes('RESTAURANT_OWNER') && !!(await this.database.client.restaurantMembership.findFirst({ where: { userId: p.userId, restaurantId: o.restaurantId, status: 'ACTIVE', membershipRole: 'OWNER' } })));
    if (!allowed) throw new NotFoundException('Order not found'); // never reveal other orders or riders

    const now = new Date();
    const terminal = TERMINAL.includes(o.status);
    const t = terminal ? null : o.tracking;
    const fresh = freshness(t?.recordedAt, now, terminal);
    const rider = t?.latitude != null ? { latitude: num(t.latitude)!, longitude: num(t.longitude)! } : null;
    const restaurant = o.restaurant.pickupLocationVerifiedAt && o.restaurant.latitude != null ? { latitude: num(o.restaurant.latitude)!, longitude: num(o.restaurant.longitude)! } : null;
    const snap = (o.deliveryAddressSnapshot as any)?.location;
    const destination = t?.destLatitude != null ? { latitude: num(t.destLatitude)!, longitude: num(t.destLongitude)!, source: 'CUSTOMER_PIN' as const }
      : snap && Number.isFinite(snap.latitude) && Number.isFinite(snap.longitude) ? { latitude: Number(snap.latitude), longitude: Number(snap.longitude), source: 'SAVED_ADDRESS' as const } : null;

    const eta = await this.eta(o, { now, rider, riderFresh: fresh.state === 'LIVE' || fresh.state === 'STALE', restaurant, destination, terminal });
    const route = t?.routeGeometry && !terminal && ['PICKED_UP', 'OUT_FOR_DELIVERY'].includes(o.status) && t.etaSource === 'ROUTED' ? (t.routeGeometry as [number, number][]) : null;
    return {
      orderId: o.id, orderNumber: o.orderNumber, status: o.status, terminal, version: o.version,
      trackingActive: !terminal && !!o.assignment && ACTIVE.includes(o.status),
      restaurant: { name: o.restaurant.name, location: restaurant, locationNote: restaurant ? null : 'Restaurant pickup point not configured yet' },
      destination, destinationNote: destination ? null : 'Confirm your delivery pin to see distance and arrival time',
      rider: o.assignment ? { name: o.assignment.rider.displayName.split(' ')[0], location: terminal ? null : rider && t ? { ...rider, accuracyMeters: t.accuracyMeters, headingDegrees: t.headingDegrees, speedMps: t.speedMps, recordedAt: t.recordedAt } : null,
        freshness: fresh.state, ageSeconds: fresh.ageSeconds } : null,
      eta, route,
      routing: { provider: this.routing.name, configured: this.routing.configured },
      schedule: o.deliveryMode === 'SCHEDULED' ? { scheduledDeliveryAt: o.scheduledDeliveryAt, windowStart: o.deliveryWindowStart, windowEnd: o.deliveryWindowEnd } : null,
      serverTime: now.toISOString(),
      rules: { liveSeconds: ETA_RULES.liveSeconds, unavailableSeconds: ETA_RULES.unavailableSeconds },
    };
  }

  private async eta(o: any, c: { now: Date; rider: LatLng | null; riderFresh: boolean; restaurant: LatLng | null; destination: LatLng | null; terminal: boolean }): Promise<EtaResult> {
    const prepMin = o.restaurant.schedulePrepMinutes ?? 20;
    const kitchenReadyAt: Date | null = o.expectedPickupAt ?? (['PENDING_RESTAURANT', 'ACCEPTED', 'PREPARING', 'AWAITING_PAYMENT'].includes(o.status) ? new Date((o.updatedAt as Date).getTime() + prepMin * 60_000) : null);
    const fallbackTravelSeconds = Math.max(10, (o.restaurant.estimatedDeliveryMaxMinutes ?? 40) - prepMin) * 60;
    const base = { now: c.now, status: o.status, rider: c.rider, riderFresh: c.riderFresh, restaurant: c.restaurant, destination: c.destination, kitchenReadyAt, fallbackTravelSeconds, windowEnd: o.deliveryWindowEnd ?? null };
    const t = o.tracking;
    const toCustomer = ['PICKED_UP', 'OUT_FOR_DELIVERY'].includes(o.status) && c.rider && c.riderFresh && c.destination;
    if (c.terminal || !toCustomer) {
      // Pre-pickup / no fix: cheap computation, no routing call; memoize briefly.
      const key = `${o.id}:${o.status}:${!!c.rider}:${!!c.destination}`;
      const hit = this.preRouteCache.get(key);
      if (hit && Date.now() - hit.at < 10_000) return hit.eta;
      const eta = computeEta({ ...base, routeToCustomer: null, routeToRestaurant: null });
      this.preRouteCache.set(key, { at: Date.now(), eta });
      if (this.preRouteCache.size > 500) this.preRouteCache.clear();
      return eta;
    }
    // In transit: reuse the cached road route unless it is older than the refresh interval.
    let route: RouteResult | null = null;
    const cachedFresh = t?.etaComputedAt && c.now.getTime() - t.etaComputedAt.getTime() < ETA_RULES.refreshSeconds * 1000 && t.etaSource === 'ROUTED';
    if (cachedFresh && t.etaDistanceMeters != null && t.etaSeconds != null) {
      // Scale the cached route by elapsed time since it was computed (no new provider request).
      const elapsed = Math.round((c.now.getTime() - t.etaComputedAt.getTime()) / 1000);
      route = { distanceMeters: t.etaDistanceMeters, durationSeconds: Math.max(0, t.etaSeconds - elapsed), geometry: (t.routeGeometry as any) ?? [] };
    } else if (this.routing.configured && (!t?.etaComputedAt || c.now.getTime() - t.etaComputedAt.getTime() >= ETA_RULES.refreshSeconds * 1000)) {
      route = await this.routing.route([c.rider!, c.destination!]);
      const eta = computeEta({ ...base, routeToCustomer: route, routeToRestaurant: null });
      if (route) {
        await this.database.client.deliveryTracking.update({ where: { orderId: o.id }, data: { etaSeconds: route.durationSeconds, etaDistanceMeters: route.distanceMeters, etaSource: 'ROUTED', etaPhase: eta.phase, routeGeometry: route.geometry as any, etaComputedAt: c.now } }).catch(() => undefined);
      } else {
        // Provider failed or was rate-limited (e.g. a concurrent request): retry in ~15 s, and never
        // overwrite a road route computed meanwhile by another request.
        const retryAt = new Date(c.now.getTime() - (ETA_RULES.refreshSeconds - 15) * 1000);
        await this.database.client.deliveryTracking.updateMany({ where: { orderId: o.id, OR: [{ etaComputedAt: null }, { etaComputedAt: { lt: new Date(c.now.getTime() - ETA_RULES.refreshSeconds * 1000) } }] },
          data: { etaSeconds: eta.seconds, etaDistanceMeters: null, etaSource: 'ESTIMATE', etaPhase: eta.phase, routeGeometry: Prisma.JsonNull, etaComputedAt: retryAt } }).catch(() => undefined);
      }
      return eta;
    }
    return computeEta({ ...base, routeToCustomer: route, routeToRestaurant: null });
  }
}
