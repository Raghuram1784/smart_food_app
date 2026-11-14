# Development order cleanup — 2026-11-14

Scope: local `food_delivery_dev` only (`NODE_ENV=development`, localhost). Approved by the project owner after a dry run.
Tool: `backend/scripts/cleanup-dev-orders.ts` (dry run by default; `--execute` requires the backup file and its SHA-256 confirm token).

## Synthetic-data checks (every order passed)
- Customer is an `isDemo` account on `@demo.test`
- Restaurant is `isDemo`
- Payment method is `DEMO_NO_PAYMENT` or `RAZORPAY_TEST`; every payment attempt is environment `TEST` with an `rzp_test_` key
- Assignment rider and dispatcher, and every event actor, are demo accounts (or system events with no actor)

## Removed (one transaction, explicit id lists, FK order)
| Table | Rows |
|---|---|
| Order | 9 |
| OrderItem | 11 |
| OrderItemAddOn | 2 |
| OrderEvent | 29 |
| OutboxEvent | 23 |
| PaymentAttempt | 4 |
| DeliveryAssignment | 2 |
| DeliveryHandover / HandoverAudit / PaymentWebhookEvent | 0 |

Orders were created 2026-11-12 → 2026-11-14 at 4 demo restaurants (deccan-handi-gachi, tiffin, prana-bowls-jubilee, chaat-mandi-kondapur).

## Preserved (unchanged counts)
User 31 · Restaurant 28 · RestaurantMembership 28 · MenuItem 224 · Cart 1 · CartQuote 20 · RiderPresence 1. No roles, menus, pricing or delivery configuration touched.

## Verification
- Orphan checks (items, add-ons, events, outbox, payments, assignments, handovers, audits): all 0
- API order lists return 0 for Customer, Owners (Deccan Handi & Dum, The Tiffin Room, Chaat Mandi), Rider and Admin; rider has no active assignment and is dispatchable again

## Backup
A full JSON backup of the deleted rows is kept locally under `backend/.local-backups/` (git-ignored, never committed).
SHA-256 `fb5a7fb09d07941efb5afa8813a6f7624d00b938c8676ea27f7d8e830ae55496`.
