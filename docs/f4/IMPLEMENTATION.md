# F4 Live Rider Tracking and Smart ETA — Team NeuroX

Branch `feature/f4-live-tracking-eta`, stacked on `feature/f3-scheduled-delivery`. Once F3 is merged with a merge commit, the F4 pull request contains only F4 commits.

## Architecture: different from the old GPS design

| Old (removed in F7) | F4 |
|---|---|
| GPS was mandatory to Go Online and broke dispatch | Go Online, invitations and first-accept-wins never touch GPS |
| Location tied to rider presence | Location tied to **one accepted, active delivery** |
| Map lifecycle crashes | MapController is created with the state, used only after `onMapReady`, and disposed with the screen |

## Rider (delivery partner phone)

- **When it runs:** `RiderTrackingPanel` appears on the active delivery card. Sharing starts automatically only if location is already allowed. Otherwise the rider taps **Share live location** to grant permission. Deliveries always work without it.
- **What it sends:** real hardware fixes from `geolocator` — latitude, longitude, accuracy, heading (only while moving), speed and the device timestamp.
- **Screen off:** an Android foreground service (`foregroundServiceType=location`) shows the ongoing notification "Sharing live location". The app declares `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS` and `WAKE_LOCK`.
- **Battery:** time-based 5 s sampling (no distance filter, so a stationary rider still sends heartbeats). Uploads are throttled to at most one every 5 s, and only when the rider has moved at least 10 m or 15 s have passed (a heartbeat that keeps the customer view LIVE).
- **Recovery states:** permission denied, permission blocked (opens app settings), GPS off (opens location settings), network issues and stream errors are all shown as states and never crash the screen.
- **When it stops:** on 410 or 403 from the server (delivered, canceled, reassigned), when no active delivery remains, and on sign-out. Stopping cancels the stream, which also removes the notification.
- **Nothing is invented:** no simulated or interpolated coordinates are ever sent.

## Backend (`backend/src/modules/tracking`)

- **Migration** `202611240001_live_tracking` (additive): `DeliveryTracking` holds one row per order with the **latest fix only** (no history), the customer's drop pin for that order and the last ETA, with check constraints for shapes and ranges. Rows are removed once the order is terminal (a sweep runs every 60 s).
- **Endpoints:**

  | Endpoint | Who may call it |
  |---|---|
  | `POST /tracking/orders/:id/location` | The assigned rider only, while the delivery is active (READY_FOR_PICKUP, PICKED_UP, OUT_FOR_DELIVERY) |
  | `GET /tracking/orders/:id` | The order's customer, the assigned rider, an active owner of the restaurant, admin. Everyone else gets 404 (orders and riders are never revealed) |
  | `PUT /tracking/orders/:id/destination` | The customer confirms the drop pin (GPS or map) for this order |
  | `PUT /tracking/restaurants/:id/pickup-location` | The outlet's owner confirms the real pickup point. GPS fixes less accurate than 100 m are refused |

- **Fix validation** (on `POST /tracking/orders/:id/location`):

  | Fix | Response |
  |---|---|
  | Coordinates out of range, or exactly 0,0 | 400 / 422 |
  | Accuracy worse than 1000 m, or speed above 70 m/s | 422 |
  | Timestamp more than 30 s in the future or more than 120 s old | 422 |
  | Out-of-order fix | 409 |
  | Less than 2 s after the previous fix | 429 |
  | Order already terminal | 410 |

- **Realtime:** `delivery.location` goes only to the order's `customer:<id>` room, the assigned `delivery:<id>` room and `dispatch`. Reconnect recovery uses the authenticated REST view, and the client also polls every 20 s.
- **Restaurant coordinates:** all 38 development outlets have **no verified pickup coordinates**, so none are invented. Until an owner confirms a point, the restaurant marker is hidden and the screen says so.

## Smart ETA (`eta.ts`, `routing.ts`)

- **Inputs:** kitchen readiness (scheduled `expectedPickupAt` or the preparation estimate), the rider's latest real fix and its freshness, road travel from the routing provider, pickup and delivery state, and the scheduled window.
- **Labels:** `source = ROUTED` uses the provider's road duration and distance. `ESTIMATE` uses straight-line × 1.35 at 18 km/h; it reports `straightLineMeters` and `distanceMeters: null`. The UI says "About X km away in a straight line" and never claims road distance.
- **Rate of routing calls:** routing is called at most once every 45 s per order. In between, the cached road duration is reduced by the elapsed time. GPS updates never trigger routing.
- **Schedule awareness:** `ON_TRACK`, `AT_RISK` or `DELAYED`, measured against the scheduled window end.
- **Providers** (interchangeable): `none` (default) and `osrm` (any OSRM-compatible server). The development `.env` points to the public OSRM demo, which is for light testing only. Production needs a self-hosted OSRM or an approved provider; the deployment plan asks for your approval first.

## Customer tracking screen (`/orders/:id/track`)

- **Entry:** a **Track Order** button in My Orders cards and on active order details.
- **Map:** a large FlutterMap with configurable tiles (`MAP_TILE_URL`; OSM attribution shown). It shows the moving bike marker (rotated by heading), the restaurant marker (when configured), the home marker, the road route polyline (only when routed), a recenter button and follow mode (released when you pan).
- **Marker movement:** the marker moves smoothly between two real fixes over 1.2 s. This is display only; nothing interpolated is stored or sent.
- **ETA card:** shows "Arriving in N min", "Expected by h:mm", the Road route or Estimate label, distance wording, what the estimate is based on, and the scheduled window with an On track / At risk / Delayed chip.
- **States:** "Waiting for rider location", "Updated N seconds ago" with a **LIVE** badge only for fixes up to 30 s old, "Last updated…" when stale, "Rider location temporarily unavailable" after 120 s, and Delivered or ended.
- **Also on the screen:** rider name, a pin-confirmation prompt, a note when the pickup point isn't configured, connection status and the delivery timeline.
- **Owner action:** "Set pickup location" on the kitchen dashboard (GPS at the counter or a map pin).

## Tests

- **Backend unit `tracking.unit.test.ts`:** freshness, estimate vs routed labels, schedule status, fallbacks, OSRM parsing, failure and rate limit.
- **Backend e2e `tracking.e2e.test.ts`:**
  - GPS-free dispatch
  - unauthorized publish and read
  - invalid, future, stale, inaccurate, out-of-order and too-frequent fixes
  - socket privacy, so another customer never receives the fix
  - latest-only storage
  - owner pickup point
  - estimate labels
  - customer pin
  - stale and unavailable states
  - OTP delivery ends tracking and the row is removed
- **Flutter `test/tracking_test.dart`:**
  - freshness and throttle rules
  - permission denied, blocked and GPS off
  - throttled real-fix upload
  - 410 stops the stream (foreground service released)
  - network and stream errors never throw
  - no-coordinates state
  - first fix initializes the map
  - smooth marker movement, and other orders' fixes ignored
  - stale and unavailable states without a LIVE badge
  - reconnect re-reads the view
  - delivery ends tracking

## Limits

- **Two-phone tracking:** physical movement between two phones requires a second Android device, which wasn't connected for this run.
- **Road routing:** on the public OSRM demo, only in development.
- **Tiles:** the OSM tiles default is for development only.
- **Push:** no push notification when the app is closed (in-app socket only).
- **Restaurant coordinates:** each outlet's pickup point must be confirmed by its owner before it appears on the map.
