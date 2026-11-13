# Phase 7 real-time architecture

Flutter action → authenticated REST endpoint → PostgreSQL transaction (order + audit event + outbox) → commit → dispatcher → authorized Socket.IO notification → Flutter refetches authoritative REST snapshot.

NestJS Socket.IO gateway shares HTTP port 5000, default `/socket.io` path and namespace. Official NestJS 11 adapters and socket_io_client 3.1.6 are used. Connect using handshake `auth: {token: opaqueSession}`; tokens in URL query strings are rejected and never logged. No JWT replacement.

## Authorization

Handshake uses existing SessionVerifier (active account, unexpired/unrevoked session, current roles, demo-auth restriction). Server assigns rooms from verified database context: customer:{id}, restaurant:{id} for active owner memberships, delivery:{id}, and explicit admin dispatch room. Clients cannot select arbitrary rooms. `order.subscribe` accepts an orderId and returns `{ok,version}` only after ownership/assignment/membership verification; notifications already use server-derived rooms. Admin does not have arbitrary customer-order subscription scope.

Every private emission revalidates the session and derives room membership again; expired/revoked sessions or removed roles cannot receive subsequent private events. Idle sockets revalidate every 15 seconds and disconnect if invalid. Membership changes remove obsolete restaurant rooms. Minimal event payload contains no address, phone, token, amount or payment secrets.

## Event contract

Event: `order.updated`

Payload: `{eventId, orderId, status, previousStatus, version, updatedAt, eventType}`. Event type distinguishes ORDER_CREATED, PAYMENT_CAPTURED, ORDER_ACCEPTED, ORDER_REJECTED, PREPARATION_STARTED, ORDER_READY, RIDER_ASSIGNED, ORDER_PICKED_UP, OUT_FOR_DELIVERY and ORDER_DELIVERED.

Recipients: owning customer, current restaurant owners, assigned rider, and admins only for delivery-stage orders. A notification is an invalidation signal, not permission to mutate local order status. REST remains usable without a socket.

## Outbox and recovery

OutboxEvent is inserted in the same transaction as its OrderEvent. A single-process dispatcher scans up to 50 pending rows every second, publishes only committed data, then records dispatchedAt and attempts. Failed publication leaves the row pending with exponential retry capped at 60 seconds. A crash between publish and marking dispatched can duplicate delivery. No receiver ACK/replay guarantee is claimed: disconnected/no-listener users recover from REST. Successful emit with zero connected recipients is a dispatched notification.

One NestJS instance is supported. The in-process running guard prevents overlapping local scans, not multi-instance processing. Before scaling, add leased/locked outbox claims and a shared Socket.IO adapter (with fresh authorization); do not simply run multiple dispatchers against this database. Retention/dead-letter administration is deferred.

## Flutter behavior

One auth-scoped socket uses the secure session vault; account/session changes dispose the prior socket. Logout invalidation disconnects immediately. Foreground reconnects and refetches REST; background disconnects. Automatic transport reconnection is bounded to five attempts with 1–10 second backoff; manual refresh/retry remains available. Reconnection reauthenticates and server-derived rooms are restored. No missed-event replay is assumed.

Per-order version tracking rejects duplicate/stale notifications. Accepted notifications invalidate REST providers; the UI never advances a status from a timer or assumes the client payload is authoritative. Timeline displays actual persisted events. Connection state, manual refresh, and REST errors are explicit. No GPS/map/ETA simulation is included.

References: [NestJS gateways](https://docs.nestjs.com/websockets/gateways), [Socket.IO middleware](https://socket.io/docs/v4/middlewares), [delivery guarantees](https://socket.io/docs/v4/delivery-guarantees/), [Flutter client](https://pub.dev/packages/socket_io_client).
