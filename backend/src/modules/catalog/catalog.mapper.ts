import { Prisma } from '../../generated/prisma/client';
export const restaurantInclude = {
  cuisines: { include: { cuisine: true } },
  items: {
    select: { basePricePaise: true },
    orderBy: { basePricePaise: 'asc' as const },
    take: 1,
  },
  locality: true,
  zones: {
    where: { isEligible: true },
    include: { zone: true },
    orderBy: [{ estimatedMinutes: 'asc' as const }, { zoneId: 'asc' as const }],
  },
};

export const itemInclude = {
  category: true,
  section: true,
  restaurant: { include: restaurantInclude },
  variants: { orderBy: [{ priceAdjustmentPaise: 'asc' as const }, { name: 'asc' as const }] },
  addOns: {
    include: { addOn: true },
    orderBy: { addOn: { pricePaise: 'asc' as const } },
  },
};

export function restaurantDto(r: Prisma.RestaurantGetPayload<{include: typeof restaurantInclude}>) {
  return {
    ...r,
    rating: Number(r.rating),
    latitude: r.latitude === null ? null : Number(r.latitude),
    longitude: r.longitude === null ? null : Number(r.longitude),
    cuisines: r.cuisines.map((x) => ({ id: x.cuisine.id, name: x.cuisine.name })),
    startingPricePaise: r.items?.[0]?.basePricePaise ?? null,
    locality: r.locality ? { id: r.locality.id, name: r.locality.name, city: r.locality.city } : null,
    serviceAreas: (r.zones ?? []).map((z) => ({
      id: z.zone.id,
      name: z.zone.name,
      estimatedMinutes: z.estimatedMinutes,
    })),
    items: undefined,
    zones: undefined,
  };
}

export function itemDto(d: Prisma.MenuItemGetPayload<{include: typeof itemInclude}>) {
  return {
    ...d,
    restaurant: restaurantDto(d.restaurant),
    addOns: d.addOns.map((x) => x.addOn),
  };
}

