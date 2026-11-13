# Razorpay Test Mode setup

Configure `RAZORPAY_KEY_ID` (rzp_test_ prefix) and `RAZORPAY_KEY_SECRET` only in ignored `backend/.env`, with NODE_ENV=development. Restart the backend after changing credentials. Do not distribute secrets, integration-test configuration, or test APKs containing demo login defines. The normal app receives only the public key from its authenticated backend.

Run `npm run db:generate`, `npm run db:migrate`, `npm run build`, and `npm start` in backend. Migration 202611130001_payments is additive and preserves existing indexes and orders. Never reset PostgreSQL or rerun outdated catalog seeds.

In Flutter, sign in as customer, add items, choose a saved address, review the authoritative quote, enable **Razorpay Test Payment**, and confirm the order. On confirmation/details, select **Pay with Razorpay TEST**. Use only Razorpay's documented test instruments. Check backend-confirmed payment status after returning. Existing unpaid demo orders intentionally have no Pay button.

Flutter Checkout is provided by the official Android/iOS plugin. The current integration is verified primarily on Android; browser/Windows Checkout is not implemented.

## Webhook configuration pending

The local environment does not have RAZORPAY_WEBHOOK_SECRET or a publicly reachable HTTPS endpoint. Local signature/deduplication tests are separate from genuine provider delivery. To enable delivery, configure the public HTTPS URL ending `/api/v1/payments/razorpay/webhook` in the Razorpay Test dashboard, configure the same secret privately on the backend, and subscribe to payment.authorized, payment.captured, payment.failed and order.paid. The API key secret is not the webhook secret. Confirm delivery/retries in the dashboard and persisted inbox before reporting live webhook verification.

Use automatic capture in the Test dashboard if desired. An authorized-only payment remains unpaid until capture is confirmed; no artificial backend success toggle or automatic manual capture is provided.

## Verification scripts

- Backend `test/commerce.e2e.test.ts` includes isolated payment safety checks using a provider double bound only in the test process and food_delivery_test PostgreSQL.
- `test/payment_test.dart` tests native callbacks with a test-only method channel and backend-owned UI state.
- `backend/scripts/verify-razorpay-test.ts` creates one genuine test provider order for the demo customer only when its cart is empty; it reuses the ignored build/razorpay-test-order.json reference on retry. It must not be used as a general seed.
- `integration_test/razorpay_test.dart` launches genuine native Checkout for EVIDENCE_ORDER_ID and waits for server-confirmed capture. It requires interactive completion using provider test instruments; it does not fabricate callbacks.

Official references: [Flutter integration](https://razorpay.com/docs/payments/payment-gateway/flutter-integration/standard/integration-steps), [create order](https://razorpay.com/docs/api/orders/create), [receipt lookup](https://razorpay.com/docs/api/orders/fetch-all), [fetch payment](https://razorpay.com/docs/api/payments/fetch-with-id), [webhook validation](https://razorpay.com/docs/webhooks/validate-test).
