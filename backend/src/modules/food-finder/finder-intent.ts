/**
 * Smart Food Finder intent: the structured search state of one conversation.
 *
 * Adapted from Jeevan's F1 work on `feature/f1-ai-ordering`
 * (backend/src/modules/ai-ordering/food-intent.ts: strict allow-listed normalisation
 * and merge-with-explicit-clears). Extended with taste, nutrition, exclusions and
 * selection fields for the current catalog. Model output is treated as untrusted data.
 */
import { MAIN_INGREDIENTS, TASTES, type MainIngredient, type Taste } from './food-taxonomy';

export interface FinderIntent {
  dishQuery: string | null;
  budgetPaise: number | null;
  quantity: number;
  vegetarian: boolean | null;
  mainIngredient: MainIngredient | null;
  cuisine: string | null;
  tastes: Taste[];
  maxSpiceLevel: number | null;
  minSpiceLevel: number | null;
  excludeIngredients: string[];
  minProteinG: number | null;
  maxCaloriesKcal: number | null;
  restaurantQuery: string | null;
  sort: 'relevance' | 'cheapest' | 'protein';
}

export const EMPTY_INTENT: FinderIntent = {
  dishQuery: null, budgetPaise: null, quantity: 1, vegetarian: null, mainIngredient: null, cuisine: null, tastes: [],
  maxSpiceLevel: null, minSpiceLevel: null, excludeIngredients: [], minProteinG: null, maxCaloriesKcal: null, restaurantQuery: null, sort: 'relevance',
};

/** A partial update extracted from one customer message (null / absent = unchanged). */
export interface IntentUpdate {
  dishQuery?: string | null;
  budgetPaise?: number | null;
  quantity?: number | null;
  vegetarian?: boolean | null;
  mainIngredient?: MainIngredient | null;
  cuisine?: string | null;
  addTastes?: Taste[];
  removeTastes?: Taste[];
  maxSpiceLevel?: number | null;
  minSpiceLevel?: number | null;
  excludeIngredients?: string[];
  minProteinG?: number | null;
  maxCaloriesKcal?: number | null;
  restaurantQuery?: string | null;
  sort?: FinderIntent['sort'] | null;
  /** "Show cheaper options": lower the budget below the cheapest shown result. */
  cheaper?: boolean;
  /** 1-based index of a previously shown recommendation the customer picked. */
  selectIndex?: number | null;
  /** The customer starts an unrelated search: drop everything not restated. */
  newSearch?: boolean;
  clearFields?: ClearableField[];
  clarificationQuestion?: string | null;
}

export const CLEARABLE_FIELDS = ['dishQuery', 'budgetPaise', 'vegetarian', 'mainIngredient', 'cuisine', 'tastes', 'spice', 'excludeIngredients', 'minProteinG', 'maxCaloriesKcal', 'restaurantQuery'] as const;
export type ClearableField = (typeof CLEARABLE_FIELDS)[number];

const MAX_BUDGET_PAISE = 10_000_00; // ₹10,000

function text(v: unknown, max: number, field: string): string | null | undefined {
  if (v === undefined) return undefined;
  if (v === null) return null;
  if (typeof v !== 'string' || v.length > max) throw new Error(`Invalid ${field}`);
  const t = v.replace(/[\u0000-\u001f<>{}]/g, ' ').replace(/\s+/g, ' ').trim();
  return t || null;
}
function num(v: unknown, min: number, max: number, field: string, integer = true): number | null | undefined {
  if (v === undefined) return undefined;
  if (v === null) return null;
  if (typeof v !== 'number' || !Number.isFinite(v) || v < min || v > max || (integer && !Number.isInteger(v))) throw new Error(`Invalid ${field}`);
  return v;
}
function bool(v: unknown, field: string): boolean | null | undefined {
  if (v === undefined || v === null) return v as null | undefined;
  if (typeof v !== 'boolean') throw new Error(`Invalid ${field}`);
  return v;
}
function tastes(v: unknown, field: string): Taste[] | undefined {
  if (v === undefined || v === null) return undefined;
  if (!Array.isArray(v) || v.length > TASTES.length) throw new Error(`Invalid ${field}`);
  for (const t of v) if (!(TASTES as readonly unknown[]).includes(t)) throw new Error(`Invalid ${field}`);
  return [...new Set(v as Taste[])];
}

/** Strict, allow-listed normalisation of an untrusted update (model output or rule parser). */
export function normalizeUpdate(raw: unknown): IntentUpdate {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('Intent update must be an object');
  const d = raw as Record<string, unknown>;
  const allowed = new Set(['dishQuery', 'budgetPaise', 'quantity', 'vegetarian', 'mainIngredient', 'cuisine', 'addTastes', 'removeTastes', 'maxSpiceLevel', 'minSpiceLevel',
    'excludeIngredients', 'minProteinG', 'maxCaloriesKcal', 'restaurantQuery', 'sort', 'cheaper', 'selectIndex', 'newSearch', 'clearFields', 'clarificationQuestion']);
  for (const k of Object.keys(d)) if (!allowed.has(k)) throw new Error('Unexpected intent field');
  const main = d.mainIngredient;
  if (main !== undefined && main !== null && !(MAIN_INGREDIENTS as readonly unknown[]).includes(main)) throw new Error('Invalid mainIngredient');
  const sort = d.sort;
  if (sort !== undefined && sort !== null && !['relevance', 'cheapest', 'protein'].includes(sort as string)) throw new Error('Invalid sort');
  const ex = d.excludeIngredients;
  if (ex !== undefined && ex !== null && (!Array.isArray(ex) || ex.length > 8 || ex.some((e) => typeof e !== 'string' || !e.trim() || e.length > 30))) throw new Error('Invalid excludeIngredients');
  const clear = d.clearFields;
  if (clear !== undefined && clear !== null && (!Array.isArray(clear) || clear.some((c) => !(CLEARABLE_FIELDS as readonly unknown[]).includes(c)))) throw new Error('Invalid clearFields');
  const u: IntentUpdate = {
    dishQuery: text(d.dishQuery, 80, 'dishQuery'),
    budgetPaise: num(d.budgetPaise, 100, MAX_BUDGET_PAISE, 'budgetPaise'),
    quantity: num(d.quantity, 1, 20, 'quantity'),
    vegetarian: bool(d.vegetarian, 'vegetarian'),
    mainIngredient: main as MainIngredient | null | undefined,
    cuisine: text(d.cuisine, 40, 'cuisine'),
    addTastes: tastes(d.addTastes, 'addTastes'),
    removeTastes: tastes(d.removeTastes, 'removeTastes'),
    maxSpiceLevel: num(d.maxSpiceLevel, 0, 3, 'maxSpiceLevel'),
    minSpiceLevel: num(d.minSpiceLevel, 0, 3, 'minSpiceLevel'),
    excludeIngredients: ex == null ? undefined : [...new Set((ex as string[]).map((e) => e.trim().toLowerCase()))],
    minProteinG: num(d.minProteinG, 1, 200, 'minProteinG'),
    maxCaloriesKcal: num(d.maxCaloriesKcal, 50, 3000, 'maxCaloriesKcal'),
    restaurantQuery: text(d.restaurantQuery, 60, 'restaurantQuery'),
    sort: sort as FinderIntent['sort'] | null | undefined,
    cheaper: bool(d.cheaper, 'cheaper') ?? undefined,
    selectIndex: num(d.selectIndex, 1, 20, 'selectIndex'),
    newSearch: bool(d.newSearch, 'newSearch') ?? undefined,
    clearFields: (clear as ClearableField[] | null | undefined) ?? undefined,
    clarificationQuestion: text(d.clarificationQuestion, 240, 'clarificationQuestion'),
  };
  for (const k of Object.keys(u) as (keyof IntentUpdate)[]) if (u[k] === undefined) delete u[k];
  return u;
}

/** Applies an update to the remembered intent. Explicit clears win; unspecified fields are kept. */
export function applyUpdate(prev: FinderIntent | null, u: IntentUpdate): FinderIntent {
  const base: FinderIntent = u.newSearch || !prev ? { ...EMPTY_INTENT, tastes: [], excludeIngredients: [] } : { ...prev, tastes: [...prev.tastes], excludeIngredients: [...prev.excludeIngredients] };
  // Hard dietary choice survives a new dish search unless the customer changes it.
  if (u.newSearch && prev?.vegetarian === true) base.vegetarian = true; // only an explicit vegetarian choice carries over
  const set = <K extends keyof FinderIntent>(k: K, v: FinderIntent[K] | null | undefined) => { if (v !== undefined && v !== null) base[k] = v; };
  if (u.dishQuery !== undefined && u.dishQuery !== null && u.dishQuery !== base.dishQuery) {
    base.dishQuery = u.dishQuery;
    if (u.mainIngredient === undefined) base.mainIngredient = null; // the new dish defines its own ingredient
  }
  set('budgetPaise', u.budgetPaise);
  set('quantity', u.quantity);
  if (u.vegetarian !== undefined && u.vegetarian !== null) {
    base.vegetarian = u.vegetarian;
    if (u.vegetarian && base.mainIngredient && ['chicken', 'mutton', 'seafood', 'egg', 'meat'].includes(base.mainIngredient)) {
      base.mainIngredient = null; // "give me a vegetarian option instead"
      if (base.dishQuery && /chicken|mutton|egg|fish|prawn|meat|keema/i.test(base.dishQuery)) base.dishQuery = base.dishQuery.replace(/\b(chicken|mutton|egg|fish|prawn|meat|keema)\b/gi, '').replace(/\s+/g, ' ').trim() || null;
    }
  }
  set('mainIngredient', u.mainIngredient);
  set('cuisine', u.cuisine);
  if (u.addTastes) base.tastes = [...new Set([...base.tastes, ...u.addTastes])];
  if (u.removeTastes) base.tastes = base.tastes.filter((t) => !u.removeTastes!.includes(t));
  if (base.tastes.includes('spicy') && base.tastes.includes('mild')) base.tastes = base.tastes.filter((t) => t !== (u.addTastes?.includes('mild') ? 'spicy' : 'mild'));
  set('maxSpiceLevel', u.maxSpiceLevel);
  set('minSpiceLevel', u.minSpiceLevel);
  if (u.excludeIngredients) base.excludeIngredients = [...new Set([...base.excludeIngredients, ...u.excludeIngredients])].slice(0, 8);
  set('minProteinG', u.minProteinG);
  set('maxCaloriesKcal', u.maxCaloriesKcal);
  set('restaurantQuery', u.restaurantQuery);
  set('sort', u.sort);
  for (const f of u.clearFields ?? []) {
    if (f === 'tastes') base.tastes = [];
    else if (f === 'spice') { base.maxSpiceLevel = null; base.minSpiceLevel = null; base.tastes = base.tastes.filter((t) => t !== 'spicy' && t !== 'mild'); }
    else if (f === 'excludeIngredients') base.excludeIngredients = [];
    else (base as any)[f] = null;
  }
  if (base.minSpiceLevel !== null && base.maxSpiceLevel !== null && base.minSpiceLevel > base.maxSpiceLevel) {
    if (u.minSpiceLevel != null) base.maxSpiceLevel = null; else base.minSpiceLevel = null;
  }
  // Diet vs dish conflict: whichever the customer said in THIS message wins, never "vegetarian chicken".
  const meatDish = (base.mainIngredient && ['chicken', 'mutton', 'seafood', 'egg', 'meat'].includes(base.mainIngredient)) ||
    /\b(chicken|mutton|egg|fish|prawn|keema|meat)\b/i.test(base.dishQuery ?? '');
  if (base.vegetarian === true && meatDish) {
    if (u.vegetarian === true) {
      base.mainIngredient = null;
      base.dishQuery = base.dishQuery?.replace(/\b(chicken|mutton|egg|fish|prawn|keema|meat)\b/gi, '').replace(/\s+/g, ' ').trim() || null;
    } else base.vegetarian = null;
  }
  return base;
}

export function hasSearchCriteria(i: FinderIntent) {
  return !!(i.dishQuery || i.mainIngredient || i.cuisine || i.tastes.length || i.minProteinG || i.maxCaloriesKcal || i.vegetarian !== null || i.budgetPaise || i.restaurantQuery);
}
