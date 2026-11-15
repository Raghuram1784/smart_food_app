/**
 * Recipe-based nutrition references by dish type (per stated serving, rounded: kcal to 10, grams to 1).
 *
 * These are APPROXIMATE values for a typical home/restaurant preparation of each kind of dish,
 * compiled from general nutrition references. They are stored with basis ESTIMATE and a source
 * note, never as measured values. A dish only gets a reference when an explicit rule below matches
 * its name/food family; anything unmatched stays without nutrition ("unavailable" in the app).
 */
export type Ref = { serving: string; grams: number; kcal: number; p: number; c: number; f: number };

export const FAMILY_SOURCE =
  'Estimate for a typical serving of this kind of dish (recipe-based reference, not measured for this kitchen). Verify against IFCT 2017 / USDA FoodData Central before relying on it.';

// prettier-ignore
export const FAMILY_REF: Record<string, Ref> = {
  familyChickenBiryani: { serving: '1 family pack (about 3 plates)', grams: 1050, kcal: 1800, p: 90, c: 210, f: 66 },
  paneerRiceBowl: { serving: '1 bowl', grams: 350, kcal: 520, p: 22, c: 62, f: 18 },
  lemonRice: { serving: '1 plate', grams: 200, kcal: 300, p: 5, c: 50, f: 9 },
  jeeraRice: { serving: '1 plate', grams: 200, kcal: 280, p: 5, c: 52, f: 6 },
  vegPulao: { serving: '1 plate', grams: 250, kcal: 330, p: 7, c: 55, f: 9 },
  khichdi: { serving: '1 bowl', grams: 250, kcal: 300, p: 11, c: 48, f: 7 },
  bisiBeleBath: { serving: '1 bowl', grams: 250, kcal: 330, p: 10, c: 52, f: 9 },
  gheeRoastDosa: { serving: '1 dosa', grams: 120, kcal: 260, p: 5, c: 32, f: 12 },
  uttapam: { serving: '1 uttapam', grams: 200, kcal: 300, p: 8, c: 46, f: 9 },
  pesarattu: { serving: '1 pesarattu', grams: 200, kcal: 280, p: 13, c: 40, f: 8 },
  ravaDosa: { serving: '1 dosa', grams: 150, kcal: 280, p: 5, c: 38, f: 12 },
  ragiDosa: { serving: '1 dosa', grams: 120, kcal: 200, p: 5, c: 34, f: 5 },
  sambarVada: { serving: '2 vadas in sambar', grams: 250, kcal: 330, p: 11, c: 34, f: 16 },
  pooriBhaji: { serving: '3 pooris with bhaji', grams: 250, kcal: 450, p: 9, c: 55, f: 22 },
  chickenThali: { serving: '1 thali', grams: 600, kcal: 850, p: 38, c: 100, f: 30 },
  muttonCurry: { serving: '1 bowl', grams: 250, kcal: 450, p: 32, c: 8, f: 32 },
  chole: { serving: '1 bowl', grams: 200, kcal: 260, p: 11, c: 34, f: 9 },
  mixVegCurry: { serving: '1 bowl', grams: 200, kcal: 220, p: 6, c: 18, f: 14 },
  eggCurry: { serving: '1 bowl with 2 eggs', grams: 250, kcal: 330, p: 18, c: 10, f: 24 },
  muttonSeekh: { serving: '6 pieces', grams: 180, kcal: 420, p: 30, c: 4, f: 32 },
  eggRoll: { serving: '1 roll', grams: 200, kcal: 400, p: 14, c: 42, f: 19 },
  vegWrap: { serving: '1 wrap', grams: 220, kcal: 380, p: 9, c: 50, f: 15 },
  paratha: { serving: '1 paratha', grams: 80, kcal: 260, p: 5, c: 36, f: 10 },
  kulcha: { serving: '1 stuffed kulcha', grams: 120, kcal: 320, p: 8, c: 48, f: 10 },
  paneerMomos: { serving: '6 pieces', grams: 180, kcal: 290, p: 12, c: 36, f: 11 },
  friedChickenMomos: { serving: '6 pieces', grams: 180, kcal: 400, p: 18, c: 36, f: 20 },
  gobiManchurian: { serving: '1 plate', grams: 200, kcal: 330, p: 6, c: 32, f: 20 },
  chilliPaneer: { serving: '1 plate', grams: 200, kcal: 380, p: 18, c: 18, f: 26 },
  chilliChicken: { serving: '1 plate', grams: 200, kcal: 400, p: 30, c: 18, f: 23 },
  vegPizza: { serving: '1 pizza, 8 inch', grams: 280, kcal: 680, p: 26, c: 82, f: 26 },
  chickenPizza: { serving: '1 pizza, 8 inch', grams: 280, kcal: 760, p: 36, c: 80, f: 32 },
  alfredoPasta: { serving: '1 plate', grams: 300, kcal: 620, p: 18, c: 70, f: 30 },
  redPasta: { serving: '1 plate', grams: 300, kcal: 450, p: 13, c: 72, f: 12 },
  chickenPasta: { serving: '1 plate', grams: 300, kcal: 600, p: 32, c: 68, f: 22 },
  chickenBurger: { serving: '1 burger', grams: 220, kcal: 520, p: 26, c: 45, f: 26 },
  paneerBurger: { serving: '1 burger', grams: 220, kcal: 540, p: 20, c: 50, f: 28 },
  greenSalad: { serving: '1 bowl', grams: 250, kcal: 220, p: 6, c: 18, f: 14 },
  quinoaBowl: { serving: '1 bowl', grams: 350, kcal: 480, p: 16, c: 62, f: 18 },
  fishBowl: { serving: '1 bowl', grams: 350, kcal: 480, p: 34, c: 50, f: 14 },
  eggBowl: { serving: '1 bowl', grams: 350, kcal: 450, p: 24, c: 45, f: 18 },
  bhelPuri: { serving: '1 plate', grams: 150, kcal: 280, p: 6, c: 46, f: 8 },
  dahiPapdi: { serving: '1 plate', grams: 200, kcal: 320, p: 8, c: 46, f: 12 },
  samosaChaat: { serving: '1 plate', grams: 250, kcal: 420, p: 10, c: 55, f: 18 },
  pakoda: { serving: '1 plate', grams: 150, kcal: 380, p: 8, c: 36, f: 23 },
  chickenNuggets: { serving: '6 pieces', grams: 110, kcal: 300, p: 15, c: 18, f: 18 },
  vegSandwich: { serving: '1 sandwich', grams: 180, kcal: 350, p: 10, c: 42, f: 15 },
  biscuits: { serving: '100 g', grams: 100, kcal: 480, p: 6, c: 62, f: 23 },
  vegPuff: { serving: '1 puff', grams: 90, kcal: 280, p: 5, c: 26, f: 17 },
  eggPuff: { serving: '1 puff', grams: 100, kcal: 300, p: 9, c: 25, f: 18 },
  chickenPuff: { serving: '1 puff', grams: 100, kcal: 320, p: 11, c: 25, f: 20 },
  muttonHaleem: { serving: '1 bowl', grams: 300, kcal: 480, p: 32, c: 30, f: 26 },
  chickenHaleem: { serving: '1 bowl', grams: 300, kcal: 420, p: 30, c: 30, f: 20 },
  kulfi: { serving: '1 kulfi', grams: 70, kcal: 180, p: 4, c: 20, f: 9 },
  rasmalai: { serving: '2 pieces', grams: 150, kcal: 330, p: 10, c: 34, f: 17 },
  brownie: { serving: '1 brownie', grams: 80, kcal: 370, p: 5, c: 48, f: 18 },
  phirni: { serving: '1 bowl', grams: 150, kcal: 220, p: 6, c: 32, f: 7 },
  doubleKaMeetha: { serving: '1 bowl', grams: 150, kcal: 420, p: 8, c: 55, f: 18 },
  qubani: { serving: '1 bowl', grams: 150, kcal: 300, p: 3, c: 60, f: 6 },
  coldCoffee: { serving: '1 glass, 300 ml', grams: 300, kcal: 300, p: 8, c: 40, f: 12 },
  mangoLassi: { serving: '1 glass, 250 ml', grams: 250, kcal: 290, p: 8, c: 46, f: 7 },
  buttermilk: { serving: '1 glass, 200 ml', grams: 200, kcal: 60, p: 3, c: 6, f: 2 },
  limeSoda: { serving: '1 glass, 300 ml, sweetened', grams: 300, kcal: 90, p: 0, c: 23, f: 0 },
  badamMilk: { serving: '1 glass, 250 ml', grams: 250, kcal: 260, p: 9, c: 32, f: 11 },
};

type P = { foodFamily: string; dishGroup: string; mainIngredient: string };

/**
 * Picks a reference key for a dish from explicit name rules within its food family.
 * Returns null when no rule clearly applies (nutrition then stays unavailable).
 */
export function referenceFor(name: string, p: P): string | null {
  const n = name.toLowerCase();
  const has = (re: RegExp) => re.test(n);
  const m = p.mainIngredient;
  switch (p.dishGroup) {
    case 'biryani':
      if (m === 'chicken') return has(/family|bucket|jumbo/) ? 'familyChickenBiryani' : has(/mini|half/) ? 'chickenBiryaniHalf' : 'chickenBiryani';
      if (m === 'mutton') return has(/family|bucket/) ? null : 'muttonBiryani';
      if (m === 'egg') return 'eggBiryani';
      if (m === 'paneer') return 'paneerBiryani';
      if (m === 'veg' || m === 'mushroom') return 'vegBiryani';
      return null;
    case 'rice':
      if (has(/fried rice|schezwan/)) return m === 'chicken' ? 'chickenFriedRice' : m === 'egg' ? 'eggFriedRice' : m === 'veg' ? 'vegFriedRice' : null;
      if (m === 'chicken' && has(/pulao/)) return 'chickenPulao';
      if (has(/curd rice|daddojanam/)) return 'curdRice';
      if (has(/lemon rice|pulihora|tamarind rice/)) return 'lemonRice';
      if (has(/jeera/)) return 'jeeraRice';
      if (has(/khichdi/)) return 'khichdi';
      if (has(/bisi bele/)) return 'bisiBeleBath';
      if (m === 'veg' && has(/pulao/)) return 'vegPulao';
      return null;
    case 'dosa':
      if (has(/masala|mysore/)) return 'masalaDosa';
      if (has(/ghee roast/)) return 'gheeRoastDosa';
      if (has(/uttapam/)) return 'uttapam';
      if (has(/pesarattu/)) return 'pesarattu';
      if (has(/rava/)) return 'ravaDosa';
      if (has(/ragi|millet/)) return 'ragiDosa';
      if (has(/plain|crisp|sada/)) return 'plainDosa';
      return null;
    case 'idli-vada':
      if (has(/sambar vada|dip sambar vada/)) return 'sambarVada';
      if (has(/idli/) && !has(/podi|fried|chilli/)) return 'idli';
      if (has(/vada/) && !has(/dahi/)) return 'vada';
      return null;
    case 'breakfast':
      if (has(/upma/)) return 'upma';
      if (has(/pongal/)) return 'pongal';
      if (has(/poori|puri/)) return 'pooriBhaji';
      return null;
    case 'thali':
      return m === 'chicken' ? 'chickenThali' : m === 'veg' || m === 'paneer' ? 'vegThali' : null;
    case 'curry':
      if (m === 'paneer') return 'paneerCurry';
      if (m === 'chicken') return has(/butter|makhani/) ? 'butterChicken' : 'chickenCurry';
      if (m === 'mutton') return 'muttonCurry';
      if (m === 'egg') return 'eggCurry';
      if (has(/dal makhani/)) return 'dalMakhani';
      if (has(/\bdal\b|tadka|pappu/)) return 'dal';
      if (has(/chole|chana/)) return 'chole';
      if (m === 'veg' && has(/veg|sabzi|kolhapuri|korma|kurma|mixed/)) return 'mixVegCurry';
      return null;
    case 'kebab':
      if (m === 'chicken') return has(/tandoori chicken/) ? 'tandooriChickenHalf' : has(/tikka|malai|kebab|kabab|tangdi|reshmi|seekh/) ? 'chickenTikka' : null;
      if (m === 'mutton') return has(/seekh|kebab|kabab/) ? 'muttonSeekh' : null;
      if (m === 'paneer') return 'paneerTikka';
      return null;
    case 'wrap':
      return m === 'chicken' ? 'chickenWrap' : m === 'paneer' ? 'paneerWrap' : m === 'egg' ? 'eggRoll' : m === 'veg' ? 'vegWrap' : null;
    case 'bread':
      if (has(/naan/)) return 'naan';
      if (has(/roti|rumali|phulka|chapati/)) return 'roti';
      if (has(/kulcha/)) return 'kulcha';
      if (has(/paratha/)) return 'paratha';
      return null;
    case 'noodles':
      return m === 'chicken' ? 'chickenNoodles' : m === 'veg' ? 'vegNoodles' : null;
    case 'momos':
      if (m === 'chicken') return has(/fried|crispy|pan/) ? 'friedChickenMomos' : 'chickenMomos';
      if (m === 'paneer') return 'paneerMomos';
      if (m === 'veg') return has(/fried|crispy/) ? null : 'vegMomos';
      return null;
    case 'starter':
      if (has(/65/) && m === 'chicken') return 'chicken65';
      if (has(/chilli|chili|manchurian/)) return m === 'chicken' ? 'chilliChicken' : m === 'paneer' ? 'chilliPaneer' : has(/gobi|cauliflower/) ? 'gobiManchurian' : null;
      return null;
    case 'pizza':
      if (has(/margherita/)) return 'margherita';
      return m === 'chicken' ? 'chickenPizza' : m === 'veg' || m === 'paneer' || m === 'mushroom' ? 'vegPizza' : null;
    case 'pasta':
      if (m === 'chicken') return 'chickenPasta';
      return has(/alfredo|cream|white/) ? 'alfredoPasta' : 'redPasta';
    case 'burger':
      if (m === 'chicken') return 'chickenBurger';
      if (m === 'paneer') return 'paneerBurger';
      if (m === 'meat') return 'cheeseburger';
      return m === 'veg' ? 'vegBurger' : null;
    case 'bowl':
      if (m === 'chicken') return has(/protein/) ? 'proteinChickenBowl' : has(/salad/) ? 'chickenSalad' : 'chickenRiceBowl';
      if (m === 'paneer') return 'paneerBowl';
      if (m === 'seafood') return 'fishBowl';
      if (m === 'egg') return 'eggBowl';
      if (has(/sprout/)) return 'sproutsSalad';
      if (has(/quinoa|falafel|grain/)) return 'quinoaBowl';
      if (has(/salad/)) return 'greenSalad';
      return null;
    case 'chaat':
      if (has(/pani ?puri|golgappa/)) return 'paniPuri';
      if (has(/pav bhaji/)) return 'pavBhaji';
      if (has(/vada pav/)) return 'vadaPav';
      if (has(/bhel/)) return 'bhelPuri';
      if (has(/dahi puri|papdi/)) return 'dahiPapdi';
      if (has(/samosa chaat|tikki|ragda/)) return 'samosaChaat';
      return null;
    case 'snack':
      if (has(/samosa/) && m === 'veg') return 'samosa';
      if (has(/fries/)) return 'frenchFries';
      if (has(/pakoda|pakora|bajji|bhajji|punugulu/)) return 'pakoda';
      if (has(/nugget/)) return 'chickenNuggets';
      if (has(/sandwich/) && m === 'veg') return 'vegSandwich';
      if (has(/biscuit|cookie/)) return 'biscuits';
      return null;
    case 'puff':
      return m === 'chicken' ? 'chickenPuff' : m === 'egg' ? 'eggPuff' : m === 'veg' ? 'vegPuff' : null;
    case 'haleem':
      return m === 'mutton' ? 'muttonHaleem' : m === 'chicken' ? 'chickenHaleem' : null;
    case 'dessert':
      if (has(/gulab jamun/)) return 'gulabJamun';
      if (has(/kulfi/)) return 'kulfi';
      if (has(/rasmalai/)) return 'rasmalai';
      if (has(/brownie/)) return 'brownie';
      if (has(/phirni|kheer/)) return 'phirni';
      if (has(/double ka meetha|shahi tukda/)) return 'doubleKaMeetha';
      if (has(/qubani/)) return 'qubani';
      return null;
    case 'beverage':
      if (has(/cold coffee|shake/)) return 'coldCoffee';
      if (has(/filter coffee|coffee/)) return 'filterCoffee';
      if (has(/mango lassi/)) return 'mangoLassi';
      if (has(/lassi/)) return 'sweetLassi';
      if (has(/buttermilk|chaas/)) return 'buttermilk';
      if (has(/lime soda|lemonade|nimbu/)) return 'limeSoda';
      if (has(/badam milk/)) return 'badamMilk';
      if (has(/chai|\btea\b/)) return 'masalaChai';
      return null;
    default:
      return null;
  }
}
