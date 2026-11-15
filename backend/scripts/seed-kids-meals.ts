/**
 * Kids Meals catalog seed (v1.1). Additive and idempotent:
 * - creates a "Kids Meals" section per restaurant only if missing;
 * - creates each dish only if neither its id nor its name already exists in that restaurant;
 * - never updates or deletes existing rows (except setting isKidsMeal=true on these same seeded ids);
 * - no nutrition or allergen data is written (none is invented).
 * Usage: npx tsx scripts/seed-kids-meals.ts [--env .env.render] [--dry-run]
 */
import { config } from 'dotenv';
import { PrismaClient } from '../src/generated/prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

const args = process.argv.slice(2);
const envIdx = args.indexOf('--env');
config({ path: envIdx >= 0 ? args[envIdx + 1] : '.env', override: true });
const dryRun = args.includes('--dry-run');
let url = (envIdx >= 0 ? process.env.RENDER_DATABASE_URL : undefined) ?? process.env.DATABASE_URL ?? '';
if (!url) throw new Error('DATABASE_URL missing');
const remote = !/localhost|127\.0\.0\.1/.test(url);
if (remote && !/sslmode=/.test(url)) url += (url.includes('?') ? '&' : '?') + 'sslmode=require';
const db = new PrismaClient({ adapter: new PrismaPg({ connectionString: url }) });

type Dish = { slug: string; name: string; description: string; pricePaise: number; categoryId: string; imageKey: string; veg: boolean };
const KIDS: Record<string, Dish[]> = {
  'woodstone-hitec': [
    { slug: 'mini-cheese-pizza', name: 'Mini Cheese Pizza', description: 'Kids portion: a 7-inch stone-baked pizza with tomato sauce and mozzarella. Mild, no chilli.', pricePaise: 14900, categoryId: 'pizza', imageKey: 'pizza', veg: true },
    { slug: 'kids-vegetable-pasta', name: 'Vegetable Pasta', description: 'Kids portion: small bowl of penne in a mild tomato sauce with soft vegetables. No chilli.', pricePaise: 13900, categoryId: 'pasta', imageKey: 'pasta', veg: true },
    { slug: 'mac-and-cheese', name: 'Mac and Cheese', description: 'Kids portion: macaroni in a creamy cheese sauce, baked until golden. Mild.', pricePaise: 12900, categoryId: 'pasta', imageKey: 'pasta', veg: true },
  ],
  'fd-smash-gachi': [
    { slug: 'mini-veg-burger', name: 'Mini Veg Burger', description: 'Kids portion: a small soft bun with a vegetable patty, lettuce and a little mayo. Mild.', pricePaise: 9900, categoryId: 'burgers', imageKey: 'burger', veg: true },
    { slug: 'mild-paneer-wrap', name: 'Mild Paneer Wrap', description: 'Kids portion: half-size wrap with soft paneer and vegetables in a mild, non-spicy sauce.', pricePaise: 11900, categoryId: 'paneer', imageKey: 'paneer', veg: true },
    { slug: 'kids-chocolate-milkshake', name: 'Chocolate Milkshake', description: 'Kids size (250 ml): chilled milk blended with chocolate.', pricePaise: 8900, categoryId: 'beverages', imageKey: 'cold-beverage', veg: true },
  ],
  'gachibowli-tiffin': [
    { slug: 'mini-idli-sambar', name: 'Mini Idli with Sambar', description: 'Kids portion: 8 bite-size idlis with mild sambar and coconut chutney.', pricePaise: 5900, categoryId: 'idli', imageKey: 'idli', veg: true },
    { slug: 'mini-dosa', name: 'Mini Dosa', description: 'Kids portion: two small plain dosas with mild coconut chutney. No chilli powder.', pricePaise: 6900, categoryId: 'dosa', imageKey: 'dosa', veg: true },
    { slug: 'mini-chapati-dal', name: 'Mini Chapati with Dal', description: 'Kids portion: two small chapatis with a mild yellow dal.', pricePaise: 7900, categoryId: 'meals', imageKey: 'meals', veg: true },
  ],
  'oven-crumb-kondapur': [
    { slug: 'kids-cheese-sandwich', name: 'Cheese Sandwich', description: 'Kids portion: toasted soft bread with melted cheese, cut into four.', pricePaise: 8900, categoryId: 'bakery', imageKey: 'bakery', veg: true },
    { slug: 'mini-pancakes', name: 'Mini Pancakes', description: 'Kids portion: five small fluffy pancakes with honey on the side.', pricePaise: 9900, categoryId: 'desserts', imageKey: 'dessert', veg: true },
    { slug: 'kids-banana-smoothie', name: 'Banana Smoothie', description: 'Kids size (250 ml): banana blended with chilled milk.', pricePaise: 7900, categoryId: 'beverages', imageKey: 'cold-beverage', veg: true },
  ],
  'botanical-bowl-madhapur': [
    { slug: 'kids-fruit-bowl', name: 'Fruit Bowl', description: 'Kids portion: a small bowl of fresh seasonal cut fruit.', pricePaise: 8900, categoryId: 'bowls', imageKey: 'salad', veg: true },
  ],
  'deccan-handi-gachi': [
    { slug: 'mild-chicken-rice-bowl', name: 'Mild Chicken Rice Bowl', description: 'Kids portion: soft rice with tender boneless chicken in a mild, non-spicy gravy.', pricePaise: 13900, categoryId: 'biryani', imageKey: 'chicken-biryani', veg: false },
    { slug: 'kids-mini-meal-combo', name: 'Kids Mini Meal Combo', description: 'Kids portion: mini vegetable pulao, a small bowl of mild dal and curd.', pricePaise: 14900, categoryId: 'meals', imageKey: 'meals', veg: true },
  ],
};

(async () => {
  console.log(`target: ${remote ? 'remote (hosted)' : 'local'} database${dryRun ? ' (dry run)' : ''}`);
  let created = 0, skipped = 0, sections = 0;
  for (const [restaurantId, dishes] of Object.entries(KIDS)) {
    const r = await db.restaurant.findUnique({ where: { id: restaurantId }, select: { id: true, name: true } });
    if (!r) { console.log(`! restaurant ${restaurantId} not found, skipping`); continue; }
    const sectionId = `${restaurantId}-kids-meals`;
    let section = await db.menuSection.findFirst({ where: { restaurantId, name: 'Kids Meals' } });
    if (!section) {
      sections++;
      if (!dryRun) section = await db.menuSection.create({ data: { id: sectionId, restaurantId, name: 'Kids Meals', displayOrder: -1 } });
    }
    for (const d of dishes) {
      const id = `kids-${restaurantId}-${d.slug}`;
      const clash = await db.menuItem.findFirst({ where: { OR: [{ id }, { restaurantId, name: d.name }] }, select: { id: true } });
      if (clash) {
        skipped++;
        if (clash.id === id && !dryRun) await db.menuItem.update({ where: { id }, data: { isKidsMeal: true } });
        console.log(`= ${r.name}: ${d.name} already present (${clash.id === id ? 'seeded earlier' : 'existing dish, left untouched'})`);
        continue;
      }
      created++;
      console.log(`+ ${r.name}: ${d.name} ₹${d.pricePaise / 100}`);
      if (!dryRun) await db.menuItem.create({ data: { id, restaurantId, sectionId: section?.id ?? sectionId, categoryId: d.categoryId, name: d.name, description: d.description, basePricePaise: d.pricePaise, imageKey: d.imageKey, isVegetarian: d.veg, isKidsMeal: true, displayOrder: 0 } });
    }
  }
  console.log(`sections created: ${sections}, dishes created: ${created}, already present: ${skipped}`);
  await db.$disconnect();
})().catch(async (e) => { console.error(e.message); await db.$disconnect(); process.exit(1); });
