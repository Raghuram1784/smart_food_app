# Test payment flow

The existing opaque-session authentication and CUSTOMER role guard protect payment creation, verification, and status. Ownership is checked server-side. Old DEMO_NO_PAYMENT orders cannot be paid or converted. New RAZORPAY_TEST orders begin AWAITING_PAYMENT. Cart pricing and immutable order snapshots remain authoritative; clients cannot submit payment amounts.

1. `POST /api/v1/orders` saves the merchant order using the existing quote and idempotency key.
2. `POST /api/v1/payments/razorpay/create-order` accepts only `orderId`. Under the existing customer transaction lock, it claims one unique PaymentAttempt per merchant order. The server creates a genuine provider order using the stored integer INR amount and a unique receipt. The response contains the public test key, amount, currency, attempt ID and provider order ID. The secret never leaves the backend.
3. Flutter opens official razorpay_flutter Checkout. Cancellation/failure does not mark anything paid. Retry reuses the existing provider order and rechecks provider payments first.
4. `POST /api/v1/payments/razorpay/verify` checks HMAC-SHA256 over the stored provider order ID and submitted payment ID with constant-time comparison. The server fetches the provider payment and validates its ID, order ID, currency and exact amount. Authorization alone remains PAYMENT_AUTHORIZED. Only captured status plus captured=true permits PAID.
5. Order payment state, attempt state and one PAYMENT_CAPTURED event commit atomically under an order row lock. Successful payment moves AWAITING_PAYMENT to PENDING_RESTAURANT; this does not accept or fulfill the order. Capture cannot be downgraded by delayed failure events.
6. `GET /api/v1/payments/orders/:id/status` reconciles provider state, throttled to one request per ten seconds. Flutter checks on open, return to foreground, callbacks, and manual refresh. A network error reports verification pending; it never fabricates success.

## Ambiguous requests

The database claim precedes external network I/O. Only the creator submits the provider POST. If the response is lost, the attempt becomes CREATE_UNKNOWN. Recovery queries provider orders by the stored receipt and attaches the matching order after amount/currency validation. If no provider order is found, absence is not proof of failure: the server does not automatically issue another POST. Manual reconciliation is required if the reference remains absent or multiple references exist. This conservative case can leave an unpaid order pending; do not create replacement charges blindly.

One PaymentAttempt represents the provider-order lifecycle, with the latest relevant payment ID. Failed provider payment retries use the same provider order. This is not a complete ledger of every SDK cancellation or provider payment attempt; refunds and Live Mode are outside this phase.

## Optional webhook

`POST /api/v1/payments/razorpay/webhook` consumes the raw JSON bytes (128 KB limit). It requires the separately configured webhook secret, verifies its HMAC, and deduplicates `x-razorpay-event-id` using a unique database inbox record and payload hash. Reusing an ID with different bytes is rejected. Recognized events trigger a fresh provider read, not blind trust in webhook claims. Missing configuration rejects the request. A crash after payment commit but before inbox completion is safely replayable. Unknown provider orders remain unprocessed and return a retryable response.

Production NODE_ENV and live keys are rejected by payment configuration. These are demo-authenticated test-mode flows, not a production deployment.
