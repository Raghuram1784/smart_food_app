/**
 * Deterministic message parser for Smart Food Finder.
 *
 * Used (1) when Gemini is unavailable (no key, quota, timeout, invalid output) so the
 * finder still works in a basic mode, and (2) to cross-check numbers in Gemini's output:
 * a budget / protein / calorie limit is accepted only if the customer actually typed it.
 */
import type { IntentUpdate } from './finder-intent';
import type { Taste, MainIngredient } from './food-taxonomy';

const WORD_NUM: Record<string, number> = { one: 1, a: 1, an: 1, single: 1, two: 2, couple: 2, three: 3, four: 4, five: 5, six: 6 };

/** Words the finder understands as food; used for spelling correction. */
export const DISH_VOCAB = [
  'biryani', 'pulao', 'fried rice', 'rice', 'dosa', 'idli', 'vada', 'upma', 'pongal', 'uttapam', 'pesarattu', 'pizza', 'burger', 'pasta', 'noodles',
  'momos', 'paneer', 'chicken', 'mutton', 'egg', 'fish', 'prawn', 'tikka', 'kebab', 'tandoori', 'naan', 'roti', 'paratha', 'thali', 'meals', 'chaat',
  'samosa', 'pakoda', 'fries', 'sandwich', 'wrap', 'roll', 'haleem', 'dessert', 'lassi', 'chai', 'coffee', 'tea', 'manchurian', 'schezwan', 'butter',
  'masala', 'curry', 'dal', 'salad', 'bowl', 'khichdi', 'pav', 'bhaji', 'puri', 'gulab', 'jamun', 'kulfi', 'brownie', 'shake', 'juice', 'margherita',
  'pepperoni', 'zinger', 'nuggets', 'quinoa', 'mushroom', 'chole', 'kulcha', 'puff', 'biscuit', 'meetha', 'rasmalai', 'phirni', 'snack', 'snacks',
  'breakfast', 'tiffin', 'starter', 'soup', 'sweet', 'sweets', 'drink', 'drinks', 'mandi', 'shawarma', 'kathi', 'bhel', 'keema', 'pepper', 'ghee',
];

const STOP = new Set(['i', 'want', 'need', 'would', 'like', 'some', 'something', 'me', 'show', 'give', 'get', 'find', 'for', 'a', 'an', 'the', 'please', 'under',
  'below', 'within', 'around', 'about', 'less', 'than', 'upto', 'up', 'to', 'budget', 'of', 'with', 'and', 'or', 'in', 'is', 'my', 'now', 'only', 'can', 'you',
  'options', 'option', 'dish', 'dishes', 'food', 'meal', 'order', 'rs', 'inr', 'rupees', 'rupee', 'total', 'max', 'maximum', 'cheap', 'cheaper', 'cheapest',
  'make', 'it', 'more', 'very', 'extra', 'not', 'too', 'no', 'any', 'that', 'this', 'which', 'what', 'have', 'has', 'do', 'eat', 'good', 'best', 'tasty',
  'nice', 'also', 'instead', 'similar', 'like', 'same', 'one', 'two', 'three', 'four', 'plates', 'plate', 'portion', 'portions', 'servings', 'serving',
  'high', 'low', 'protein', 'calories', 'calorie', 'kcal', 'cal', 'grams', 'gram', 'g', 'veg', 'vegetarian', 'nonveg', 'non', 'pure', 'spicy', 'spicier',
  'mild', 'tangy', 'sweet', 'creamy', 'smoky', 'crunchy', 'crispy', 'aromatic', 'rich', 'light', 'hot', 'fiery', 'savory', 'savoury', 'at', 'from', 'on',
  'remove', 'drop', 'clear', 'ignore', 'limit', 'price', 'without', 'avoid', 'exclude', 'allergic', 'lunch', 'dinner', 'tonight', 'today', 'quick',
  'add', 'select', 'choose', 'pick', 'first', 'second', 'third', 'fourth', 'fifth', 'number', 'cart', 'show', 'anything', 'else', 'other', 'different',
  'increase', 'decrease', 'raise', 'lower', 'reduce', 'change', 'set', 'go', 'let', 'lets', 'us', 'be', 'should', 'could', 'just', 'something', 'dish']);

export function levenshtein(a: string, b: string) {
  const m = a.length, n = b.length; if (!m || !n) return m + n;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = cur;
  }
  return prev[n];
}

/** Corrects a single misspelt food word ("biriyani", "biryni", "panner") against the vocabulary. */
export function correctWord(w: string, vocab: readonly string[] = DISH_VOCAB): string {
  if (w.length < 4 || vocab.includes(w)) return w;
  const limit = w.length >= 7 ? 2 : 1;
  let best: string | null = null, bestD = limit + 1;
  for (const v of vocab) {
    if (v.includes(' ')) continue;
    const d = levenshtein(w, v);
    if (d < bestD) { best = v; bestD = d; }
  }
  return best ?? w;
}

const TASTE_WORDS: [RegExp, Taste][] = [
  [/\btangy\b|\bsour\b|\bchatpata\b/, 'tangy'], [/\bsweet\b(?! lassi)|\bdessert/, 'sweet'], [/\bcreamy\b|\bbuttery\b/, 'creamy'],
  [/\bsmoky\b|\bsmoked\b|\bgrilled\b|\btandoori\b/, 'smoky'], [/\bcrunchy\b|\bcrispy\b|\bcrisp\b/, 'crunchy'], [/\baromatic\b|\bfragrant\b/, 'aromatic'],
  [/\brich\b|\bindulgent\b/, 'rich'], [/\blight\b|\blow[- ]oil\b/, 'light'], [/\bsavou?ry\b/, 'savory'],
];

const CUISINES: [RegExp, string][] = [
  [/south indian|udupi|tiffin/, 'South Indian'], [/north indian|punjabi/, 'North Indian'], [/indo[- ]?chinese|chinese/, 'Indo-Chinese'],
  [/italian/, 'Italian'], [/hyderabadi/, 'Hyderabadi'], [/andhra|telangana/, 'Andhra'], [/mughlai/, 'Mughlai'], [/street food/, 'Street Food'],
  [/healthy/, 'Healthy'], [/fast food/, 'Fast Food'],
];

const EXCLUDABLE = ['onion', 'garlic', 'egg', 'eggs', 'nuts', 'nut', 'peanut', 'peanuts', 'cashew', 'mushroom', 'mushrooms', 'paneer', 'cheese', 'dairy', 'milk', 'gluten', 'coconut', 'chicken', 'mutton', 'fish', 'prawn', 'prawns', 'sugar'];

export function mainIngredientWord(t: string): MainIngredient | null {
  if (/\b(mutton|lamb|goat|gosht|keema)\b/.test(t)) return 'mutton';
  if (/\b(chicken|murgh)\b/.test(t)) return 'chicken';
  if (/\b(fish|prawns?|seafood)\b/.test(t)) return 'seafood';
  if (/\beggs?\b|\banda\b/.test(t)) return 'egg';
  if (/\bpaneer\b/.test(t)) return 'paneer';
  if (/\bmushrooms?\b/.test(t)) return 'mushroom';
  return null;
}

export function parseMessage(message: string): IntentUpdate {
  const raw = message.toLowerCase().replace(/[’']/g, "'").replace(/\s+/g, ' ').trim();
  const u: IntentUpdate = {};
  let t = raw;

  // Explicit exclusions first so "no onion" never becomes a dish word.
  const ex = [...t.matchAll(/\b(?:without|no|exclude|avoid|allergic to|skip)\s+(?:any\s+)?([a-z]+)/g)].map((m) => m[1]).filter((w) => EXCLUDABLE.includes(w));
  if (ex.length) { u.excludeIngredients = ex.map((w) => w.replace(/s$/, '').replace(/^nut$/, 'nuts')); for (const w of ex) t = t.replace(new RegExp(`\\b(without|no|exclude|avoid|allergic to|skip)\\s+(any\\s+)?${w}\\b`, 'g'), ' '); }

  // Clears.
  const clear = new Set<NonNullable<IntentUpdate['clearFields']>[number]>();
  if (/\b(remove|drop|clear|ignore|forget|no|without|any)\b.{0,12}\b(budget|price limit|price cap|limit)\b|\bno budget\b|\bany price\b|\bprice doesn'?t matter\b/.test(t)) clear.add('budgetPaise');
  if (/\b(remove|drop|clear|ignore|no|any)\b.{0,12}\b(taste|flavou?r|spice)\b.{0,12}\b(preference|restriction|filter|level)?/.test(t) && !/\bspic(y|ier)\b/.test(t)) { clear.add('tastes'); clear.add('spice'); }
  if (/\b(remove|drop|clear|ignore)\b.{0,12}\b(protein)\b/.test(t)) clear.add('minProteinG');
  if (/\b(remove|drop|clear|ignore)\b.{0,12}\b(calorie|kcal)/.test(t)) clear.add('maxCaloriesKcal');
  if (/\b(any|either) (veg or non[- ]?veg|diet)\b|\bboth veg and non[- ]?veg\b/.test(t)) clear.add('vegetarian');
  if (/\b(start over|new search|reset|clear everything|clear all)\b/.test(t)) u.newSearch = true;

  // Protein / calories (before the budget so "500 calories" is never read as ₹500).
  const prot = t.match(/(\d{1,3})\s*(?:g|gm|grams?)\s*(?:of\s+)?protein|protein\s*(?:of\s*)?(?:at least|min(?:imum)?|over|above)?\s*(\d{1,3})\s*(?:g|grams?)/);
  if (prot) { u.minProteinG = Number(prot[1] ?? prot[2]); t = t.replace(prot[0], ' '); }
  else if (/high[- ]protein|protein[- ]rich|lots of protein/.test(t) && !clear.has('minProteinG')) u.minProteinG = 20;
  const cal = t.match(/(?:under|below|less than|max(?:imum)?|within|upto|up to)?\s*(\d{3,4})\s*(?:calories|calorie|kcals?|cals?)\b/);
  if (cal) { u.maxCaloriesKcal = Number(cal[1]); t = t.replace(cal[0], ' '); }
  else if (/low[- ]cal(orie)?s?/.test(t)) u.maxCaloriesKcal = 450;

  // Quantity ("2 plates", "for 3 people", "two biryanis").
  const qty = t.match(/\b(\d{1,2}|one|two|three|four|five|six|couple)\s*(?:x\s|plates?|portions?|servings?|orders?|packs?|people|persons?)\b|\bfor (\d{1,2}|two|three|four|five|six) (?:people|persons?)\b/);
  if (qty) { const q = qty[1] ?? qty[2]; u.quantity = WORD_NUM[q] ?? Number(q); t = t.replace(qty[0], ' '); }
  else {
    // "2 full mutton biryanis", "three masala dosas": a count directly before a dish (the dish words stay).
    const q2 = t.match(/\b(\d{1,2}|two|three|four|five|six)\s+((?:full|regular|large|big|plates of)\s+)?(?=(?:[a-z]+\s+)?(?:biryanis?|dosas?|pizzas?|burgers?|thalis?|rolls?|bowls?|idlis?|samosas?|wraps?|momos|meals)\b)/);
    if (q2 && Number(WORD_NUM[q2[1]] ?? q2[1]) <= 20) { u.quantity = WORD_NUM[q2[1]] ?? Number(q2[1]); t = t.replace(q2[0], ' '); }
  }

  // Budget: currency-marked numbers, or a number after a budget word. Interpreted as the TOTAL payable.
  const money = t.match(/(?:₹|rs\.?|inr)\s*(\d{2,5})|(\d{2,5})\s*(?:₹|rs\b|rupees?|\/-|bucks)|(?:under|below|within|less than|upto|up to|for|around|budget(?: of| is)?|max(?:imum)?|increase (?:it|budget)? ?to|decrease (?:it|budget)? ?to|change (?:it|budget)? ?to|make it)\s*(\d{2,5})\b(?!\s*(?:g|grams|kcal|cal|calories|people|plates?|pcs|pieces))/);
  if (money && !clear.has('budgetPaise')) { u.budgetPaise = Number(money[1] ?? money[2] ?? money[3]) * 100; t = t.replace(money[0], ' '); }
  if (/\b(cheaper|less expensive|lower (?:price|cost)|more affordable|budget[- ]friendly)\b/.test(t)) u.cheaper = true;
  if (/\bcheapest\b|\blowest price\b/.test(t)) u.sort = 'cheapest';
  if (/\b(most|highest|more) protein\b/.test(t)) u.sort = 'protein';

  // Diet.
  if (/\bnon[- ]?veg(etarian)?\b/.test(t)) u.vegetarian = false;
  else if (/\b(pure veg|vegetarian|veggie|veg)\b|\bno meat\b/.test(t)) u.vegetarian = true;

  // Spice and tastes.
  const add: Taste[] = [], remove: Taste[] = [];
  if (/\b(less spicy|not (?:too |very |that )?spicy|no spice|mild(?:er|ly spicy)?|not hot)\b/.test(t)) {
    if (/mildly spicy/.test(t)) { u.maxSpiceLevel = 2; u.minSpiceLevel = 1; } else { add.push('mild'); remove.push('spicy'); u.maxSpiceLevel = 1; }
  } else if (/\b(spicier|more spicy|extra spicy|very spicy|super spicy|fiery|extra hot)\b/.test(t)) { add.push('spicy'); remove.push('mild'); u.minSpiceLevel = /extra|very|super|fiery/.test(t) ? 3 : 2; }
  else if (/\bspicy\b|\bhot and\b|\bteekha\b/.test(t)) { add.push('spicy'); remove.push('mild'); }
  for (const [re, taste] of TASTE_WORDS) if (re.test(t) && !(taste === 'sweet' && /\bsweet (corn|potato)\b/.test(t))) add.push(taste);
  if (add.length) u.addTastes = [...new Set(add)];
  if (remove.length) u.removeTastes = remove;

  // Cuisine and restaurant.
  for (const [re, c] of CUISINES) if (re.test(t)) { u.cuisine = c; break; }
  const from = t.match(/\bfrom ([a-z&' ]{3,40}?)(?:\s+(?:under|below|within|for|with)\b|$)/);
  if (from && !/^(the )?(menu|list|above|options?)$/.test(from[1].trim())) { u.restaurantQuery = from[1].trim(); t = t.replace(from[0], ' '); }

  // Selecting a shown recommendation ("add the second one").
  const ord = t.match(/\b(first|second|third|fourth|fifth|1st|2nd|3rd|4th|5th)\b|\b(?:option|number|#)\s*(\d)\b/);
  if (ord && /\b(add|select|choose|pick|take|want|order|that|this|one|option|number|#)\b/.test(t)) {
    const map: Record<string, number> = { first: 1, '1st': 1, second: 2, '2nd': 2, third: 3, '3rd': 3, fourth: 4, '4th': 4, fifth: 5, '5th': 5 };
    u.selectIndex = ord[1] ? map[ord[1]] : Number(ord[2]);
  }

  // Dish: remaining food words, spelling-corrected.
  const main = mainIngredientWord(t);
  const words = t.replace(/[^a-z ]/g, ' ').split(' ').filter(Boolean).map((w) => (STOP.has(w) ? w : correctWord(w)));
  const food = words.filter((w) => !STOP.has(w) && (DISH_VOCAB.includes(w) || DISH_VOCAB.some((v) => v.includes(' ') && t.includes(v)) || w.length >= 4));
  const dishWords = food.filter((w) => !CUISINES.some(([re]) => re.test(w)) && !['option', 'something', 'anything'].includes(w));
  const hasFoodNoun = dishWords.some((w) => DISH_VOCAB.includes(w));
  if (hasFoodNoun) {
    u.dishQuery = dishWords.join(' ').slice(0, 80);
    if (main) u.mainIngredient = main;
    if (main && ['chicken', 'mutton', 'seafood', 'egg'].includes(main) && u.vegetarian === undefined) u.vegetarian = null as any;
  } else if (main && !u.excludeIngredients?.length) {
    u.mainIngredient = main;
  }
  if (clear.size) u.clearFields = [...clear];
  // A self-contained request ("find meals with 25g protein under ₹250") starts a new search;
  // adjustments ("now under ₹150", "vegetarian instead", "make it spicier") refine the current one.
  const fresh = /^(i want|i'd like|i would like|i need|find|show me|give me|get me|looking for|suggest|recommend|craving)\b/.test(raw)
    && !/\b(instead|now|also|too|cheaper|more|less|again|same|similar|remove|without|another|other|change)\b/.test(raw);
  if (fresh && (u.dishQuery || u.minProteinG || u.maxCaloriesKcal || u.cuisine || u.addTastes?.length || u.mainIngredient)) u.newSearch = true;
  for (const k of Object.keys(u) as (keyof IntentUpdate)[]) if (u[k] === undefined || u[k] === null) delete u[k];
  return u;
}

/** Numbers the customer actually typed (used to reject invented budgets/limits from the model). */
export function numbersIn(message: string): number[] {
  return [...message.replace(/,(?=\d{3})/g, '').matchAll(/\d+(?:\.\d+)?/g)].map((m) => Number(m[0]));
}
