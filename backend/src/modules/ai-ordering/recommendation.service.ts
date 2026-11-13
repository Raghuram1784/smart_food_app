
import {
  BadRequestException,
  Inject,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
import { DatabaseService } from '../../database/database.module';
import { PricingService } from '../pricing/pricing.service';
import { itemInclude } from '../catalog/catalog.mapper';
import {
  FoodIntent,
  normalizeFoodIntent,
} from './food-intent';

@Injectable()
export class RecommendationService {
  constructor(
    @Inject(DatabaseService)
    private readonly db: DatabaseService,
    @Inject(PricingService)
    private readonly pricing: PricingService,
  ) {}

  async recommend(rawIntent: unknown, areaId: string) {
    let intent: FoodIntent;

    try {
      intent = normalizeFoodIntent(rawIntent);
    } catch {
      throw new BadRequestException('Invalid food-ordering intent');
    }

    if (!intent.dishQuery || !intent.quantity) {
      throw new UnprocessableEntityException(
        'Please specify a dish and quantity',
      );
    }

    // First-pass normalization of common plural dish names.
    const term = intent.dishQuery
      .trim()
      .toLowerCase()
      .replace(/\s+/g, ' ')
      .replace(/\bpizzas\b/g, 'pizza')
      .replace(/\bburgers\b/g, 'burger')
      .replace(/\bdosas\b/g, 'dosa');

    return this.db.client.$transaction(async tx => {
      const now = new Date();

      const area = await this.pricing.validateArea(
        tx,
        areaId,
      );

      const where: Prisma.MenuItemWhereInput = {
        availabilityStatus: 'AVAILABLE',
        category: { isActive: true },

        ...(intent.vegetarian !== null
          ? { isVegetarian: intent.vegetarian }
          : {}),

        OR: [
          { name: { contains: term, mode: 'insensitive' } },
          {
            category: {
              name: { contains: term, mode: 'insensitive' },
            },
          },
        ],

        restaurant: {
          operatingStatus: 'OPEN',
          deliveryAvailability: true,

          ...(intent.minRating !== null
            ? { rating: { gte: intent.minRating } }
            : {}),

          zones: {
            some: {
              zoneId: areaId,
              isEligible: true,
              zone: { isActive: true },
            },
          },
        },

        AND: [{
          OR: [
            { variants: { none: {} } },
            { variants: { some: { isAvailable: true } } },
          ],
        }],
      };

      const items = await tx.menuItem.findMany({
        where,
        include: itemInclude,
        take: 501,
        orderBy: { id: 'asc' },
      });

      if (items.length > 500) {
        throw new UnprocessableEntityException(
          'Please narrow your dish search',
        );
      }

      const rules = await this.pricing.rules(
        tx,
        areaId,
        now,
      );

      const candidates = items.map(item => {
        // Existing authoritative pricing code.
        // Quantity is applied before checking the budget.
        const quote = this.pricing.price(
          item,
          {
            restaurantId: item.restaurantId,
            menuItemId: item.id,
            area: areaId,
            quantity: intent.quantity!,
            addOnIds: [],
          },
          rules,
          now,
          area.name,
        );

        return {
          menuItemId: item.id,
          dishName: item.name,
          restaurantId: item.restaurantId,
          restaurantName: item.restaurant.name,
          vegetarian: item.isVegetarian,
          rating: Number(item.restaurant.rating),
          quantity: intent.quantity,
          estimatedMinutes: quote.estimatedMinutes,
          subtotalPaise: quote.subtotalPaise,
          finalPayablePaise: quote.finalPayablePaise,
          packagingPaise: quote.packagingPaise,
          deliveryPaise: quote.deliveryPaise,
          platformPaise: quote.platformPaise,
          taxPaise: quote.taxPaise,
          quoteExpiresAt: quote.expiresAt,
        };
      });

      const withinTime = candidates.filter(c =>
        intent.maxDeliveryMinutes === null ||
        c.estimatedMinutes <= intent.maxDeliveryMinutes
      );

      const matches = withinTime
        .filter(c =>
          intent.maxPayablePaise === null ||
          c.finalPayablePaise <= intent.maxPayablePaise
        )
        .sort((a, b) =>
          a.finalPayablePaise - b.finalPayablePaise ||
          a.estimatedMinutes - b.estimatedMinutes ||
          b.rating - a.rating
        );

      // A near miss is information, not a valid recommendation.
      const closestOverBudget =
        matches.length === 0 &&
        intent.maxPayablePaise !== null
          ? withinTime
              .filter(c =>
                c.finalPayablePaise > intent.maxPayablePaise!
              )
              .sort((a, b) =>
                a.finalPayablePaise - b.finalPayablePaise
              )[0] ?? null
          : null;

      return {
        intent,
        area: { id: area.id, name: area.name },
        matches: matches.slice(0, 5),
        totalMatches: matches.length,
        closestOverBudget,
        message: matches.length
          ? 'Matching options found'
          : 'No available option satisfies all constraints',
        notice:
          'Illustrative catalog, ratings and delivery estimates. ' +
          'Prices must be re-quoted before checkout.',
      };
    }, { isolationLevel: 'RepeatableRead' });
  }
}
