import { Inject, Injectable, UnprocessableEntityException } from '@nestjs/common';
import { DatabaseService } from '../../database/database.module';
import { Prisma } from '../../generated/prisma/client';
import { PricingService } from '../pricing/pricing.service';
import { itemInclude } from './catalog.mapper';
import { SmartQuery } from './smart-query.dto';

export function wordsWhere(words: string[]): Prisma.MenuItemWhereInput[] {
  return words.map(word => ({ OR: [
    { name: { contains: word, mode: 'insensitive' } },
    { description: { contains: word, mode: 'insensitive' } },
    { category: { name: { contains: word, mode: 'insensitive' } } },
    { restaurant: { name: { contains: word, mode: 'insensitive' } } },
    { restaurant: { cuisineDescription: { contains: word, mode: 'insensitive' } } },
    { restaurant: { locality: { name: { contains: word, mode: 'insensitive' } } } },
    { restaurant: { cuisines: { some: { cuisine: { name: { contains: word, mode: 'insensitive' } } } } } },
  ] }));
}

@Injectable()
export class SmartSearchService {
  constructor(@Inject(DatabaseService) private readonly database: DatabaseService,
    @Inject(PricingService) private readonly pricing: PricingService) {}

  async search(q: SmartQuery) {
    return this.database.client.$transaction(async tx => {
      const now = new Date(), area = await this.pricing.validateArea(tx,q.area);
      const words = (q.q ?? '').toLowerCase().split(/\s+/).filter(Boolean);
      const where: Prisma.MenuItemWhereInput = {
        availabilityStatus: 'AVAILABLE', category: { isActive: true },
        ...(q.category ? {categoryId:q.category} : {}),
        ...(q.vegetarian !== undefined ? {isVegetarian:q.vegetarian} : {}),
        ...(q.maxPricePaise !== undefined ? {basePricePaise:{lte:q.maxPricePaise}} : {}),
        restaurant: { operatingStatus: 'OPEN', deliveryAvailability: true,
          ...(q.restaurantId ? {id:q.restaurantId} : {}),
          ...(q.cuisine ? {cuisines:{some:{cuisineId:q.cuisine}}} : {}),
          ...(q.minRating !== undefined ? {rating:{gte:q.minRating}} : {}),
          zones:{some:{zoneId:q.area,isEligible:true,zone:{isActive:true}}},
        },
        AND: [...wordsWhere(words), {OR:[{variants:{none:{}}},{variants:{some:{isAvailable:true}}}]}],
      };
      // Apply every DB-expressible constraint first; exact pricing occurs in one bounded snapshot.
      // Never paginate before fee/budget filtering, which would produce false empty pages/totals.
      const items = await tx.menuItem.findMany({where,include:itemInclude,take:5001,orderBy:{id:'asc'}});
      if(items.length>5000) throw new UnprocessableEntityException('Please narrow the search with a category or restaurant');
      const rules = await this.pricing.rules(tx,q.area,now);
      const priced = items.map(item => {
        const quote = this.pricing.price(item,{restaurantId:item.restaurantId,menuItemId:item.id,area:q.area,quantity:1,addOnIds:[]},rules,now,area.name);
        const name = item.name.toLowerCase();
        const relevance = words.length ? words.reduce((sum,w) => sum+(name.includes(w)?3:1),0) : 0;
        const rating = Number(item.restaurant.rating);
        // Stable absolute score, not dependent on page size or which competitors were fetched.
        const priceScore = Math.max(0,100-Math.floor(quote.finalPayablePaise/1000));
        const timeScore = Math.max(0,100-quote.estimatedMinutes);
        const valueScore = priceScore*50 + Math.round(rating*20)*30 + timeScore*20;
        const explanations = [`Eligible for ${area.name}.`, 'One item with configured fees included.'];
        if(q.maxPayablePaise !== undefined && quote.finalPayablePaise<=q.maxPayablePaise) explanations.push(`${q.maxPayablePaise-quote.finalPayablePaise} paise below your budget.`);
        if(q.vegetarian === true) explanations.push('Matches the stored vegetarian attribute.');
        if(q.maxMinutes !== undefined && quote.estimatedMinutes<=q.maxMinutes) explanations.push(`Illustrative delivery estimate is within ${q.maxMinutes} minutes.`);
        return {quote,explanations,valueScore,relevance,rating};
      }).filter(x => (q.maxPayablePaise === undefined || x.quote.finalPayablePaise<=q.maxPayablePaise) &&
        (q.maxMinutes === undefined || x.quote.estimatedMinutes<=q.maxMinutes));
      priced.sort((a,b) => {
        const primary = q.sort==='price' ? a.quote.finalPayablePaise-b.quote.finalPayablePaise
          : q.sort==='time' ? a.quote.estimatedMinutes-b.quote.estimatedMinutes
          : q.sort==='rating' ? b.rating-a.rating : q.sort==='relevance' ? b.relevance-a.relevance : b.valueScore-a.valueScore;
        return primary || b.relevance-a.relevance || a.quote.finalPayablePaise-b.quote.finalPayablePaise || a.quote.item.id.localeCompare(b.quote.item.id, 'en');
      });
      return {items:priced.slice((q.page-1)*q.limit,q.page*q.limit),total:priced.length,page:q.page,limit:q.limit,
        area,sort:q.sort,availability:'available-only',dietaryAttributes:['vegetarian'],
        rankingPolicy:'value-v1: price 50%, sample rating 30%, illustrative time 20%; ties relevance, payable, ID',
        quoteBasis:'One item, cheapest available variant, no add-ons, quantity one. Independent meal quote, not a multi-item cart.'};
    },{isolationLevel:'RepeatableRead'});
  }
}
