/**
 * Smart ETA (pure functions, no I/O).
 *
 * Combines kitchen progress, the rider's latest real GPS fix, road travel from a routing provider
 * when available, and the scheduled delivery window. When road routing is unavailable the travel
 * leg is an ESTIMATE derived from straight-line distance with an urban detour factor; it is labeled
 * as such and the straight-line figure is never presented as road distance.
 */
import type { LatLng, RouteResult } from './routing';

export const ETA_RULES = {
  liveSeconds: 30,          // fix younger than this: LIVE
  unavailableSeconds: 120,  // older than this: temporarily unavailable
  refreshSeconds: 45,       // minimum time between routing requests per order
  detourFactor: 1.35,       // straight line -> typical Hyderabad road distance
  fallbackSpeedKmh: 18,     // two-wheeler urban average for estimates
  handoffSeconds: 120,      // parking + walking to the door
  pickupSeconds: 180,       // collecting the order at the restaurant
};

export type Freshness = 'WAITING' | 'LIVE' | 'STALE' | 'UNAVAILABLE' | 'ENDED';
export type EtaPhase = 'PREPARING' | 'TO_RESTAURANT' | 'TO_CUSTOMER' | 'DELIVERED' | 'ENDED';

export function haversineMeters(a: LatLng, b: LatLng): number {
  const R = 6371000, rad = Math.PI / 180;
  const dLat = (b.latitude - a.latitude) * rad, dLng = (b.longitude - a.longitude) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function freshness(recordedAt: Date | null | undefined, now: Date, terminal: boolean): { state: Freshness; ageSeconds: number | null } {
  if (terminal) return { state: 'ENDED', ageSeconds: null };
  if (!recordedAt) return { state: 'WAITING', ageSeconds: null };
  const age = Math.max(0, Math.round((now.getTime() - recordedAt.getTime()) / 1000));
  return { state: age <= ETA_RULES.liveSeconds ? 'LIVE' : age <= ETA_RULES.unavailableSeconds ? 'STALE' : 'UNAVAILABLE', ageSeconds: age };
}

/** Travel leg: routed when the provider answered, otherwise a labeled estimate. */
export function travelLeg(from: LatLng, to: LatLng, routed: RouteResult | null) {
  if (routed) return { seconds: routed.durationSeconds, distanceMeters: routed.distanceMeters, source: 'ROUTED' as const, straightLineMeters: null };
  const straight = haversineMeters(from, to);
  const estimatedRoad = straight * ETA_RULES.detourFactor;
  return { seconds: Math.round(estimatedRoad / (ETA_RULES.fallbackSpeedKmh / 3.6)), distanceMeters: null, source: 'ESTIMATE' as const, straightLineMeters: Math.round(straight) };
}

export interface EtaInput {
  now: Date;
  status: string;
  rider: LatLng | null;           // latest real fix (null when none / unavailable)
  riderFresh: boolean;            // fix is LIVE or STALE (not unavailable)
  restaurant: LatLng | null;      // configured, verified pickup point only
  destination: LatLng | null;     // confirmed delivery pin only
  kitchenReadyAt: Date | null;    // expectedPickupAt (scheduled) or estimate
  fallbackTravelSeconds: number;  // restaurant timing estimate when coordinates are missing
  windowEnd: Date | null;
  routeToCustomer: RouteResult | null;
  routeToRestaurant: RouteResult | null;
}

export interface EtaResult {
  phase: EtaPhase;
  seconds: number | null;
  arrivalAt: string | null;
  distanceMeters: number | null;        // road distance, only when routed
  straightLineMeters: number | null;    // shown as "straight line", never as road distance
  source: 'ROUTED' | 'ESTIMATE' | null;
  basis: string;
  scheduleStatus: 'ON_TRACK' | 'AT_RISK' | 'DELAYED' | null;
}

const TERMINAL = ['DELIVERED', 'CANCELED', 'REJECTED'];

export function computeEta(i: EtaInput): EtaResult {
  const end = (phase: EtaPhase, basis: string): EtaResult => ({ phase, seconds: null, arrivalAt: null, distanceMeters: null, straightLineMeters: null, source: null, basis, scheduleStatus: null });
  if (i.status === 'DELIVERED') return end('DELIVERED', 'Delivered');
  if (TERMINAL.includes(i.status)) return end('ENDED', 'Tracking ended');

  let seconds = 0, source: 'ROUTED' | 'ESTIMATE' = 'ESTIMATE', distance: number | null = null, straight: number | null = null;
  let phase: EtaPhase; const parts: string[] = [];
  const toCustomerFrom = (from: LatLng, route: RouteResult | null) => {
    const leg = travelLeg(from, i.destination!, route);
    seconds += leg.seconds + ETA_RULES.handoffSeconds; source = leg.source; distance = leg.distanceMeters; straight = leg.straightLineMeters;
    parts.push(leg.source === 'ROUTED' ? 'road route to you' : 'estimated travel to you (no road route available)');
  };

  if (['PICKED_UP', 'OUT_FOR_DELIVERY'].includes(i.status)) {
    phase = 'TO_CUSTOMER';
    if (i.rider && i.riderFresh && i.destination) toCustomerFrom(i.rider, i.routeToCustomer);
    else { seconds += i.fallbackTravelSeconds; parts.push(i.destination ? 'restaurant timing estimate (rider location unavailable)' : 'restaurant timing estimate (delivery pin not confirmed)'); }
  } else {
    // Before pickup: remaining kitchen time, rider to restaurant, then restaurant to customer.
    phase = i.status === 'READY_FOR_PICKUP' && i.rider ? 'TO_RESTAURANT' : 'PREPARING';
    const kitchen = i.kitchenReadyAt ? Math.max(0, Math.round((i.kitchenReadyAt.getTime() - i.now.getTime()) / 1000)) : 0;
    let toRestaurant = 0;
    if (i.rider && i.riderFresh && i.restaurant) {
      const leg = travelLeg(i.rider, i.restaurant, i.routeToRestaurant);
      toRestaurant = leg.seconds;
      parts.push(leg.source === 'ROUTED' ? 'rider road route to restaurant' : 'estimated rider travel to restaurant');
      if (leg.source === 'ESTIMATE') source = 'ESTIMATE';
    }
    seconds += Math.max(kitchen, toRestaurant) + ETA_RULES.pickupSeconds;
    if (kitchen > 0) parts.unshift('kitchen preparation');
    if (i.restaurant && i.destination) {
      const leg = travelLeg(i.restaurant, i.destination, null);
      seconds += leg.seconds + ETA_RULES.handoffSeconds; straight = leg.straightLineMeters;
      parts.push('estimated travel from restaurant to you');
    } else { seconds += i.fallbackTravelSeconds; parts.push('restaurant timing estimate'); }
    source = 'ESTIMATE'; // before pickup the customer leg is always an estimate
  }

  const arrival = new Date(i.now.getTime() + seconds * 1000);
  let scheduleStatus: EtaResult['scheduleStatus'] = null;
  if (i.windowEnd) scheduleStatus = i.now > i.windowEnd ? 'DELAYED' : arrival <= i.windowEnd ? 'ON_TRACK' : 'AT_RISK';
  return { phase, seconds, arrivalAt: arrival.toISOString(), distanceMeters: distance, straightLineMeters: straight, source, basis: parts.join(' + '), scheduleStatus };
}
