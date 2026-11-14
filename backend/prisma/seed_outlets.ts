/**
 * Brand outlets for locality coverage (synthetic development data, not real businesses).
 *
 *   npx tsx prisma/seed_outlets.ts
 *
 * - Every restaurant gets a RestaurantBrand (brand id = slug of its name).
 * - New outlets are separate Restaurant rows of an existing brand: own id, locality, display
 *   address, menu copy (own item ids), delivery zone, owner membership and therefore own orders.
 * - No GPS coordinates are invented (latitude/longitude stay null; serviceability uses zones).
 * - Create-only and idempotent: existing rows are never modified or deleted; re-running only
 *   adds menu items that the flagship gained since the last run.
 */
import 'dotenv/config';
import { createHash } from 'node:crypto';
import { createDatabase } from '../src/database/client';

const slug = (s: string) => s.toLowerCase().replace(/&/g, 'and').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

/** [outletId, flagship restaurant id, locality/zone id, display address] */
// prettier-ignore
export const OUTLETS: [string, string, string, string][] = [
  ['deccan-handi-kphb', 'deccan-handi-gachi', 'kukatpally', 'KPHB Colony, Road No. 1, Kukatpally, Hyderabad (Demo outlet)'],
  ['pind-handi-kphb', 'pind-handi-madhapur', 'kukatpally', 'Near KPHB Metro, Kukatpally, Hyderabad (Demo outlet)'],
  ['cyberabad-wok-kphb', 'cyberabad-wok-madhapur', 'kukatpally', 'JNTU Road, Kukatpally, Hyderabad (Demo outlet)'],
  ['tiffin-mehdi', 'tiffin', 'mehdipatnam', 'Rethibowli, Mehdipatnam, Hyderabad (Demo outlet)'],
  ['kaveri-veg-biryani-mehdi', 'kaveri-veg-biryani-kuka', 'mehdipatnam', 'Mehdipatnam Main Road, Hyderabad (Demo outlet)'],
  ['crunch-box-mehdi', 'crunch-box-kuka', 'mehdipatnam', 'Gudimalkapur, Mehdipatnam, Hyderabad (Demo outlet)'],
  ['deccan-handi-secund', 'deccan-handi-gachi', 'secunderabad', 'SD Road, Secunderabad, Hyderabad (Demo outlet)'],
  ['cyberabad-wok-secund', 'cyberabad-wok-madhapur', 'secunderabad', 'Paradise Circle, Secunderabad, Hyderabad (Demo outlet)'],
  ['botanical-bowl-secund', 'botanical-bowl-madhapur', 'secunderabad', 'Marredpally, Secunderabad, Hyderabad (Demo outlet)'],
  ['charcoal-secund', 'charcoal-hitec', 'secunderabad', 'Trimulgherry, Secunderabad, Hyderabad (Demo outlet)'],
];

export const outletItemId = (outletId: string, flagshipItemId: string) =>
  `o-${outletId}-${createHash('sha1').update(flagshipItemId).digest('hex').slice(0, 10)}`;

export async function seedOutlets(db: ReturnType<typeof createDatabase>) {
  let brands = 0, outlets = 0, items = 0, memberships = 0;
  await db.$transaction(async (tx) => {
    // 1. Brands for every restaurant (outlets share their flagship's brand).
    for (const r of await tx.restaurant.findMany({ where: { brandId: null }, select: { id: true, name: true } })) {
      const id = slug(r.name).slice(0, 64);
      if (!(await tx.restaurantBrand.findUnique({ where: { id } }))) { await tx.restaurantBrand.create({ data: { id, name: r.name } }); brands++; }
      await tx.restaurant.update({ where: { id: r.id }, data: { brandId: id } });
    }
    for (const [outletId, flagshipId, zoneId, address] of OUTLETS) {
      const flag = await tx.restaurant.findUnique({ where: { id: flagshipId }, include: { cuisines: true, memberships: { where: { status: 'ACTIVE', membershipRole: 'OWNER' } } } });
      const zone = await tx.deliveryZone.findUnique({ where: { id: zoneId } });
      const locality = await tx.locality.findUnique({ where: { id: zoneId } });
      if (!flag || !zone || !locality) continue; // never create orphans
      // 2. Outlet row.
      if (!(await tx.restaurant.findUnique({ where: { id: outletId } }))) {
        await tx.restaurant.create({ data: {
          id: outletId, name: flag.name, slug: `${flag.slug}-${zoneId}`.slice(0, 160), description: flag.description, address,
          rating: flag.rating, reviewCount: null, estimatedDeliveryMinutes: flag.estimatedDeliveryMinutes, estimatedDeliveryMaxMinutes: flag.estimatedDeliveryMaxMinutes,
          deliveryAvailability: true, imageKey: flag.imageKey, cuisineDescription: flag.cuisineDescription, operatingStatus: 'OPEN', isDemo: true,
          displayOrder: flag.displayOrder + 100, localityId: zoneId, brandId: flag.brandId,
        } });
        for (const c of flag.cuisines) await tx.restaurantCuisine.create({ data: { restaurantId: outletId, cuisineId: c.cuisineId } });
        outlets++;
      }
      // 3. Delivery zone: its own locality.
      const z = await tx.restaurantDeliveryZone.findUnique({ where: { restaurantId_zoneId: { restaurantId: outletId, zoneId } } });
      if (!z) await tx.restaurantDeliveryZone.create({ data: { restaurantId: outletId, zoneId, isEligible: true, estimatedMinutes: flag.estimatedDeliveryMinutes } });
      // 4. Owner: the brand's existing owner(s) also own this outlet (orders stay per outlet).
      for (const m of flag.memberships) {
        const has = await tx.restaurantMembership.findUnique({ where: { userId_restaurantId: { userId: m.userId, restaurantId: outletId } } });
        if (!has) { await tx.restaurantMembership.create({ data: { userId: m.userId, restaurantId: outletId, membershipRole: 'OWNER', status: 'ACTIVE' } }); memberships++; }
      }
      // 5. Menu copy (sections, items, variants, add-on links, nutrition, profile).
      const sections = await tx.menuSection.findMany({ where: { restaurantId: flagshipId } });
      const sectionMap = new Map<string, string>();
      for (const s of sections) {
        let own = await tx.menuSection.findFirst({ where: { restaurantId: outletId, name: s.name } });
        if (!own) own = await tx.menuSection.create({ data: { id: `${outletId}-${slug(s.name)}`.slice(0, 100), restaurantId: outletId, name: s.name, displayOrder: s.displayOrder } });
        sectionMap.set(s.id, own.id);
      }
      const menu = await tx.menuItem.findMany({ where: { restaurantId: flagshipId }, include: { variants: true, addOns: true, nutrition: true, profile: true } });
      for (const it of menu) {
        const id = outletItemId(outletId, it.id);
        if (await tx.menuItem.findUnique({ where: { id }, select: { id: true } })) continue;
        await tx.menuItem.create({ data: {
          id, restaurantId: outletId, categoryId: it.categoryId, sectionId: sectionMap.get(it.sectionId)!, name: it.name, description: it.description,
          basePricePaise: it.basePricePaise, imageKey: it.imageKey, isVegetarian: it.isVegetarian, availabilityStatus: it.availabilityStatus,
          availabilityReason: it.availabilityReason, displayOrder: it.displayOrder,
        } });
        for (const v of it.variants) await tx.menuItemVariant.create({ data: { menuItemId: id, name: v.name, priceAdjustmentPaise: v.priceAdjustmentPaise, isAvailable: v.isAvailable } });
        for (const a of it.addOns) await tx.menuItemAddOn.create({ data: { menuItemId: id, addOnId: a.addOnId } });
        if (it.nutrition) {
          const { menuItemId: _m, createdAt: _c, updatedAt: _u, ...n } = it.nutrition;
          await tx.menuItemNutrition.create({ data: { ...n, menuItemId: id } });
        }
        if (it.profile) {
          const { menuItemId: _m, createdAt: _c, updatedAt: _u, ...pr } = it.profile;
          await tx.menuItemProfile.create({ data: { ...pr, menuItemId: id } });
        }
        items++;
      }
    }
  }, { timeout: 180000 });
  return { brands, outlets, items, memberships };
}

if (require.main === module) {
  const url = process.env.DATABASE_URL!;
  const db = createDatabase(url);
  seedOutlets(db)
    .then((r) => console.log(JSON.stringify({ event: 'outlets_seeded', database: new URL(url).pathname.slice(1), ...r })))
    .catch((e) => { console.error(e instanceof Error ? e.message : e); process.exitCode = 1; })
    .finally(() => db.$disconnect());
}
