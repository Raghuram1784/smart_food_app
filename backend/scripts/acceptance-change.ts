import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import { settings } from '../src/config/settings';
const config = settings();
if (config.production || new URL(config.databaseUrl).pathname !== '/food_delivery_dev') {
  throw new Error('Acceptance changes are restricted to food_delivery_dev');
}
const db = createDatabase(config.databaseUrl);
async function run() {
  const restore = process.argv[2] === 'restore';
  if (!restore && process.argv[2] !== 'change') throw new Error('Use change or restore');
  const expected = restore ? 14937 : 14900;
  const target = restore ? 14900 : 14937;
  const updated = await db.menuItem.updateMany({
    where: { id: 'dosa', basePricePaise: expected, restaurantId: 'tiffin' },
    data: { basePricePaise: target, version: { increment: 1 } },
  });
  const record = await db.menuItem.findUniqueOrThrow({ where: { id: 'dosa' } });
  if (record.basePricePaise !== target) throw new Error('Unexpected existing price; no overwrite allowed');
  const response = await fetch('http://127.0.0.1:5000/api/v1/menu-items/dosa');
  const body = await response.json() as { data: { basePricePaise: number } };
  if (!response.ok || body.data.basePricePaise !== target) throw new Error('API did not reflect database update');
  console.log(JSON.stringify({ action: restore ? 'restored' : 'changed', updated: updated.count, databasePaise: record.basePricePaise, apiPaise: body.data.basePricePaise }));
}
run().catch(() => { console.error('Acceptance change verification failed; inspect the dedicated development record.'); process.exitCode = 1; }).finally(() => db.$disconnect());
