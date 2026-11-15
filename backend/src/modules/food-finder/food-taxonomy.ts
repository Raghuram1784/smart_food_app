/**
 * Smart Food Finder taxonomy: deterministic, rule-based classification of a dish
 * into food family / dish group / main ingredient / taste / spice.
 *
 * Used by the catalog seed (to profile items that have no curated profile) and by
 * the recommender (to normalise customer requests such as "chicken biriyani").
 * Rules only read the dish's own name, description and category — never prices.
 */

export const TASTES = ['spicy', 'mild', 'tangy', 'sweet', 'savory', 'creamy', 'smoky', 'crunchy', 'aromatic', 'rich', 'light'] as const;
export type Taste = (typeof TASTES)[number];

export const MAIN_INGREDIENTS = ['chicken', 'mutton', 'seafood', 'egg', 'meat', 'paneer', 'mushroom', 'veg'] as const;
export type MainIngredient = (typeof MAIN_INGREDIENTS)[number];

export interface DishProfile {
  cuisine: string;
  foodFamily: string;
  dishGroup: string;
  mainIngredient: MainIngredient;
  tasteTags: Taste[];
  spiceLevel: 0 | 1 | 2 | 3;
  synonyms: string[];
}

/** Groups whose family is qualified by the main ingredient (chicken-biryani vs veg-biryani). */
const QUALIFIED_GROUPS = new Set(['biryani', 'rice', 'curry', 'noodles', 'momos', 'pizza', 'burger', 'wrap', 'kebab', 'haleem', 'bowl', 'starter', 'thali', 'pasta', 'puff']);

/** Ordered: first match wins. Tested against the lower-cased dish name. */
const GROUP_RULES: [RegExp, string][] = [
  [/biryani|biriyani/, 'biryani'],
  [/haleem/, 'haleem'],
  [/thali|\bmeals\b|banana leaf/, 'thali'],
  [/momo/, 'momos'],
  [/noodle|hakka|chow ?mein/, 'noodles'],
  [/pizza|margherita|pepperoni|calzone/, 'pizza'],
  [/pasta|penne|alfredo|spaghetti|arrabbiata|lasagn/, 'pasta'],
  [/burger/, 'burger'],
  [/wrap|(?<!brioche |cinnamon |swiss )roll\b|frankie|shawarma|kathi/, 'wrap'],
  [/\bbowl\b|salad/, 'bowl'],
  [/pulao|pulav|fried rice|rice|khichdi|bisi bele|bath\b/, 'rice'],
  [/dosa|uttapam|pesarattu/, 'dosa'],
  [/idli|vada(?! pav)/, 'idli-vada'],
  [/upma|pongal|poori|puri bhaji/, 'breakfast'],
  [/masala\b(?!.*(dosa|chai|fries|buttermilk|chaas|soda|peanut|papad))|curry|makhani|korma|rogan|kadai|butter chicken|\bdal\b|chole|palak|saag|kolhapuri|gravy|salan|nihari|paya/, 'curry'],
  [/manchurian|chilli|chili|crispy corn|\b65\b|lollipop/, 'starter'],
  [/sandwich|sourdough|toast/, 'snack'],
  [/naan|roti|paratha|kulcha|bread basket|rumali/, 'bread'],
  [/tikka|kebab|kabab|tandoor|seekh|tangdi|grill|shami|galouti/, 'kebab'],
  [/chaat|pani ?puri|golgappa|dahi puri|bhel|papdi|pav|tikki|ragda/, 'chaat'],
  [/puff/, 'puff'],
  [/meetha|jamun|halwa|kheer|phirni|kulfi|rasmalai|brownie|cake|ice cream|pastry|mithai|sundae|qubani|jalebi|ladoo|laddu|rabri|payasam|kunafa|shahi tukda/, 'dessert'],
  [/chai|coffee|\btea\b|lassi|shake|juice|soda|milk|buttermilk|lime|mojito|smoothie|cooler|lemonade|chaas/, 'beverage'],
  [/samosa|pakoda|pakora|bajji|fries|nuggets|biscuit|cookie|sandwich|toast|bun maska|khari|rusk|cutlet|spring roll|wedges/, 'snack'],
];

const CATEGORY_GROUP: Record<string, string> = {
  biryani: 'biryani', dosa: 'dosa', idli: 'idli-vada', 'telangana-andhra': 'thali', paneer: 'curry', 'indo-chinese': 'starter',
  kebabs: 'kebab', meals: 'thali', burgers: 'burger', pizza: 'pizza', pasta: 'pasta', bowls: 'bowl', chaat: 'chaat',
  bakery: 'snack', desserts: 'dessert', beverages: 'beverage',
};

const GROUP_CUISINE: Record<string, string> = {
  biryani: 'Hyderabadi', haleem: 'Hyderabadi', dosa: 'South Indian', 'idli-vada': 'South Indian', breakfast: 'South Indian',
  thali: 'Indian', curry: 'North Indian', kebab: 'Mughlai', bread: 'North Indian', noodles: 'Indo-Chinese', momos: 'Indo-Chinese',
  starter: 'Indo-Chinese', pizza: 'Italian', pasta: 'Italian', burger: 'Fast Food', wrap: 'Fast Food', bowl: 'Healthy',
  chaat: 'Street Food', snack: 'Snacks', puff: 'Bakery', dessert: 'Desserts', beverage: 'Beverages', rice: 'Indian',
};

const GROUP_SYNONYMS: Record<string, string[]> = {
  biryani: ['biryani', 'biriyani', 'briyani', 'dum biryani', 'rice'],
  haleem: ['haleem', 'harees'],
  rice: ['rice', 'pulao', 'pulav', 'rice bowl'],
  dosa: ['dosa', 'dosai', 'tiffin', 'breakfast'],
  'idli-vada': ['idli', 'vada', 'tiffin', 'breakfast'],
  breakfast: ['breakfast', 'tiffin'],
  thali: ['thali', 'meals', 'full meal', 'combo'],
  curry: ['curry', 'gravy', 'sabzi'],
  kebab: ['kebab', 'tandoori', 'tikka', 'grill', 'starter'],
  bread: ['bread', 'naan', 'roti'],
  noodles: ['noodles', 'chinese', 'chowmein'],
  momos: ['momos', 'momo', 'dumplings', 'dimsum'],
  starter: ['starter', 'chinese', 'appetizer'],
  pizza: ['pizza'],
  pasta: ['pasta'],
  burger: ['burger'],
  wrap: ['wrap', 'roll', 'kathi roll', 'frankie'],
  bowl: ['bowl', 'healthy', 'salad', 'protein bowl'],
  chaat: ['chaat', 'street food', 'snack'],
  snack: ['snack', 'evening snack'],
  puff: ['puff', 'bakery', 'snack'],
  dessert: ['dessert', 'sweet', 'mithai'],
  beverage: ['drink', 'beverage'],
};

const INGREDIENT_SYNONYMS: Record<MainIngredient, string[]> = {
  chicken: ['chicken', 'murgh'], mutton: ['mutton', 'lamb', 'gosht'], seafood: ['fish', 'prawn', 'seafood'],
  egg: ['egg', 'anda'], meat: ['meat', 'pork', 'beef'], paneer: ['paneer', 'cottage cheese'], mushroom: ['mushroom'], veg: ['veg', 'vegetarian'],
};

export function mainIngredientOf(text: string, isVegetarian: boolean): MainIngredient {
  const t = text.toLowerCase();
  if (!isVegetarian) {
    if (/mutton|lamb|gosht|keema|nihari|paya/.test(t)) return 'mutton';
    if (/chicken|murgh|tangdi/.test(t)) return 'chicken';
    if (/fish|prawn|seafood|apollo/.test(t)) return 'seafood';
    if (/pepperoni|bacon|pork|beef|\bham\b|salami|sausage/.test(t)) return 'meat';
    if (/\begg|anda|omelette/.test(t)) return 'egg';
    return 'chicken';
  }
  if (/paneer/.test(t)) return 'paneer';
  if (/mushroom/.test(t)) return 'mushroom';
  return 'veg';
}

export function groupOf(name: string, categoryId?: string): string {
  const n = name.toLowerCase();
  for (const [re, g] of GROUP_RULES) if (re.test(n)) return g;
  return (categoryId && CATEGORY_GROUP[categoryId]) || 'meal';
}

export function familyOf(group: string, main: MainIngredient) {
  return QUALIFIED_GROUPS.has(group) ? `${main}-${group}` : group;
}

export function tastesOf(name: string, description: string, group: string): Taste[] {
  const n = name.toLowerCase(), t = `${n} ${description.toLowerCase()}`;
  const tags = new Set<Taste>();
  const spicyRe = /spicy|\bhot\b|chilli|chili|schezwan|andhra|mirchi|peri peri|\b65\b|kolhapuri|pepper|karam|chettinad|zinger|guntur|vindaloo/;
  const sweetOrDrink = group === 'dessert' || group === 'beverage';
  if (!sweetOrDrink && (spicyRe.test(n) || /fiery|spicy/.test(t))) tags.add('spicy');
  if (/tangy|lemon|tamarind|imli|achari|\blime\b|manchurian|arrabbiata|chaat|pani ?puri|dahi puri|bhel|papdi|sambar|rasam|pickle/.test(t)) tags.add('tangy');
  if (group === 'dessert' || /\bsweet\b|meetha|jamun|honey|\bbbq\b|mango|jaggery/.test(n)) tags.add('sweet');
  if (/cream|malai|butter(?!milk)|makhani|alfredo|korma|lassi|shake|kulfi|rabri|cheese|mayo/.test(t)) tags.add('creamy');
  if (/tandoor|tikka|kebab|kabab|seekh|grill|\bbbq\b|charcoal|smoked|wood-fired|coal/.test(t)) tags.add('smoky');
  if (/crisp|crunch|fried|fries|pakoda|pakora|bajji|vada|puri|samosa|\b65\b|nugget|papdi|bhel|dosa|zinger|biscuit|puff/.test(t)) tags.add('crunchy');
  if (/biryani|pulao|\bdum\b|saffron|zafran|ghee|jeera|haleem|chai|filter coffee|cardamom|elaichi/.test(t)) tags.add('aromatic');
  if (/biryani|mutton|butter(?!milk)|makhani|ghee|cheese|haleem|rogan|double ka|nihari|korma|brownie|alfredo/.test(t)) tags.add('rich');
  if (/salad|idli|\bbowl\b|soup|sprout|steamed|grilled|quinoa|millet|ragi|buttermilk|chaas|lime soda|upma|curd rice|khichdi/.test(t)) tags.add('light');
  if (/malai|\bmild\b|plain|curd|korma|alfredo|kids/.test(t) && !tags.has('spicy')) tags.add('mild');
  if (group !== 'dessert' && group !== 'beverage') tags.add('savory');
  return TASTES.filter((x) => tags.has(x));
}

export function spiceOf(name: string, description: string, group: string, tastes: Taste[]): 0 | 1 | 2 | 3 {
  const t = `${name} ${description}`.toLowerCase();
  if (group === 'dessert' || group === 'beverage') return 0;
  if (/andhra|schezwan|mirchi|kolhapuri|\b65\b|karam|extra hot|guntur|chettinad|zinger|vindaloo|spicy|fiery/.test(name.toLowerCase())) return 3;
  if (tastes.includes('mild')) return 1;
  if (['biryani', 'curry', 'kebab', 'chaat', 'haleem', 'starter'].includes(group) || /chilli|chili|peri peri/.test(t)) return 2;
  if (['bread', 'snack', 'puff', 'pasta', 'pizza', 'bowl'].includes(group)) return /pepper|peri/.test(t) ? 2 : 1;
  return 1;
}

export function classifyDish(input: { name: string; description: string; categoryId?: string; isVegetarian: boolean }): DishProfile {
  const dishGroup = groupOf(input.name, input.categoryId);
  const mainIngredient = mainIngredientOf(`${input.name} ${dishGroup === 'meal' ? input.description : ''}`, input.isVegetarian);
  const tasteTags = tastesOf(input.name, input.description, dishGroup);
  const spiceLevel = spiceOf(input.name, input.description, dishGroup, tasteTags);
  if (spiceLevel >= 2 && !tasteTags.includes('spicy')) tasteTags.splice(0, 0, 'spicy');
  const synonyms = [...new Set([...(GROUP_SYNONYMS[dishGroup] ?? []), ...(QUALIFIED_GROUPS.has(dishGroup) ? INGREDIENT_SYNONYMS[mainIngredient] : [])])].slice(0, 12);
  const cuisine = /fried rice|schezwan/.test(input.name.toLowerCase()) ? 'Indo-Chinese' : GROUP_CUISINE[dishGroup] ?? 'Indian';
  return { cuisine, foodFamily: familyOf(dishGroup, mainIngredient), dishGroup, mainIngredient, tasteTags: TASTES.filter((t) => tasteTags.includes(t)), spiceLevel, synonyms };
}

/** Groups that customers treat as interchangeable meals (biryani ↔ pulao ↔ fried rice). */
const RELATED_GROUPS: Record<string, string[]> = {
  biryani: ['rice', 'haleem'], rice: ['biryani', 'noodles'], noodles: ['rice', 'momos'], momos: ['noodles', 'starter'],
  dosa: ['idli-vada', 'breakfast'], 'idli-vada': ['dosa', 'breakfast'], breakfast: ['dosa', 'idli-vada'],
  curry: ['thali', 'kebab'], thali: ['curry', 'rice'], kebab: ['starter', 'wrap', 'curry'], starter: ['kebab', 'momos'],
  pizza: ['pasta', 'burger'], pasta: ['pizza'], burger: ['wrap', 'pizza', 'snack'], wrap: ['burger', 'kebab'],
  chaat: ['snack'], snack: ['chaat', 'puff'], puff: ['snack'], bowl: ['rice'], haleem: ['biryani', 'curry'],
};

/**
 * 0..1 similarity between a requested family/group/ingredient and a dish profile.
 * 1 = same family; 0.75 = same group, different main ingredient (chicken→mutton biryani);
 * 0.6 = related group, same main ingredient (chicken biryani → chicken pulao).
 */
export function familySimilarity(
  want: { foodFamily?: string | null; dishGroup?: string | null; mainIngredient?: MainIngredient | null },
  dish: { foodFamily: string; dishGroup: string; mainIngredient: string },
): number {
  if (want.foodFamily && want.foodFamily === dish.foodFamily) return 1;
  const sameIngredient = !want.mainIngredient || want.mainIngredient === dish.mainIngredient;
  if (want.dishGroup && want.dishGroup === dish.dishGroup) return sameIngredient ? (want.foodFamily ? 0.9 : 1) : 0.75;
  if (want.dishGroup && RELATED_GROUPS[want.dishGroup]?.includes(dish.dishGroup)) return !want.mainIngredient ? 0.45 : sameIngredient ? 0.6 : 0.35;
  if (!want.dishGroup && want.mainIngredient) return want.mainIngredient === dish.mainIngredient ? 1 : 0;
  return 0;
}
