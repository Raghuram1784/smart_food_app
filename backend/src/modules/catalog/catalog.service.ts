import { wordsWhere } from './smart-search.service';
import { Injectable, Inject, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../database/database.module';
import { CatalogQuery } from '../../common/dto/catalog-query.dto';
import { Prisma } from '../../generated/prisma/client';

import { restaurantInclude, itemInclude, restaurantDto, itemDto } from './catalog.mapper';

@Injectable()
export class CatalogService {
  constructor(@Inject(DatabaseService) private readonly database: DatabaseService) {}

  private get db() {
    return this.database.client;
  }

  async areas() {
    const [localities, eligibleRows] = await this.db.$transaction([
      this.db.locality.findMany({
        where: { isActive: true },
        orderBy: [{ displayOrder: 'asc' }, { id: 'asc' }],
      }),
      this.db.restaurantDeliveryZone.findMany({
        where: {
          isEligible: true,
          restaurant: { operatingStatus: 'OPEN' },
        },
        select: { zoneId: true },
      }),
    ]);
    const counts = new Map<string, number>();
    for (const row of eligibleRows) {
      counts.set(row.zoneId, (counts.get(row.zoneId) ?? 0) + 1);
    }
    return localities.map((l) => ({
      ...l,
      serviceableRestaurantCount: counts.get(l.id) ?? 0,
    }));
  }

  async categories() {
    return this.db.category.findMany({
      where: { isActive: true },
      orderBy: [{ displayOrder: 'asc' }, { id: 'asc' }],
    });
  }

  async cuisines() {
    return this.db.cuisine.findMany({ orderBy: { name: 'asc' } });
  }

  async restaurants(q: CatalogQuery) {
    const where: Prisma.RestaurantWhereInput = {
      ...(q.cuisine ? { cuisines: { some: { cuisineId: q.cuisine } } } : {}),
      ...(q.category ? { items: { some: { categoryId: q.category } } } : {}),
      ...(q.q ? { name: { contains: q.q, mode: 'insensitive' } } : {}),
      ...(q.area ? { zones: { some: { zoneId: q.area, isEligible: true } } } : {}),
    };
    const [rows, total] = await this.db.$transaction([
      this.db.restaurant.findMany({
        where,
        include: restaurantInclude,
        skip: (q.page - 1) * q.limit,
        take: q.limit,
        orderBy: [{ displayOrder: 'asc' }, { id: 'asc' }],
      }),
      this.db.restaurant.count({ where }),
    ]);
    return { items: rows.map(restaurantDto), page: q.page, limit: q.limit, total };
  }

  async restaurant(id: string) {
    const r = await this.db.restaurant.findUnique({
      where: { id },
      include: restaurantInclude,
    });
    if (!r) throw new NotFoundException('Restaurant not found');
    return restaurantDto(r);
  }

  async menu(id: string) {
    const restaurant = await this.restaurant(id);
    const sections = await this.db.menuSection.findMany({
      where: { restaurantId: id },
      orderBy: [{ displayOrder: 'asc' }, { id: 'asc' }],
      include: {
        items: {
          orderBy: [{ displayOrder: 'asc' }, { id: 'asc' }],
          include: itemInclude,
        },
      },
    });
    return {
      restaurant,
      sections: sections.map((s) => ({ ...s, items: s.items.map(itemDto) })),
    };
  }

  async item(id: string) {
    const d = await this.db.menuItem.findUnique({
      where: { id },
      include: itemInclude,
    });
    if (!d) throw new NotFoundException('Menu item not found');
    return itemDto(d);
  }

  async search(q: CatalogQuery) {
    const words = (q.q ?? '').trim().toLowerCase().split(/\s+/).filter(Boolean);
    const restaurantFilter: Prisma.RestaurantWhereInput = {
      ...(q.cuisine ? { cuisines: { some: { cuisineId: q.cuisine } } } : {}),
      ...(q.area ? { zones: { some: { zoneId: q.area, isEligible: true } } } : {}),
    };
    const where: Prisma.MenuItemWhereInput = {
      ...(q.category ? { categoryId: q.category } : {}),
      ...(q.maxPricePaise !== undefined ? { basePricePaise: { lte: q.maxPricePaise } } : {}),
      ...(Object.keys(restaurantFilter).length > 0 ? { restaurant: restaurantFilter } : {}),
      AND: wordsWhere(words),
    };
    const [items, total] = await this.db.$transaction([
      this.db.menuItem.findMany({
        where,
        include: itemInclude,
        skip: (q.page - 1) * q.limit,
        take: q.limit,
        orderBy: [{ displayOrder: 'asc' }, { id: 'asc' }],
      }),
      this.db.menuItem.count({ where }),
    ]);
    return { items: items.map(itemDto), total, page: q.page, limit: q.limit };
  }
}
