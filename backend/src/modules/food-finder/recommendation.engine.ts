/**
 * Budget-aware recommendation engine for Smart Food Finder.
 *
 * Every total comes from the authoritative PricingService (same calculator as cart
 * quotes and checkout). The budget is the TOTAL PAYABLE: food × quantity + packaging +
 * delivery + platform + configured tax − eligible discounts. "Within budget" is only
 * ever assigned when total ≤ budget. Candidate matching, filtering and ranking use
 * database attributes (MenuItemProfile, MenuItemNutrition, isVegetarian) — never model output.
 *
 * Approach to quantity/price rejection adapted from Jeevan's RecommendationService
 * (feature/f1-ai-ordering): price each candidate with the real engine, then filter.
 */
import { Inject, Injectable } from '@nestjs/common';
import { DatabaseService } from '../../database/database.module';
import { Prisma } from '../../generated/prisma/client';
import { itemInclude, itemDto } from '../catalog/catalog.mapper';
import { PricingService } from '../pricing/pricing.service';
import { classifyDish, familyOf, familySimilarity, type MainIngredient } from './food-taxonomy';
import type { FinderIntent } from './finder-intent';
import { correctWord, mainIngredientWord } from './rule-parser';

export const NEAR_BUDGET_FRACTION = Math.min(0.5, Math.max(0, Number(process.env.FINDER_NEAR_BUDGET_PCT ?? 15) / 100));
const LIMITS = { exact: 6, near: 4, similar: 6 };

const finderInclude = { ...itemInclude, profile: true } satisfies Prisma.MenuItemInclude;
type FinderItem = Prisma.MenuItemGetPayload<{ include: typeof finderInclude }>;

export type MatchType = 'EXACT' | 'NEAR_BUDGET' | 'SIMILAR';
export type BudgetStatus = 'EXACT_BUDGET' | 'WITHIN_BUDGET' | 'ABOVE_BUDGET' | 'NO_BUDGET';
export type ResultStatus = 'EXACT_MATCHES' | 'ALTERNATIVES_ONLY' | 'OVER_BUDGET_ONLY' | 'NO_RESULTS';

export interface Recommendation {
  menuItemId: string; restaurantId: string; restaurantName: string; locality: string | null;
  name: string; description: string; imageKey: string; isVegetarian: boolean; quantity: number;
  variant: { id: string; name: string } | null; hasVariantChoices: boolean; hasAddOns: boolean;
  pricing: { foodPaise: number; discountPaise: number; packagingPaise: number; deliveryPaise: number; platformPaise: number; taxPaise: number; totalPaise: number };
  budgetPaise: number | null; budgetStatus: BudgetStatus; budgetDifferencePaise: number | null;
  nutrition: ReturnType<typeof itemDto>['nutrition'];
  tasteTags: string[]; spiceLevel: number; foodFamily: string; cuisine: string;
  matchType: MatchType; reasons: string[]; score: number;
  quotedAt: string; quoteExpiresAt: string;
}

export interface FinderResult {
  status: ResultStatus;
  area: { id: string; name: string };
  budgetPaise: number | null; quantity: number; nearBudgetLimitPaise: number | null;
  exact: Recommendation[]; nearBudget: Recommendation[]; similar: Recommendation[];
  /** Dishes left out of strict nutrition matching because we hold no nutrition data for them. */
  excludedForMissingNutrition: number;
  summary: string;
  notice: string;
}

const MEAT = ['chicken', 'mutton', 'seafood', 'egg', 'meat'];
const SIDE_GROUPS = new Set(['bread', 'beverage', 'puff', 'snack']);
const rupees = (p: number) => `₹${(p / 100).toFixed(p % 100 ? 2 : 0)}`;

const GENERIC_WORDS: Record<string, string | null> = {
  snack: 'snack', snacks: 'snack', dessert: 'dessert', desserts: 'dessert', sweet: 'dessert', sweets: 'dessert', drink: 'beverage', drinks: 'beverage',
  beverage: 'beverage', beverages: 'beverage', breakfast: 'breakfast', tiffin: 'breakfast', tiffins: 'breakfast', starter: 'starter', starters: 'starter',
  meal: null, meals: null, food: null, dish: null, dishes: null, something: null, lunch: null, dinner: null,
};

export interface Want { dishGroup: string | null; mainIngredient: MainIngredient | null; foodFamily: string | null; tokens: string[] }

export function resolveWant(intent: FinderIntent): Want {
  const q = intent.dishQuery?.toLowerCase().trim() ?? '';
  const corrected = q.split(/\s+/).filter(Boolean).map((w) => correctWord(w)).join(' ');
  const main = intent.mainIngredient ?? mainIngredientWord(corrected);
  let words = corrected.split(/\s+/).filter((w) => w.length >= 3 && !['veg', 'with', 'and', 'the'].includes(w));
  // Category words ("snacks", "desserts", "breakfast") select a dish group; generic words ("meals", "food") select nothing.
  let generic: string | null = null;
  words = words.filter((w) => { const g = GENERIC_WORDS[w]; if (g === undefined) return true; if (g) generic = g; return false; });
  const text = words.join(' ');
  const group = text ? classifyDish({ name: text, description: '', isVegetarian: !main || !MEAT.includes(main) }).dishGroup : null;
  const dishGroup = group && group !== 'meal' ? group : generic;
  const tokens = words.map((w) => (w.length > 4 ? w.replace(/(e?s)$/, '') : w));
  return { dishGroup, mainIngredient: main, foodFamily: dishGroup && main ? familyOf(dishGroup, main) : null, tokens };
}

@Injectable()
export class RecommendationEngine {
  constructor(
    @Inject(DatabaseService) private readonly database: DatabaseService,
    @Inject(PricingService) private readonly pricing: PricingService,
  ) {}

  async recommend(intent: FinderIntent, areaId: string): Promise<FinderResult> {
    return this.database.client.$transaction(async (tx) => {
      const now = new Date();
      const area = await this.pricing.validateArea(tx, areaId);
      const items = await tx.menuItem.findMany({
        where: {
          availabilityStatus: 'AVAILABLE', category: { isActive: true },
          ...(intent.vegetarian !== null ? { isVegetarian: intent.vegetarian } : {}),
          restaurant: { operatingStatus: 'OPEN', deliveryAvailability: true, zones: { some: { zoneId: areaId, isEligible: true, zone: { isActive: true } } } },
          AND: [{ OR: [{ variants: { none: {} } }, { variants: { some: { isAvailable: true } } }] }],
        },
        include: finderInclude, take: 1500, orderBy: { id: 'asc' },
      });
      const rules = await this.pricing.rules(tx, areaId, now);
      return this.rank(intent, items, (item) => this.pricing.price(item, { restaurantId: item.restaurantId, menuItemId: item.id, area: areaId, quantity: intent.quantity, addOnIds: [] }, rules, now, area.name), { id: area.id, name: area.name });
    }, { isolationLevel: 'RepeatableRead' });
  }

  /** Pure ranking step (exported for unit tests with a stub price function). */
  rank(intent: FinderIntent, items: FinderItem[], price: (item: FinderItem) => ReturnType<PricingService['price']>, area: { id: string; name: string }): FinderResult {
    const want = resolveWant(intent);
    const B = intent.budgetPaise;
    const nearLimit = B === null ? null : Math.floor(B * (1 + NEAR_BUDGET_FRACTION));
    const hasDish = !!(want.dishGroup || want.mainIngredient || want.tokens.length);
    const rq = intent.restaurantQuery?.toLowerCase().split(/\s+/).filter((w) => w.length >= 3) ?? [];
    let excludedForMissingNutrition = 0;
    let dishOnMenu = false; // the requested dish exists in this area at any price
    let cheapestDishTotal: number | null = null; // lowest total for the requested dish, any budget
    let bestProtein: number | null = null, lowestKcal: number | null = null; // closest real values when a nutrition limit excludes everything
    const scored: Recommendation[] = [];

    for (const item of items) {
      const p = item.profile ?? { ...classifyDish(item), tagSource: 'RULES' };
      const hay = `${item.name} ${item.description}`.toLowerCase();
      // Hard constraints.
      if (intent.excludeIngredients.some((x) => hay.includes(x.replace(/s$/, '')) || (MEAT.includes(x) ? p.mainIngredient === (x === 'fish' || x === 'prawn' ? 'seafood' : x) : false))) continue;
      if (intent.excludeIngredients.includes('egg') && p.mainIngredient === 'egg') continue;
      if (intent.vegetarian === true && MEAT.includes(p.mainIngredient)) continue; // belt and braces
      if (rq.length && !rq.every((w) => item.restaurant.name.toLowerCase().includes(w) || correctWord(w, item.restaurant.name.toLowerCase().split(/\W+/)) !== w)) continue;
      if (intent.cuisine && !(p.cuisine.toLowerCase().includes(intent.cuisine.toLowerCase()) || item.restaurant.cuisineDescription.toLowerCase().includes(intent.cuisine.toLowerCase()))) continue;
      if (intent.minSpiceLevel !== null && p.spiceLevel < intent.minSpiceLevel) continue;
      if (intent.maxSpiceLevel !== null && p.spiceLevel > intent.maxSpiceLevel) continue;
      const n = item.nutrition;
      if ((intent.minProteinG !== null || intent.maxCaloriesKcal !== null || intent.sort === 'protein') && !n) { excludedForMissingNutrition++; continue; }
      if (intent.minProteinG !== null && Number(n!.proteinG) < intent.minProteinG) { bestProtein = Math.max(bestProtein ?? 0, Number(n!.proteinG)); continue; }
      if (intent.maxCaloriesKcal !== null && n!.caloriesKcal > intent.maxCaloriesKcal) { lowestKcal = Math.min(lowestKcal ?? Infinity, n!.caloriesKcal); continue; }

      // Relevance.
      const nameHay = `${item.name.toLowerCase()} ${p.synonyms.join(' ')}`;
      const textScore = want.tokens.length ? want.tokens.filter((t) => nameHay.includes(t)).length / want.tokens.length : 0;
      let fam = hasDish ? familySimilarity(want, p) : 1;
      if (hasDish && !want.dishGroup && !want.mainIngredient) fam = textScore >= 0.5 ? 1 : 0; // free-text dish we cannot classify
      if (want.mainIngredient && p.mainIngredient !== want.mainIngredient && fam >= 0.9) fam = 0.75;
      if (fam <= 0) continue;
      // Open requests (taste / cuisine / nutrition only) are about food, not drinks or sweets, unless asked.
      if (!want.dishGroup && !want.tokens.length && p.dishGroup === 'beverage') continue;
      if (!want.dishGroup && !want.tokens.length && p.dishGroup === 'dessert' && !intent.tastes.includes('sweet')) continue;
      const wanted = intent.tastes.filter((t) => t !== 'savory');
      const tasteHits = wanted.filter((t) => p.tasteTags.includes(t));
      const tasteScore = wanted.length ? tasteHits.length / wanted.length : 1;
      if (!hasDish && wanted.length && tasteScore === 0) continue;
      const exactDish = fam >= 0.9 && (textScore >= 0.5 || !want.tokens.length || !!want.dishGroup) && tasteScore >= (wanted.length ? 0.5 : 0);
      if (fam >= 0.9) dishOnMenu = true;
      // Open requests prefer proper dishes over sides; "spicy" prefers hotter dishes.
      const open = !want.dishGroup && !want.tokens.length;
      const mainBonus = open ? (SIDE_GROUPS.has(p.dishGroup) ? -0.15 : 0.1) : 0;
      const spiceBonus = wanted.includes('spicy') ? p.spiceLevel / 30 : wanted.includes('mild') ? (3 - p.spiceLevel) / 30 : 0;
      const score = Math.round((0.6 * fam + 0.3 * tasteScore + 0.1 * textScore + mainBonus + spiceBonus) * 1000) / 1000;

      let quote: ReturnType<PricingService['price']>;
      try { quote = price(item); } catch { continue; } // unservable / unavailable variant: never shown
      const total = quote.finalPayablePaise;
      if (exactDish && (cheapestDishTotal === null || total < cheapestDishTotal)) cheapestDishTotal = total;
      let matchType: MatchType | null;
      if (exactDish && (B === null || total <= B)) matchType = 'EXACT';
      else if (B !== null && total > B && total <= nearLimit! && fam >= 0.6) matchType = 'NEAR_BUDGET';
      else if (!exactDish && fam >= (want.mainIngredient && want.mainIngredient !== 'veg' ? 0.5 : 0.35) && (B === null || total <= B)) matchType = 'SIMILAR';
      else matchType = null;
      if (!matchType) continue;

      const budgetStatus: BudgetStatus = B === null ? 'NO_BUDGET' : total === B ? 'EXACT_BUDGET' : total < B ? 'WITHIN_BUDGET' : 'ABOVE_BUDGET';
      const reasons: string[] = [];
      if (hasDish && !want.dishGroup && want.mainIngredient && exactDish) reasons.push(`${want.mainIngredient[0].toUpperCase()}${want.mainIngredient.slice(1)} dish`);
      else if (hasDish) reasons.push(fam >= 0.9 && exactDish ? (textScore >= 0.99 ? 'Exact dish match' : 'Same food family') : fam >= 0.9 ? 'Same dish, different taste' : fam >= 0.6 ? 'Similar dish' : 'Related flavours');
      for (const t of tasteHits) reasons.push(`Matches ${t} preference`);
      if (budgetStatus === 'EXACT_BUDGET') reasons.push('Exact budget match');
      else if (budgetStatus === 'WITHIN_BUDGET') reasons.push(`${rupees(B! - total)} under budget`);
      else if (budgetStatus === 'ABOVE_BUDGET') reasons.push(`${rupees(total - B!)} above your budget`);
      if (n && intent.minProteinG !== null) reasons.push(`${Number(n.proteinG)} g protein (estimate)`);
      if (n && intent.maxCaloriesKcal !== null) reasons.push(`${n.caloriesKcal} kcal (estimate)`);

      const variants = item.variants.filter((v) => v.isAvailable);
      scored.push({
        menuItemId: item.id, restaurantId: item.restaurantId, restaurantName: item.restaurant.name, locality: item.restaurant.locality?.name ?? null,
        name: item.name, description: item.description, imageKey: item.imageKey, isVegetarian: item.isVegetarian, quantity: intent.quantity,
        variant: quote.selectedVariant ? { id: quote.selectedVariant.id, name: quote.selectedVariant.name } : null,
        hasVariantChoices: variants.length > 1, hasAddOns: item.addOns.some((a) => a.addOn.isAvailable),
        pricing: { foodPaise: quote.subtotalPaise, discountPaise: quote.discountPaise, packagingPaise: quote.packagingPaise, deliveryPaise: quote.deliveryPaise, platformPaise: quote.platformPaise, taxPaise: quote.taxPaise, totalPaise: total },
        budgetPaise: B, budgetStatus, budgetDifferencePaise: B === null ? null : total - B,
        nutrition: itemDto(item as any).nutrition,
        tasteTags: p.tasteTags, spiceLevel: p.spiceLevel, foodFamily: p.foodFamily, cuisine: p.cuisine,
        matchType, reasons, score, quotedAt: quote.quotedAt, quoteExpiresAt: quote.expiresAt,
      });
    }

    const protein = (r: Recommendation) => r.nutrition?.proteinG ?? -1;
    const byPreference = (a: Recommendation, b: Recommendation) =>
      intent.sort === 'cheapest' ? a.pricing.totalPaise - b.pricing.totalPaise || b.score - a.score
        : intent.sort === 'protein' ? protein(b) - protein(a) || a.pricing.totalPaise - b.pricing.totalPaise
          : b.score - a.score || a.pricing.totalPaise - b.pricing.totalPaise || a.menuItemId.localeCompare(b.menuItemId);
    // One card per dish per kitchen, at most two kitchens' worth of the same dish name, two cards per kitchen.
    const dedupe = (list: Recommendation[]) => {
      const seen = new Set<string>(), perKitchen = new Map<string, number>(), perName = new Map<string, number>();
      return list.filter((r) => {
        const k = `${r.restaurantId}|${r.name.toLowerCase()}`, n = r.name.toLowerCase();
        if (seen.has(k) || (perKitchen.get(r.restaurantId) ?? 0) >= 2 || (perName.get(n) ?? 0) >= 2) return false;
        seen.add(k); perKitchen.set(r.restaurantId, (perKitchen.get(r.restaurantId) ?? 0) + 1); perName.set(n, (perName.get(n) ?? 0) + 1);
        return true;
      });
    };
    const exact = dedupe(scored.filter((r) => r.matchType === 'EXACT').sort(byPreference)).slice(0, LIMITS.exact);
    const nearBudget = dedupe(scored.filter((r) => r.matchType === 'NEAR_BUDGET').sort((a, b) => a.pricing.totalPaise - b.pricing.totalPaise || b.score - a.score)).slice(0, LIMITS.near);
    const similar = dedupe(scored.filter((r) => r.matchType === 'SIMILAR').sort(byPreference)).slice(0, LIMITS.similar);

    const status: ResultStatus = exact.length ? 'EXACT_MATCHES' : similar.length ? 'ALTERNATIVES_ONLY' : nearBudget.length ? 'OVER_BUDGET_ONLY' : 'NO_RESULTS';
    return {
      status, area, budgetPaise: B, quantity: intent.quantity, nearBudgetLimitPaise: nearLimit,
      exact, nearBudget, similar, excludedForMissingNutrition,
      summary: summarize(intent, status, { exact, nearBudget, similar }, excludedForMissingNutrition, dishOnMenu || !hasDish, cheapestDishTotal, { bestProtein, lowestKcal }),
      notice: 'Synthetic demo restaurants with illustrative prices. Totals use the live pricing rules for your area and are re-quoted at cart and checkout. Nutrition values are estimates, not medical advice.',
    };
  }
}

export function describeIntent(i: FinderIntent) {
  const parts: string[] = [];
  if (i.quantity > 1) parts.push(`${i.quantity} ×`);
  if (i.tastes.length) parts.push(i.tastes.filter((t) => t !== 'savory').join(', '));
  if (i.vegetarian === true && !/veg/i.test(i.dishQuery ?? '')) parts.push('vegetarian');
  if (i.vegetarian === false && !i.dishQuery) parts.push('non-veg');
  parts.push(i.dishQuery ?? (i.cuisine ? `${i.cuisine} food` : i.mainIngredient && i.mainIngredient !== 'veg' ? `${i.mainIngredient} dishes` : 'food'));
  if (i.minProteinG) parts.push(`with ${i.minProteinG} g+ protein`);
  if (i.maxCaloriesKcal) parts.push(`under ${i.maxCaloriesKcal} kcal`);
  return parts.filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
}

function summarize(i: FinderIntent, status: ResultStatus, r: { exact: Recommendation[]; nearBudget: Recommendation[]; similar: Recommendation[] }, missingNutrition: number, dishOnMenu = true, cheapestDishTotal: number | null = null, closest: { bestProtein: number | null; lowestKcal: number | null } = { bestProtein: null, lowestKcal: null }) {
  const what = describeIntent(i);
  const within = i.budgetPaise !== null ? ` within ${rupees(i.budgetPaise)} total` : '';
  const nutritionNote = missingNutrition ? ` (${missingNutrition} dish${missingNutrition === 1 ? ' has' : 'es have'} no nutrition data, so I left ${missingNutrition === 1 ? 'it' : 'them'} out.)` : '';
  const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;
  const near = r.nearBudget.length ? ` ${plural(r.nearBudget.length, 'option is', 'options are')} slightly above budget — I'll ask before adding.` : '';
  switch (status) {
    case 'EXACT_MATCHES': {
      const best = r.exact[0];
      return `Found ${plural(r.exact.length, 'match', 'matches')} for ${what}${within}. ${best.name} at ${best.restaurantName} comes to ${rupees(best.pricing.totalPaise)} including delivery and fees.` +
        (r.similar.length ? ` Plus ${plural(r.similar.length, 'related dish', 'related dishes')}.` : '') + nutritionNote;
    }
    case 'ALTERNATIVES_ONLY':
      return (!dishOnMenu && i.dishQuery
        ? `No restaurant delivering to you serves ${i.dishQuery} right now, but I found ${plural(r.similar.length, 'related dish', 'related dishes')} you may like.`
        : `I couldn't find ${what}${within}, but I found ${plural(r.similar.length, 'related dish', 'related dishes')} that fit your taste and budget.`) + near + nutritionNote;
    case 'OVER_BUDGET_ONLY':
      return `Nothing for ${what} fits${within}.${near}` + nutritionNote;
    default:
      if (!dishOnMenu && i.dishQuery) return `No restaurant delivering to you serves ${i.dishQuery} right now. Try a different dish or ask for something similar.` + nutritionNote;
      if (cheapestDishTotal !== null && i.budgetPaise !== null) return `I couldn't find ${what}${within}. The lowest total near you is ${rupees(cheapestDishTotal)} — try a higher budget, a smaller portion or fewer items.` + nutritionNote;
      if (i.minProteinG !== null && closest.bestProtein !== null) return `I couldn't find ${what}${within} nearby. The highest-protein match near you has about ${closest.bestProtein} g — try asking for ${Math.floor(closest.bestProtein / 5) * 5} g protein.` + nutritionNote;
      if (i.maxCaloriesKcal !== null && closest.lowestKcal !== null) return `I couldn't find ${what}${within} nearby. The lightest match near you is about ${closest.lowestKcal} kcal.` + nutritionNote;
      return `I couldn't find ${what}${within} nearby. Try a higher budget, a different dish or fewer filters.` + nutritionNote;
  }
}
