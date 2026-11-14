/**
 * Development-only cleanup of synthetic test orders.
 *
 *   npx tsx scripts/cleanup-dev-orders.ts            # dry run + verified backup (default, deletes nothing)
 *   npx tsx scripts/cleanup-dev-orders.ts --execute --backup <file> --confirm <token>
 *
 * Safety:
 *  - Requires NODE_ENV=development and the exact database name food_delivery_dev.
 *  - Every order must be provably synthetic (demo customer on @demo.test, demo restaurant,
 *    demo/test payment method, Razorpay TEST attempts only, demo riders/dispatchers/actors).
 *    If any single order fails a check, nothing is deleted.
 *  - Never touches users, roles, memberships, restaurants, menus, carts, pricing or presence.
 *  - Deletes by explicit id lists only, in FK order, inside one transaction, after verifying
 *    the backup file's SHA-256 and that the selected ids still match the backup exactly.
 *  - Backups are written under backend/.local-backups/ (git-ignored) and never committed.
 */
import 'dotenv/config';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createDatabase } from '../src/database/client';

const EXPECTED_DB = 'food_delivery_dev';
const DEMO_DOMAIN = '@demo.test';
const BACKUP_DIR = resolve(__dirname, '..', '.local-backups');

type Db = ReturnType<typeof createDatabase>;

function guardEnvironment(): string {
  const url = process.env.DATABASE_URL;
  if (process.env.NODE_ENV !== 'development') throw new Error('Refusing: NODE_ENV must be development');
  if (!url) throw new Error('Refusing: DATABASE_URL missing');
  const parsed = new URL(url);
  const dbName = parsed.pathname.replace(/^\//, '');
  if (dbName !== EXPECTED_DB) throw new Error(`Refusing: database is "${dbName}", expected "${EXPECTED_DB}"`);
  if (!['localhost', '127.0.0.1', '::1'].includes(parsed.hostname)) throw new Error('Refusing: database host is not local');
  return url;
}

async function collect(db: Db) {
  const orders = await db.order.findMany({
    include: {
      customer: { select: { id: true, email: true, isDemo: true } },
      restaurant: { select: { id: true, isDemo: true } },
      items: { include: { addOns: true } },
      events: { include: { outbox: true, actor: { select: { email: true, isDemo: true } } } },
      paymentAttempts: true,
      assignment: {
        include: {
          rider: { select: { email: true, isDemo: true } },
          assignedBy: { select: { email: true, isDemo: true } },
        },
      },
      handover: { include: { audit: true } },
    },
    orderBy: { createdAt: 'asc' },
  });

  const violations: string[] = [];
  const isDemoUser = (u: { email: string; isDemo: boolean } | null | undefined) =>
    !!u && u.isDemo && u.email.toLowerCase().endsWith(DEMO_DOMAIN);

  for (const o of orders) {
    const why: string[] = [];
    if (!isDemoUser(o.customer)) why.push('customer is not a demo @demo.test account');
    if (!o.restaurant.isDemo) why.push('restaurant is not marked isDemo');
    if (!['DEMO_NO_PAYMENT', 'RAZORPAY_TEST'].includes(o.paymentMethod)) why.push(`payment method ${o.paymentMethod}`);
    for (const p of o.paymentAttempts) {
      if (p.environment !== 'TEST' || !p.keyId.startsWith('rzp_test_')) why.push(`payment attempt ${p.id} is not Razorpay TEST`);
    }
    if (o.assignment && (!isDemoUser(o.assignment.rider) || !isDemoUser(o.assignment.assignedBy))) {
      why.push('assignment rider/dispatcher is not a demo account');
    }
    for (const e of o.events) if (e.actor && !isDemoUser(e.actor)) why.push(`event ${e.id} actor is not a demo account`);
    if (why.length) violations.push(`${o.orderNumber}: ${why.join('; ')}`);
  }

  const providerOrderIds = orders.flatMap((o) => o.paymentAttempts.map((p) => p.providerOrderId)).filter((x): x is string => !!x);
  const webhooks = providerOrderIds.length
    ? await db.paymentWebhookEvent.findMany({ where: { providerOrderId: { in: providerOrderIds } } })
    : [];

  const ids = {
    handoverAudit: orders.flatMap((o) => o.handover?.audit.map((a) => a.id) ?? []),
    deliveryHandover: orders.flatMap((o) => (o.handover ? [o.handover.id] : [])),
    deliveryAssignment: orders.flatMap((o) => (o.assignment ? [o.assignment.id] : [])),
    outboxEvent: orders.flatMap((o) => o.events.flatMap((e) => (e.outbox ? [e.outbox.id] : []))),
    orderEvent: orders.flatMap((o) => o.events.map((e) => e.id)),
    orderItemAddOn: orders.flatMap((o) => o.items.flatMap((i) => i.addOns.map((a) => a.id))),
    orderItem: orders.flatMap((o) => o.items.map((i) => i.id)),
    paymentWebhookEvent: webhooks.map((w) => w.id),
    paymentAttempt: orders.flatMap((o) => o.paymentAttempts.map((p) => p.id)),
    order: orders.map((o) => o.id),
  };
  return { orders, webhooks, ids, violations };
}

function summarize(ids: Record<string, string[]>) {
  return Object.fromEntries(Object.entries(ids).map(([k, v]) => [k, v.length]));
}

async function main() {
  const url = guardEnvironment();
  const args = process.argv.slice(2);
  const execute = args.includes('--execute');
  const arg = (name: string) => {
    const i = args.indexOf(name);
    return i >= 0 ? args[i + 1] : undefined;
  };
  const db = createDatabase(url);
  try {
    const { orders, webhooks, ids, violations } = await collect(db);
    console.log(`Database: ${EXPECTED_DB} (NODE_ENV=development, local host)`);
    console.log('Rows selected for deletion (FK-safe order):');
    console.table(summarize(ids));
    console.log('Orders:');
    console.table(orders.map((o) => ({ orderNumber: o.orderNumber, status: o.status, payment: o.paymentMethod, restaurant: o.restaurantId, createdAt: o.createdAt.toISOString() })));
    if (violations.length) {
      console.error('STOP: some orders are not provably synthetic. Nothing will be deleted.');
      for (const v of violations) console.error('  - ' + v);
      process.exitCode = 3;
      return;
    }
    console.log('All selected orders passed every synthetic-data check.');

    if (!execute) {
      if (!existsSync(BACKUP_DIR)) mkdirSync(BACKUP_DIR, { recursive: true });
      const stamp = new Date().toISOString().replace(/[:.]/g, '-');
      const file = join(BACKUP_DIR, `dev-orders-${stamp}.json`);
      const payload = JSON.stringify({ createdAt: new Date().toISOString(), database: EXPECTED_DB, counts: summarize(ids), ids, orders, webhooks }, null, 2);
      writeFileSync(file, payload, { encoding: 'utf8', mode: 0o600 });
      const written = readFileSync(file, 'utf8');
      const sha = createHash('sha256').update(written).digest('hex');
      const reparsed = JSON.parse(written);
      if (written !== payload || reparsed.orders.length !== orders.length) throw new Error('Backup verification failed');
      console.log(`DRY RUN — nothing deleted.\nBackup: ${file}\nSHA-256: ${sha}`);
      console.log(`Confirm token: ${sha.slice(0, 12)}`);
      return;
    }

    // --- Execute path ---------------------------------------------------------
    const backupFile = arg('--backup');
    const token = arg('--confirm');
    if (!backupFile || !token) throw new Error('--execute requires --backup <file> and --confirm <token>');
    const backupText = readFileSync(resolve(backupFile), 'utf8');
    const sha = createHash('sha256').update(backupText).digest('hex');
    if (sha.slice(0, 12) !== token) throw new Error('Confirm token does not match backup SHA-256');
    const backup = JSON.parse(backupText) as { ids: Record<string, string[]> };
    for (const [k, v] of Object.entries(ids)) {
      const b = [...(backup.ids[k] ?? [])].sort().join(',');
      if ([...v].sort().join(',') !== b) throw new Error(`Live rows for ${k} differ from the backup; re-run the dry run`);
    }

    const deleted = await db.$transaction(async (tx) => {
      const r: Record<string, number> = {};
      r.handoverAudit = (await tx.handoverAudit.deleteMany({ where: { id: { in: ids.handoverAudit } } })).count;
      r.deliveryHandover = (await tx.deliveryHandover.deleteMany({ where: { id: { in: ids.deliveryHandover } } })).count;
      r.deliveryAssignment = (await tx.deliveryAssignment.deleteMany({ where: { id: { in: ids.deliveryAssignment } } })).count;
      r.outboxEvent = (await tx.outboxEvent.deleteMany({ where: { id: { in: ids.outboxEvent } } })).count;
      r.orderEvent = (await tx.orderEvent.deleteMany({ where: { id: { in: ids.orderEvent } } })).count;
      r.orderItemAddOn = (await tx.orderItemAddOn.deleteMany({ where: { id: { in: ids.orderItemAddOn } } })).count;
      r.orderItem = (await tx.orderItem.deleteMany({ where: { id: { in: ids.orderItem } } })).count;
      r.paymentWebhookEvent = (await tx.paymentWebhookEvent.deleteMany({ where: { id: { in: ids.paymentWebhookEvent } } })).count;
      r.paymentAttempt = (await tx.paymentAttempt.deleteMany({ where: { id: { in: ids.paymentAttempt } } })).count;
      r.order = (await tx.order.deleteMany({ where: { id: { in: ids.order } } })).count;
      for (const [k, v] of Object.entries(ids)) {
        if (r[k] !== v.length) throw new Error(`Deleted ${r[k]} ${k} rows, expected ${v.length}; rolling back`);
      }
      return r;
    }, { timeout: 30000 });
    console.log('Deleted (committed):');
    console.table(deleted);

    // Integrity: no orphans may remain.
    const orphanChecks = await db.$queryRawUnsafe<{ check: string; n: number }[]>(`
      SELECT 'OrderItem without Order' AS check, count(*)::int n FROM "OrderItem" i LEFT JOIN "Order" o ON o.id=i."orderId" WHERE o.id IS NULL
      UNION ALL SELECT 'OrderItemAddOn without OrderItem', count(*)::int FROM "OrderItemAddOn" a LEFT JOIN "OrderItem" i ON i.id=a."orderItemId" WHERE i.id IS NULL
      UNION ALL SELECT 'OrderEvent without Order', count(*)::int FROM "OrderEvent" e LEFT JOIN "Order" o ON o.id=e."orderId" WHERE o.id IS NULL
      UNION ALL SELECT 'OutboxEvent without OrderEvent', count(*)::int FROM "OutboxEvent" x LEFT JOIN "OrderEvent" e ON e.id=x."eventId" WHERE e.id IS NULL
      UNION ALL SELECT 'PaymentAttempt without Order', count(*)::int FROM "PaymentAttempt" p LEFT JOIN "Order" o ON o.id=p."orderId" WHERE o.id IS NULL
      UNION ALL SELECT 'DeliveryAssignment without Order', count(*)::int FROM "DeliveryAssignment" d LEFT JOIN "Order" o ON o.id=d."orderId" WHERE o.id IS NULL
      UNION ALL SELECT 'DeliveryHandover without Order', count(*)::int FROM "DeliveryHandover" h LEFT JOIN "Order" o ON o.id=h."orderId" WHERE o.id IS NULL
      UNION ALL SELECT 'HandoverAudit without Handover', count(*)::int FROM "HandoverAudit" a LEFT JOIN "DeliveryHandover" h ON h.id=a."handoverId" WHERE h.id IS NULL`);
    console.table(orphanChecks);
    if (orphanChecks.some((c) => c.n > 0)) process.exitCode = 4;
  } finally {
    await db.$disconnect();
  }
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exitCode = 1;
});
