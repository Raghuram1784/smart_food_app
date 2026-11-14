import type { Prisma } from '../../generated/prisma/client';

/**
 * Delivery serviceability policy (single source of truth for discovery, quote and checkout).
 *
 * 1. VERIFIED_DISTANCE — the restaurant has a *verified* pickup point and a configured delivery
 *    radius, and the address has confirmed coordinates: eligible iff the straight-line distance
 *    is within the radius. This is authoritative and overrides service-area coverage.
 * 2. SERVICE_AREA — otherwise, eligibility follows the restaurant's configured service-area
 *    coverage for the service area the customer chose. Distance is NOT verified and no distance
 *    or ETA is claimed.
 * 3. Otherwise not serviceable.
 *
 * Straight-line distance is never presented as road distance; no road ETA is computed.
 */
export type ServiceabilityBasis = 'VERIFIED_DISTANCE' | 'SERVICE_AREA' | 'NONE';
export type ServiceabilityStatus = 'SERVICEABLE' | 'SERVICEABLE_UNVERIFIED_DISTANCE' | 'NOT_SERVICEABLE';

export interface ServiceabilityRestaurant {
  id: string;
  name: string;
  latitude: Prisma.Decimal | number | null;
  longitude: Prisma.Decimal | number | null;
  pickupLocationVerifiedAt: Date | null;
  deliveryRadiusMeters: number | null;
  operatingStatus?: string;
  zones: { zoneId: string; isEligible: boolean }[];
}

export interface ServiceabilityAddress {
  localityId: string | null;
  latitude: Prisma.Decimal | number | null;
  longitude: Prisma.Decimal | number | null;
}

export interface Serviceability {
  restaurantId: string;
  eligible: boolean;
  status: ServiceabilityStatus;
  basis: ServiceabilityBasis;
  /** Straight-line metres; only present for VERIFIED_DISTANCE. */
  straightLineMeters: number | null;
  radiusMeters: number | null;
  reason: string;
}

const num = (v: Prisma.Decimal | number | null | undefined) => (v == null ? null : Number(v));

export function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371008.8;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

export function evaluateServiceability(r: ServiceabilityRestaurant, a: ServiceabilityAddress): Serviceability {
  const base = { restaurantId: r.id, straightLineMeters: null, radiusMeters: null };
  const rLat = num(r.latitude), rLng = num(r.longitude);
  const aLat = num(a.latitude), aLng = num(a.longitude);
  const distancePolicy =
    r.pickupLocationVerifiedAt != null && rLat != null && rLng != null && r.deliveryRadiusMeters != null;

  if (distancePolicy && aLat != null && aLng != null) {
    const meters = Math.round(haversineMeters(rLat!, rLng!, aLat, aLng));
    const eligible = meters <= r.deliveryRadiusMeters!;
    return {
      ...base,
      eligible,
      status: eligible ? 'SERVICEABLE' : 'NOT_SERVICEABLE',
      basis: 'VERIFIED_DISTANCE',
      straightLineMeters: meters,
      radiusMeters: r.deliveryRadiusMeters,
      reason: eligible
        ? `Within ${r.name}'s ${(r.deliveryRadiusMeters! / 1000).toFixed(1)} km delivery radius (straight line).`
        : `${r.name} delivers within ${(r.deliveryRadiusMeters! / 1000).toFixed(1)} km (straight line); this address is ${(meters / 1000).toFixed(1)} km away.`,
    };
  }

  const covered = a.localityId != null && r.zones.some((z) => z.zoneId === a.localityId && z.isEligible);
  if (covered) {
    const why = !distancePolicy
      ? "the restaurant's pickup location is not verified"
      : 'this address has no confirmed map location';
    return {
      ...base,
      eligible: true,
      status: 'SERVICEABLE_UNVERIFIED_DISTANCE',
      basis: 'SERVICE_AREA',
      reason: `${r.name} serves the selected service area. Exact distance is not verified because ${why}.`,
    };
  }

  return {
    ...base,
    eligible: false,
    status: 'NOT_SERVICEABLE',
    basis: 'NONE',
    reason: a.localityId == null
      ? `This address is outside the current delivery service areas, so ${r.name} can't deliver there.`
      : `${r.name} does not deliver to the selected service area.`,
  };
}

export const serviceabilitySelect = {
  id: true,
  name: true,
  latitude: true,
  longitude: true,
  pickupLocationVerifiedAt: true,
  deliveryRadiusMeters: true,
  operatingStatus: true,
  zones: { select: { zoneId: true, isEligible: true } },
} as const;
