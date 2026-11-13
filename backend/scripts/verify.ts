import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import { settings } from '../src/config/settings';
const db = createDatabase(settings().databaseUrl);
async function verify() {
  const tables = await db.$queryRaw<Array<{ table_name: string }>>`SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name`;
  const counts = { restaurants: await db.restaurant.count(), items: await db.menuItem.count(), categories: await db.category.count(), cuisines: await db.cuisine.count(), sections: await db.menuSection.count(), zones: await db.deliveryZone.count() };
  const menu = await db.menuItem.findMany({ select: { id: true, restaurantId: true, categoryId: true, basePricePaise: true, imageKey: true, availabilityStatus: true }, orderBy: { displayOrder: 'asc' } });
  console.log(JSON.stringify({ tables: tables.map(t => t.table_name), counts, menu }, null, 2));
}
verify().catch(() => { console.error('Database verification failed. Check configuration and migrations.'); process.exitCode = 1; }).finally(() => db.$disconnect());
