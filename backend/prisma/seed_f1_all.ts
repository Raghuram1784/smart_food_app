/**
 * F1 demo data, in order: catalog + profiles + nutrition, brand outlets, then catalog again so
 * outlet menu copies also get profiles/nutrition. Every step is create-only and idempotent.
 *   npx tsx prisma/seed_f1_all.ts
 */
import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import { seedFoodFinderCatalog } from './seed_food_finder_catalog';
import { seedOutlets } from './seed_outlets';

export async function seedF1All(db: ReturnType<typeof createDatabase>) {
  const catalog = await seedFoodFinderCatalog(db);
  const outlets = await seedOutlets(db);
  const catalogAgain = await seedFoodFinderCatalog(db);
  return { catalog, outlets, catalogAgain };
}

if (require.main === module) {
  const url = process.env.DATABASE_URL!;
  const db = createDatabase(url);
  seedF1All(db)
    .then((r) => console.log(JSON.stringify({ event: 'f1_seed', database: new URL(url).pathname.slice(1), ...r })))
    .catch((e) => { console.error(e instanceof Error ? e.message : e); process.exitCode = 1; })
    .finally(() => db.$disconnect());
}
