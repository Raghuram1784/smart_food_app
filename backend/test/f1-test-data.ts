/** Test DB only: removes everything the F1 seeds add, so other suites keep their exact base fixtures. */
export async function removeF1TestData(db: any) {
  const url = process.env.DATABASE_URL ?? '';
  if (new URL(url).pathname !== '/food_delivery_test') throw new Error('F1 cleanup runs on the isolated test database only');
  const { OUTLETS } = require('../dist/prisma/seed_outlets');
  const { FAMILY_SOURCE } = require('../dist/prisma/nutrition_reference');
  const outletIds: string[] = OUTLETS.map((o: any[]) => o[0]);
  const items = (await db.menuItem.findMany({ where: { OR: [{ id: { startsWith: 'f1-' } }, { restaurantId: { in: outletIds } }] }, select: { id: true } })).map((r: any) => r.id);
  await db.cartItem.deleteMany({ where: { menuItemId: { in: items } } });
  await db.menuItemNutrition.deleteMany({ where: { OR: [{ menuItemId: { in: items } }, { source: FAMILY_SOURCE }] } });
  await db.menuItemVariant.deleteMany({ where: { menuItemId: { in: items }, cartItems: { none: {} } } });
  await db.menuItemAddOn.deleteMany({ where: { menuItemId: { in: items } } });
  await db.menuItemProfile.deleteMany({});
  await db.menuItem.deleteMany({ where: { id: { in: items }, orderItems: { none: {} } } });
  const removable = (await db.restaurant.findMany({ where: { id: { in: outletIds }, orders: { none: {} } }, select: { id: true } })).map((r: any) => r.id);
  await db.cart.updateMany({ where: { restaurantId: { in: removable } }, data: { restaurantId: null } });
  await db.restaurantDeliveryZone.deleteMany({ where: { restaurantId: { in: removable } } });
  await db.restaurantCuisine.deleteMany({ where: { restaurantId: { in: removable } } });
  await db.restaurantMembership.deleteMany({ where: { restaurantId: { in: removable } } });
  await db.menuSection.deleteMany({ where: { restaurantId: { in: removable } } });
  await db.restaurant.deleteMany({ where: { id: { in: removable } } });
  await db.restaurant.updateMany({ where: { brandId: { not: null } }, data: { brandId: null } });
  await db.restaurantBrand.deleteMany({ where: { outlets: { none: {} } } });
}
