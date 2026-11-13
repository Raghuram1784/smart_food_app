import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import { AvailabilityStatus, OperatingStatus } from '../src/generated/prisma/client';
import { seed, slug } from './seed';
import localitiesData from './localities.json';
import catalogData from './catalog_hyd.json';

interface LocalityRecord {
  id: string;
  name: string;
  city: string;
  displayOrder: number;
}

interface ExistingZoneConfig {
  restaurantId?: string;
  id?: string;
  localityId: string;
  address?: string;
  serviceAreas: string[];
}

interface CategoryRecord {
  id: string;
  name: string;
  imageKey: string;
  displayOrder?: number;
}

interface AddOnRecord {
  name: string;
  pricePaise: number;
}

interface RestaurantRecord {
  id: string;
  name: string;
  localityId: string;
  address?: string;
  cuisineDescription: string;
  description: string;
  imageKey: string;
  rating: number;
  deliveryTime?: string;
  estimatedDeliveryMinutes?: number;
  estimatedDeliveryMaxMinutes?: number;
  cuisines: string[];
  operatingStatus?: 'OPEN' | 'CLOSED' | 'PAUSED';
  serviceAreas?: string[];
  displayOrder?: number;
}

interface DishVariantRecord {
  name: string;
  priceAdjustmentPaise: number;
  isAvailable?: boolean;
}

interface DishRecord {
  id: string;
  restaurantId: string;
  name: string;
  description: string;
  categoryId: string;
  imageKey: string;
  pricePaise?: number;
  basePricePaise?: number;
  section: string;
  isVegetarian: boolean;
  availabilityStatus?: 'AVAILABLE' | 'SOLD_OUT' | 'UNAVAILABLE';
  availabilityReason?: string | null;
  variants?: DishVariantRecord[];
  addOnNames?: string[];
}

interface HyderabadCatalog {
  categories: CategoryRecord[];
  existingRestaurantZones?: Record<string, ExistingZoneConfig> | ExistingZoneConfig[];
  addOns?: AddOnRecord[];
  restaurants: RestaurantRecord[];
  dishes: DishRecord[];
}

const LEGACY_BENGALURU_ZONES = ['indiranagar', 'koramangala', 'whitefield'];
const LEGACY_DISH_IDS = new Set(['dosa', 'idli', 'biryani', 'paneer', 'pizza', 'pasta', 'salad', 'burger']);

function parseDeliveryWindow(r: RestaurantRecord): [number, number] {
  if (
    typeof r.estimatedDeliveryMinutes === 'number' &&
    typeof r.estimatedDeliveryMaxMinutes === 'number'
  ) {
    return [r.estimatedDeliveryMinutes, r.estimatedDeliveryMaxMinutes];
  }
  const nums = (r.deliveryTime ?? '25-35').match(/\d+/g)?.map(Number) ?? [25, 35];
  const min = nums[0] ?? 25;
  const max = nums[1] ?? min + 10;
  return [min, Math.max(min, max)];
}

export async function seedHyd(db: ReturnType<typeof createDatabase>) {
  // Ensure base 4 restaurants and 8 original dishes exist when run on an empty DB.
  if ((await db.restaurant.findUnique({ where: { id: 'tiffin' } })) === null) {
    await seed(db);
  }

  const localities = (localitiesData as { localities: LocalityRecord[] }).localities;
  const localityById = new Map(localities.map((l) => [l.id, l]));
  const catalog = catalogData as unknown as HyderabadCatalog;

  await db.$transaction(
    async (tx) => {
      // 1. Upsert all 10 Hyderabad localities and matching delivery zones.
      for (const loc of localities) {
        await tx.locality.upsert({
          where: { id: loc.id },
          update: {
            name: loc.name,
            city: loc.city,
            displayOrder: loc.displayOrder,
            isActive: true,
          },
          create: {
            id: loc.id,
            name: loc.name,
            city: loc.city,
            displayOrder: loc.displayOrder,
            isActive: true,
          },
        });

        await tx.deliveryZone.upsert({
          where: { id: loc.id },
          update: {
            name: `${loc.name}, ${loc.city}`,
            isIllustrative: true,
            isActive: true,
          },
          create: {
            id: loc.id,
            name: `${loc.name}, ${loc.city}`,
            isIllustrative: true,
            isActive: true,
          },
        });
      }

      // 2. Deactivate legacy Bengaluru zones without deleting historical references.
      await tx.deliveryZone.updateMany({
        where: { id: { in: LEGACY_BENGALURU_ZONES } },
        data: { isActive: false },
      });

      // 3. Upsert all 16 categories (preserving existing 8 IDs while updating Hyderabad metadata).
      for (const [index, cat] of catalog.categories.entries()) {
        const displayOrder = cat.displayOrder ?? index;
        await tx.category.upsert({
          where: { id: cat.id },
          update: {
            name: cat.name,
            imageKey: cat.imageKey,
            displayOrder,
            isActive: true,
          },
          create: {
            id: cat.id,
            name: cat.name,
            slug: cat.id,
            imageKey: cat.imageKey,
            displayOrder,
            isActive: true,
          },
        });
      }

      // 4. Upsert global add-ons by name.
      const addOnIdByName = new Map<string, string>();
      for (const addOn of catalog.addOns ?? []) {
        const existing = await tx.addOn.findFirst({ where: { name: addOn.name } });
        if (existing) {
          const updated = await tx.addOn.update({
            where: { id: existing.id },
            data: { pricePaise: addOn.pricePaise, isAvailable: true },
          });
          addOnIdByName.set(updated.name, updated.id);
        } else {
          const created = await tx.addOn.create({
            data: { name: addOn.name, pricePaise: addOn.pricePaise, isAvailable: true },
          });
          addOnIdByName.set(created.name, created.id);
        }
      }

      // Helper to configure eligible service areas for a restaurant.
      const syncServiceAreas = async (
        restaurantId: string,
        ownLocalityId: string,
        baseMinutes: number,
        serviceAreas: string[],
      ) => {
        const areas = Array.from(new Set(serviceAreas.length > 0 ? serviceAreas : [ownLocalityId]));
        for (const [idx, zoneId] of areas.entries()) {
          const estimatedMinutes =
            zoneId === ownLocalityId ? Math.max(15, baseMinutes) : Math.max(20, baseMinutes + 5 + idx * 3);
          await tx.restaurantDeliveryZone.upsert({
            where: { restaurantId_zoneId: { restaurantId, zoneId } },
            update: { isEligible: true, estimatedMinutes },
            create: { restaurantId, zoneId, isEligible: true, estimatedMinutes },
          });
        }
        await tx.restaurantDeliveryZone.updateMany({
          where: { restaurantId, zoneId: { notIn: areas } },
          data: { isEligible: false },
        });
      };

      // 5. Update the 4 existing restaurants with Hyderabad localities and serviceable zones.
      const rawExisting = catalog.existingRestaurantZones;
      const existingEntries: Array<[string, ExistingZoneConfig]> = rawExisting
        ? Array.isArray(rawExisting)
          ? rawExisting.map((item) => [(item.restaurantId ?? item.id)!, item])
          : Object.entries(rawExisting)
        : [
            ['tiffin', { localityId: 'madhapur', serviceAreas: ['madhapur', 'hitec-city', 'gachibowli', 'kondapur', 'jubilee-hills'] }],
            ['hearth', { localityId: 'jubilee-hills', serviceAreas: ['jubilee-hills', 'madhapur', 'banjara-hills', 'hitec-city'] }],
            ['table', { localityId: 'banjara-hills', serviceAreas: ['banjara-hills', 'jubilee-hills', 'madhapur', 'ameerpet'] }],
            ['bun', { localityId: 'gachibowli', serviceAreas: ['gachibowli', 'hitec-city', 'kondapur', 'madhapur'] }],
          ];

      for (const [restaurantId, cfg] of existingEntries) {
        if (!restaurantId) continue;
        const existing = await tx.restaurant.findUnique({ where: { id: restaurantId } });
        if (!existing) continue;
        const locName = localityById.get(cfg.localityId)?.name ?? cfg.localityId;
        await tx.restaurant.update({
          where: { id: restaurantId },
          data: {
            localityId: cfg.localityId,
            address: cfg.address ?? `${locName}, Hyderabad (Demo)`,
            deliveryAvailability: true,
          },
        });
        await syncServiceAreas(
          restaurantId,
          cfg.localityId,
          existing.estimatedDeliveryMinutes,
          cfg.serviceAreas,
        );
      }

      // 6. Upsert all new Hyderabad restaurants, cuisines, and serviceable delivery zones.
      for (const [index, r] of catalog.restaurants.entries()) {
        const [minMin, maxMin] = parseDeliveryWindow(r);
        const locName = localityById.get(r.localityId)?.name ?? r.localityId;
        const address = r.address ?? `${locName}, Hyderabad (Demo)`;
        const operatingStatus = (r.operatingStatus as OperatingStatus | undefined) ?? OperatingStatus.OPEN;
        const displayOrder = r.displayOrder ?? 10 + index;

        await tx.restaurant.upsert({
          where: { id: r.id },
          update: {
            name: r.name,
            description: r.description,
            address,
            rating: r.rating,
            estimatedDeliveryMinutes: minMin,
            estimatedDeliveryMaxMinutes: maxMin,
            deliveryAvailability: true,
            imageKey: r.imageKey,
            cuisineDescription: r.cuisineDescription,
            operatingStatus,
            localityId: r.localityId,
            displayOrder,
            isDemo: true,
          },
          create: {
            id: r.id,
            name: r.name,
            slug: slug(`${r.name}-${r.id}`),
            description: r.description,
            address,
            rating: r.rating,
            estimatedDeliveryMinutes: minMin,
            estimatedDeliveryMaxMinutes: maxMin,
            deliveryAvailability: true,
            imageKey: r.imageKey,
            cuisineDescription: r.cuisineDescription,
            operatingStatus,
            localityId: r.localityId,
            displayOrder,
            isDemo: true,
          },
        });

        for (const cuisineName of r.cuisines) {
          const cuisineId = slug(cuisineName);
          await tx.cuisine.upsert({
            where: { id: cuisineId },
            update: {},
            create: { id: cuisineId, name: cuisineName, slug: cuisineId },
          });
          await tx.restaurantCuisine.upsert({
            where: { restaurantId_cuisineId: { restaurantId: r.id, cuisineId } },
            update: {},
            create: { restaurantId: r.id, cuisineId },
          });
        }

        await syncServiceAreas(
          r.id,
          r.localityId,
          minMin,
          r.serviceAreas ?? [r.localityId],
        );
      }

      // 7. Upsert menu sections, dishes, variants, and add-on mappings.
      const sectionOrderByRestaurant = new Map<string, Map<string, number>>();
      for (const [index, dish] of catalog.dishes.entries()) {
        if (LEGACY_DISH_IDS.has(dish.id)) continue;

        let sectionsMap = sectionOrderByRestaurant.get(dish.restaurantId);
        if (!sectionsMap) {
          sectionsMap = new Map<string, number>();
          sectionOrderByRestaurant.set(dish.restaurantId, sectionsMap);
        }
        if (!sectionsMap.has(dish.section)) {
          sectionsMap.set(dish.section, sectionsMap.size);
        }
        const sectionOrder = sectionsMap.get(dish.section)!;
        const sectionId = `${dish.restaurantId}-${slug(dish.section)}`;

        await tx.menuSection.upsert({
          where: { id: sectionId },
          update: { name: dish.section, displayOrder: sectionOrder },
          create: {
            id: sectionId,
            restaurantId: dish.restaurantId,
            name: dish.section,
            displayOrder: sectionOrder,
          },
        });

        const basePricePaise = dish.basePricePaise ?? dish.pricePaise ?? 0;
        const availabilityStatus =
          (dish.availabilityStatus as AvailabilityStatus | undefined) ?? AvailabilityStatus.AVAILABLE;
        const availabilityReason = dish.availabilityReason ?? null;

        await tx.menuItem.upsert({
          where: { id: dish.id },
          update: {
            restaurantId: dish.restaurantId,
            categoryId: dish.categoryId,
            sectionId,
            name: dish.name,
            description: dish.description,
            basePricePaise,
            imageKey: dish.imageKey,
            isVegetarian: dish.isVegetarian,
            availabilityStatus,
            availabilityReason,
            displayOrder: 20 + index,
          },
          create: {
            id: dish.id,
            restaurantId: dish.restaurantId,
            categoryId: dish.categoryId,
            sectionId,
            name: dish.name,
            description: dish.description,
            basePricePaise,
            imageKey: dish.imageKey,
            isVegetarian: dish.isVegetarian,
            availabilityStatus,
            availabilityReason,
            displayOrder: 20 + index,
          },
        });

        for (const variant of dish.variants ?? []) {
          await tx.menuItemVariant.upsert({
            where: { menuItemId_name: { menuItemId: dish.id, name: variant.name } },
            update: {
              priceAdjustmentPaise: variant.priceAdjustmentPaise,
              isAvailable: variant.isAvailable ?? true,
            },
            create: {
              menuItemId: dish.id,
              name: variant.name,
              priceAdjustmentPaise: variant.priceAdjustmentPaise,
              isAvailable: variant.isAvailable ?? true,
            },
          });
        }

        for (const addOnName of dish.addOnNames ?? []) {
          let addOnId = addOnIdByName.get(addOnName);
          if (!addOnId) {
            const existingAddOn = await tx.addOn.findFirst({ where: { name: addOnName } });
            if (existingAddOn) {
              addOnId = existingAddOn.id;
            } else {
              const createdAddOn = await tx.addOn.create({
                data: { name: addOnName, pricePaise: 3000, isAvailable: true },
              });
              addOnId = createdAddOn.id;
            }
            addOnIdByName.set(addOnName, addOnId);
          }

          await tx.menuItemAddOn.upsert({
            where: { menuItemId_addOnId: { menuItemId: dish.id, addOnId } },
            update: {},
            create: { menuItemId: dish.id, addOnId },
          });
        }
      }
    },
    { maxWait: 10000, timeout: 60000 },
  );
}

if (require.main === module) {
  const db = createDatabase(process.env.DATABASE_URL!);
  seedHyd(db)
    .then(async () => {
      console.log(
        JSON.stringify({
          seed: 'hyd_confirmed',
          localities: await db.locality.count(),
          restaurants: await db.restaurant.count(),
          menuItems: await db.menuItem.count(),
          categories: await db.category.count(),
          cuisines: await db.cuisine.count(),
          variants: await db.menuItemVariant.count(),
          addOns: await db.addOn.count(),
        }),
      );
    })
    .catch((err) => {
      console.error('Hyderabad seed failed:', err?.message ?? err);
      process.exitCode = 1;
    })
    .finally(() => db.$disconnect());
}
