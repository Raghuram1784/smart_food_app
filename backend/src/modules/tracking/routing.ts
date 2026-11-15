/**
 * Interchangeable road-routing providers for F4 smart ETA.
 *
 * - `none` (default): no routing service. ETAs are labeled ESTIMATE and never claim road distance.
 * - `osrm`: any OSRM-compatible HTTP server (self-hosted, or the public demo server for light
 *   development testing only, per its usage policy). Configure ROUTING_PROVIDER=osrm and ROUTING_BASE_URL.
 *
 * Providers are only asked for a route when the cached ETA is older than the refresh interval,
 * never once per GPS update.
 */
export interface LatLng { latitude: number; longitude: number }
export interface RouteResult { distanceMeters: number; durationSeconds: number; geometry: [number, number][] /* [lat, lng] */ }

export interface RoutingProvider {
  readonly name: string;
  readonly configured: boolean;
  route(points: LatLng[]): Promise<RouteResult | null>;
}

export class NoRoutingProvider implements RoutingProvider {
  readonly name = 'none';
  readonly configured = false;
  async route(): Promise<RouteResult | null> { return null; }
}

export class OsrmRoutingProvider implements RoutingProvider {
  readonly name = 'osrm';
  readonly configured = true;
  private lastCall = 0;
  constructor(private readonly baseUrl: string, private readonly timeoutMs = 4000, private readonly minIntervalMs = 1100, private readonly fetcher: typeof fetch = fetch) {}

  async route(points: LatLng[]): Promise<RouteResult | null> {
    if (points.length < 2) return null;
    // Respect provider rate limits (the public demo allows about one request per second).
    const wait = this.lastCall + this.minIntervalMs - Date.now();
    if (wait > 0) return null;
    this.lastCall = Date.now();
    const coords = points.map((p) => `${p.longitude.toFixed(6)},${p.latitude.toFixed(6)}`).join(';');
    const url = `${this.baseUrl.replace(/\/+$/, '')}/route/v1/driving/${coords}?overview=simplified&geometries=geojson&alternatives=false&steps=false`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), this.timeoutMs);
    try {
      const r = await this.fetcher(url, { signal: ctrl.signal, headers: { 'user-agent': 'neurox-food-delivery-dev/1.0' } });
      if (!r.ok) return null;
      const body: any = await r.json();
      const route = body?.code === 'Ok' ? body.routes?.[0] : null;
      if (!route || !Number.isFinite(route.distance) || !Number.isFinite(route.duration)) return null;
      const line = (route.geometry?.coordinates ?? []) as [number, number][];
      return { distanceMeters: Math.round(route.distance), durationSeconds: Math.round(route.duration), geometry: line.slice(0, 500).map(([lng, lat]) => [lat, lng]) };
    } catch {
      return null; // Routing failures fall back to labeled estimates; they never break tracking.
    } finally {
      clearTimeout(timer);
    }
  }
}

export function routingFromEnv(env: NodeJS.ProcessEnv = process.env): RoutingProvider {
  const kind = (env.ROUTING_PROVIDER ?? 'none').trim().toLowerCase();
  const base = env.ROUTING_BASE_URL?.trim();
  if (kind === 'osrm' && base && /^https?:\/\//.test(base)) return new OsrmRoutingProvider(base);
  return new NoRoutingProvider();
}
