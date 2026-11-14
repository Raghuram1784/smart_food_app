/**
 * Idempotent catalog expansion for the synthetic development restaurants.
 *
 *   npx tsx prisma/seed_catalog_expansion.ts
 *
 * - Create-only upserts: existing (possibly edited) menu items, sections and
 *   nutrition rows are never overwritten; re-running adds nothing new.
 * - Every dish has an explicit vegetarian classification based on its listed
 *   ingredients (no inference from IDs, names of images or categories).
 * - Prices are illustrative demo values, not real restaurant prices.
 * - Nutrition: only for dishes that clearly match a reference preparation below.
 *   Values are ESTIMATES for the stated serving (see NUTRITION_SOURCE); dishes
 *   without a reference show "Nutrition unavailable" in the app.
 */
import 'dotenv/config';
import { createDatabase } from '../src/database/client';

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

export const NUTRITION_SOURCE =
  'Estimate for a typical recipe at the stated serving, compiled from general nutrition references; not measured for this kitchen. Verify against IFCT 2017 / USDA FoodData Central before relying on it.';

/** Approximate per-serving values, rounded (kcal to 10, grams to 1). */
export const NUTRITION_REF: Record<string, { serving: string; grams: number; kcal: number; p: number; c: number; f: number }> = {
  idli: { serving: '2 idlis with sambar', grams: 250, kcal: 220, p: 8, c: 40, f: 3 },
  vada: { serving: '2 medu vadas', grams: 100, kcal: 290, p: 9, c: 28, f: 16 },
  plainDosa: { serving: '1 plain dosa', grams: 100, kcal: 170, p: 4, c: 28, f: 5 },
  masalaDosa: { serving: '1 masala dosa', grams: 250, kcal: 380, p: 8, c: 55, f: 14 },
  upma: { serving: '1 bowl rava upma', grams: 200, kcal: 260, p: 6, c: 40, f: 8 },
  pongal: { serving: '1 bowl ven pongal', grams: 200, kcal: 300, p: 8, c: 42, f: 11 },
  vegBiryani: { serving: '1 plate', grams: 300, kcal: 450, p: 10, c: 70, f: 14 },
  chickenBiryani: { serving: '1 plate', grams: 350, kcal: 600, p: 30, c: 70, f: 22 },
  muttonBiryani: { serving: '1 plate', grams: 350, kcal: 680, p: 30, c: 70, f: 30 },
  eggBiryani: { serving: '1 plate with 2 eggs', grams: 350, kcal: 560, p: 22, c: 72, f: 20 },
  paneerCurry: { serving: '1 bowl', grams: 200, kcal: 400, p: 14, c: 14, f: 32 },
  dal: { serving: '1 bowl', grams: 200, kcal: 220, p: 10, c: 28, f: 7 },
  chickenCurry: { serving: '1 bowl', grams: 250, kcal: 400, p: 30, c: 10, f: 26 },
  chickenTikka: { serving: '6 pieces', grams: 180, kcal: 300, p: 38, c: 6, f: 13 },
  paneerTikka: { serving: '6 pieces', grams: 180, kcal: 380, p: 22, c: 10, f: 28 },
  naan: { serving: '1 butter naan', grams: 90, kcal: 290, p: 8, c: 45, f: 9 },
  roti: { serving: '1 tandoori roti', grams: 45, kcal: 120, p: 4, c: 24, f: 1 },
  margherita: { serving: '1 pizza, 8 inch', grams: 250, kcal: 600, p: 25, c: 75, f: 22 },
  cheeseburger: { serving: '1 burger', grams: 200, kcal: 520, p: 28, c: 40, f: 27 },
  vegBurger: { serving: '1 burger', grams: 200, kcal: 450, p: 12, c: 55, f: 20 },
  vegNoodles: { serving: '1 plate', grams: 250, kcal: 420, p: 9, c: 65, f: 13 },
  chickenFriedRice: { serving: '1 plate', grams: 300, kcal: 520, p: 22, c: 70, f: 16 },
  chicken65: { serving: '1 plate', grams: 150, kcal: 380, p: 28, c: 12, f: 25 },
  samosa: { serving: '2 samosas', grams: 140, kcal: 520, p: 8, c: 56, f: 30 },
  paniPuri: { serving: '6 puris', grams: 120, kcal: 210, p: 4, c: 34, f: 7 },
  chickenSalad: { serving: '1 bowl', grams: 300, kcal: 350, p: 32, c: 15, f: 18 },
  curdRice: { serving: '1 bowl', grams: 250, kcal: 300, p: 9, c: 45, f: 9 },
  masalaChai: { serving: '1 cup, 150 ml, with milk and sugar', grams: 150, kcal: 100, p: 3, c: 15, f: 3 },
  filterCoffee: { serving: '1 cup, 150 ml, with milk and sugar', grams: 150, kcal: 90, p: 3, c: 12, f: 3 },
  sweetLassi: { serving: '1 glass, 250 ml', grams: 250, kcal: 250, p: 8, c: 38, f: 7 },
  gulabJamun: { serving: '2 pieces', grams: 80, kcal: 300, p: 4, c: 45, f: 12 },
};

type Row = [restaurantId: string, key: string, name: string, description: string, categoryId: string, imageKey: string, rupees: number, section: string, veg: boolean, ref: string | null];

// prettier-ignore
export const DISHES: Row[] = [
  ['tiffin','ven-pongal','Ven Pongal','Rice and moong dal cooked with ghee, pepper, cumin and cashew.','idli','meals',140,'Tiffin favourites',true,'pongal'],
  ['tiffin','filter-coffee','Filter Coffee','South Indian decoction coffee with hot milk and sugar.','beverages','chai',60,'Comfort classics',true,'filterCoffee'],
  ['hearth','margherita','Margherita Pizza','Tomato sauce, mozzarella and fresh basil on a wood-fired base.','pizza','pizza',380,'From the oven',true,'margherita'],
  ['table','chicken-salad','Grilled Chicken Salad Bowl','Grilled chicken, greens, cucumber, tomato and lemon dressing.','bowls','salad',320,'Freshly prepared',false,'chickenSalad'],
  ['bun','veg-burger','Crispy Veg Burger','Potato and pea patty, lettuce, tomato and mayo in a toasted bun.','burgers','burger',180,'House favourites',true,'vegBurger'],
  ['deccan-handi-gachi','egg-biryani','Hyderabadi Egg Dum Biryani','Basmati rice dum-cooked with spiced boiled eggs and fried onions.','biryani','biryani',240,'Signature Dum Biryanis',false,'eggBiryani'],
  ['deccan-handi-gachi','dal-tadka','Dal Tadka','Yellow lentils tempered with ghee, garlic and cumin.','meals','dal-curry',160,'Sides & Accompaniments',true,'dal'],
  ['deccan-handi-gachi','gulab-jamun','Gulab Jamun','Two milk-solid dumplings in cardamom sugar syrup.','desserts','dessert',90,'Hyderabadi Desserts',true,'gulabJamun'],
  ['gachibowli-tiffin','rava-upma','Rava Upma','Semolina cooked with mustard, curry leaves, onion and vegetables.','idli','meals',90,'Dosas & Tiffins',true,'upma'],
  ['gachibowli-tiffin','plain-dosa','Plain Dosa','Crisp rice and urad dal crepe with chutney and sambar.','dosa','uttapam',80,'Dosas & Tiffins',true,'plainDosa'],
  ['gachibowli-tiffin','curd-rice','Curd Rice','Rice mixed with yogurt, tempered with mustard and curry leaves.','meals','meals',120,'Lunch Meals',true,'curdRice'],
  ['fd-smash-gachi','chicken-burger','Crispy Chicken Burger','Fried chicken thigh, slaw and pickles in a brioche bun.','burgers','burger',240,'Smash Burgers',false,null],
  ['fd-smash-gachi','veg-burger','Aloo Tikki Burger','Spiced potato tikki, onion and mint mayo.','burgers','burger',150,'Smash Burgers',true,'vegBurger'],
  ['fd-smash-gachi','choco-shake','Chocolate Shake','Chocolate ice cream blended with chilled milk.','beverages','cold-beverage',160,'Desserts & Shakes',true,null],
  ['cyberabad-wok-madhapur','veg-hakka','Veg Hakka Noodles','Wok-tossed noodles with cabbage, carrot, capsicum and soy.','indo-chinese','noodles',190,'Wok Noodles & Rice',true,'vegNoodles'],
  ['cyberabad-wok-madhapur','chicken-fried-rice','Chicken Fried Rice','Wok-fried rice with chicken, egg, spring onion and soy.','indo-chinese','noodles',230,'Wok Noodles & Rice',false,'chickenFriedRice'],
  ['cyberabad-wok-madhapur','gobi-manchurian','Gobi Manchurian','Crisp cauliflower tossed in garlic-soy Manchurian sauce.','indo-chinese','noodles',180,'Wok Starters',true,null],
  ['pind-handi-madhapur','dal-makhani','Dal Makhani','Black lentils slow-cooked with butter and cream.','paneer','dal-curry',220,'Dhaba Curries',true,'dal'],
  ['pind-handi-madhapur','butter-naan','Butter Naan','Tandoor-baked refined-flour bread brushed with butter.','meals','roti-naan',60,'Tandoor Breads',true,'naan'],
  ['pind-handi-madhapur','sweet-lassi','Sweet Lassi','Churned yogurt drink with sugar.','beverages','cold-beverage',90,'Beverages',true,'sweetLassi'],
  ['botanical-bowl-madhapur','chicken-salad','Lemon Herb Chicken Salad','Grilled chicken, mixed leaves, cucumber and lemon-herb dressing.','bowls','salad',340,'Fresh Salads',false,'chickenSalad'],
  ['botanical-bowl-madhapur','chana-bowl','Chickpea Quinoa Bowl','Quinoa, spiced chickpeas, greens and tahini dressing.','bowls','salad',300,'Signature Grain Bowls',true,null],
  ['woodstone-hitec','margherita','Classic Margherita','San Marzano-style tomato, mozzarella and basil.','pizza','pizza',360,'Stone-Baked Pizzas',true,'margherita'],
  ['woodstone-hitec','chicken-pesto-pasta','Chicken Pesto Penne','Penne with basil pesto, grilled chicken and parmesan.','pasta','pasta',380,'Artisan Pastas',false,null],
  ['woodstone-hitec','arrabbiata','Penne Arrabbiata','Penne in spicy tomato and garlic sauce.','pasta','pasta',300,'Artisan Pastas',true,null],
  ['charcoal-hitec','chicken-tikka','Chicken Tikka','Yogurt-marinated chicken chunks grilled on charcoal.','kebabs','kebab',320,'Charcoal Specialties',false,'chickenTikka'],
  ['charcoal-hitec','paneer-tikka','Paneer Tikka','Cottage cheese cubes marinated in spiced yogurt and grilled.','kebabs','paneer',280,'Vegetarian Grills',true,'paneerTikka'],
  ['charcoal-hitec','rumali-roti','Tandoori Roti','Whole-wheat flatbread baked in the tandoor.','meals','roti-naan',35,'Biryani & Breads',true,'roti'],
  ['oven-crumb-kondapur','veg-puff','Vegetable Puff','Flaky pastry filled with spiced mixed vegetables.','bakery','bakery',50,'Morning Bakes',true,null],
  ['oven-crumb-kondapur','egg-puff','Egg Puff','Flaky pastry with half a boiled egg in onion masala.','bakery','bakery',60,'Morning Bakes',false,null],
  ['oven-crumb-kondapur','cappuccino','Cappuccino','Espresso with steamed and foamed milk.','beverages','chai',140,'Coffee Bar',true,null],
  ['chaat-mandi-kondapur','samosa','Punjabi Samosa (2 pcs)','Pastry with spiced potato and peas, mint chutney.','chaat','chaat',60,'Hot Street Plates',true,'samosa'],
  ['chaat-mandi-kondapur','pani-puri','Pani Puri (6 pcs)','Crisp puris with potato, tangy mint water and tamarind.','chaat','chaat',50,'Chaat Classics',true,'paniPuri'],
  ['chaat-mandi-kondapur','masala-chai','Masala Chai','Tea brewed with milk, sugar, ginger and cardamom.','beverages','chai',30,'Hot Chai',true,'masalaChai'],
  ['kaveri-veg-biryani-kuka','veg-dum-biryani','Classic Veg Dum Biryani','Basmati and seasonal vegetables dum-cooked with saffron.','biryani','biryani',220,'Pure Veg Dum Biryanis',true,'vegBiryani'],
  ['kaveri-veg-biryani-kuka','paneer-65','Paneer 65','Fried paneer tossed with curry leaves and chilli.','paneer','paneer',210,'Starters & Sides',true,null],
  ['kaveri-veg-biryani-kuka','gulab-jamun','Gulab Jamun','Two milk-solid dumplings in sugar syrup.','desserts','dessert',80,'Desserts',true,'gulabJamun'],
  ['suprabhat-tiffins-kuka','idli','Idli Sambar (2 pcs)','Steamed rice-lentil cakes with sambar and coconut chutney.','idli','idli',70,'Idli & Vada',true,'idli'],
  ['suprabhat-tiffins-kuka','masala-dosa','Masala Dosa','Crisp dosa with potato masala, chutney and sambar.','dosa','dosa',110,'Tiffin Specials',true,'masalaDosa'],
  ['suprabhat-tiffins-kuka','filter-coffee','Filter Coffee','Decoction coffee with milk and sugar.','beverages','chai',40,'Beverages',true,'filterCoffee'],
  ['crunch-box-kuka','veg-burger','Crunchy Veg Burger','Vegetable patty, lettuce and tangy sauce.','burgers','burger',140,'Burgers & Combos',true,'vegBurger'],
  ['crunch-box-kuka','chicken-wrap','Peri Peri Chicken Wrap','Grilled peri peri chicken, onion and lettuce in a tortilla.','burgers','burger',190,'Wraps & Sides',false,null],
  ['crunch-box-kuka','oreo-shake','Cookies & Cream Shake','Vanilla ice cream blended with chocolate cookies and milk.','beverages','cold-beverage',170,'Shakes',true,null],
  ['kesar-clove-jubilee','chicken-curry','Murgh Makhani','Chicken in a buttery tomato and cashew gravy.','meals','dal-curry',380,'Royal Curries',false,'chickenCurry'],
  ['kesar-clove-jubilee','paneer-butter-masala','Paneer Butter Masala','Paneer in a rich tomato, butter and cream gravy.','paneer','paneer',340,'Royal Curries',true,'paneerCurry'],
  ['kesar-clove-jubilee','butter-naan','Butter Naan','Tandoor-baked naan with butter.','meals','roti-naan',70,'Tandoor Breads',true,'naan'],
  ['zafran-mithai-jubilee','gulab-jamun','Gulab Jamun (2 pcs)','Milk-solid dumplings soaked in rose-cardamom syrup.','desserts','dessert',90,'Classic Mithai',true,'gulabJamun'],
  ['zafran-mithai-jubilee','masala-chai','Masala Chai','Spiced milk tea.','beverages','chai',40,'Artisanal Chai',true,'masalaChai'],
  ['prana-bowls-jubilee','chicken-salad','Protein Chicken Salad','Grilled chicken breast, greens, sprouts and yogurt dressing.','bowls','salad',360,'High-Protein Bowls',false,'chickenSalad'],
  ['prana-bowls-jubilee','paneer-bowl','Grilled Paneer Power Bowl','Brown rice, grilled paneer, beans and vegetables.','bowls','salad',320,'High-Protein Bowls',true,null],
  ['banjara-courtyard','chicken-biryani','Chicken Dum Biryani','Basmati rice dum-cooked with marinated chicken.','biryani','chicken-biryani',320,'Hyderabadi Mains',false,'chickenBiryani'],
  ['banjara-courtyard','margherita','Margherita Pizza','Tomato, mozzarella and basil.','pizza','pizza',360,'Continental Grill',true,'margherita'],
  ['banjara-courtyard','masala-dosa','Masala Dosa','Dosa with potato masala.','dosa','dosa',140,'South Indian',true,'masalaDosa'],
  ['koyla-seekh-banjara','chicken-tikka','Angara Chicken Tikka','Smoky charcoal-grilled chicken tikka.','kebabs','kebab',330,'Charcoal Kebabs',false,'chickenTikka'],
  ['koyla-seekh-banjara','paneer-tikka','Achari Paneer Tikka','Paneer in pickle-spiced marinade, grilled.','kebabs','paneer',290,'Vegetarian Tandoor',true,'paneerTikka'],
  ['koyla-seekh-banjara','tandoori-roti','Tandoori Roti','Whole-wheat tandoor flatbread.','meals','roti-naan',35,'Rolls & Breads',true,'roti'],
  ['deccan-leaf-ameerpet','chicken-65','Chicken 65','Deep-fried spiced chicken with curry leaves.','telangana-andhra','kebab',260,'Regional Starters',false,'chicken65'],
  ['deccan-leaf-ameerpet','curd-rice','Andhra Curd Rice','Yogurt rice with tempering and pomegranate.','telangana-andhra','meals',130,'Comfort Rice Bowls',true,'curdRice'],
  ['deccan-leaf-ameerpet','buttermilk','Spiced Buttermilk','Thin salted yogurt drink with ginger and curry leaves.','beverages','cold-beverage',50,'Beverages',true,null],
  ['begum-chaat-ameerpet','pani-puri','Pani Puri (6 pcs)','Puris with potato and spiced water.','chaat','chaat',50,'Puri Classics',true,'paniPuri'],
  ['begum-chaat-ameerpet','samosa','Samosa (2 pcs)','Potato-pea samosas with chutney.','chaat','chaat',60,'Hot Chaat',true,'samosa'],
  ['begum-chaat-ameerpet','masala-chai','Masala Chai','Spiced milk tea.','beverages','chai',30,'Beverages',true,'masalaChai'],
  ['golconda-zafran-mehdi','mutton-biryani','Kacchi Mutton Biryani','Raw-marinated mutton and basmati dum-cooked together.','biryani','mutton-biryani',380,'Copper Deg Biryanis',false,'muttonBiryani'],
  ['golconda-zafran-mehdi','veg-biryani','Subz Dum Biryani','Mixed vegetables and basmati dum-cooked with saffron.','biryani','biryani',240,'Vegetarian Biryanis',true,'vegBiryani'],
  ['golconda-zafran-mehdi','chicken-65','Chicken 65','Spiced fried chicken starter.','kebabs','kebab',250,'Old City Starters',false,'chicken65'],
  ['irani-bakery-mehdi','irani-chai','Irani Chai','Slow-brewed tea with thickened milk and sugar.','beverages','chai',30,'Chai & Café',true,'masalaChai'],
  ['irani-bakery-mehdi','veg-puff','Vegetable Puff','Flaky pastry with spiced vegetables.','bakery','bakery',40,'Savoury Bakes',true,null],
  ['irani-bakery-mehdi','chicken-puff','Chicken Puff','Flaky pastry with spiced chicken filling.','bakery','bakery',55,'Savoury Bakes',false,null],
  ['dakshin-sunrise-secund','pongal','Ven Pongal','Rice and moong dal with ghee, pepper and cashew.','idli','meals',90,'Breakfast Specials',true,'pongal'],
  ['dakshin-sunrise-secund','medu-vada','Medu Vada (2 pcs)','Crisp urad dal fritters with sambar and chutney.','idli','vada',70,'Idli & Vada',true,'vada'],
  ['dakshin-sunrise-secund','filter-coffee','Filter Coffee','Decoction coffee with milk and sugar.','beverages','chai',40,'Hot Beverages',true,'filterCoffee'],
  ['clock-tower-secund','dal-tadka','Dal Tadka','Yellow lentils tempered with garlic and cumin.','meals','dal-curry',140,'Homestyle Curries',true,'dal'],
  ['clock-tower-secund','chicken-curry','Home-style Chicken Curry','Chicken simmered in onion-tomato masala.','meals','dal-curry',240,'Homestyle Curries',false,'chickenCurry'],
  ['clock-tower-secund','tandoori-roti','Tandoori Roti','Whole-wheat tandoor flatbread.','meals','roti-naan',25,'Breads',true,'roti'],
];

/** Explicit classification + nutrition for the original base dishes (replaces ID-list inference). */
// prettier-ignore
export const BASE_DISH_FACTS: Record<string, { veg: boolean; basis: string; ref: string | null }> = {
  pizza: { veg: false, basis: 'pepperoni (pork/beef sausage)', ref: null },
  burger: { veg: false, basis: 'beef patty and bacon', ref: 'cheeseburger' },
  pasta: { veg: true, basis: 'tomato, basil, penne', ref: null },
  salad: { veg: true, basis: 'vegetables, feta, olives', ref: null },
  dosa: { veg: true, basis: 'rice batter, potato masala', ref: 'masalaDosa' },
  idli: { veg: true, basis: 'rice-lentil batter, vegetables', ref: 'idli' },
  biryani: { veg: true, basis: 'rice and vegetables', ref: 'vegBiryani' },
  paneer: { veg: true, basis: 'paneer and pepper gravy', ref: null },
};

export async function expandCatalog(db: ReturnType<typeof createDatabase>) {
  let created = 0, nutrition = 0;
  await db.$transaction(async (tx) => {
    const restaurants = new Set((await tx.restaurant.findMany({ select: { id: true } })).map((r) => r.id));
    const categories = new Set((await tx.category.findMany({ select: { id: true } })).map((c) => c.id));
    for (const [i, [restaurantId, key, name, description, categoryId, imageKey, rupees, section, veg, ref]] of DISHES.entries()) {
      if (!restaurants.has(restaurantId) || !categories.has(categoryId)) continue; // never create orphans
      const sectionId = `${restaurantId}-${slug(section)}`;
      const existingSection = await tx.menuSection.findFirst({ where: { restaurantId, name: section } });
      const sid = existingSection?.id ?? sectionId;
      if (!existingSection) await tx.menuSection.create({ data: { id: sid, restaurantId, name: section, displayOrder: 50 } });
      const id = `x-${restaurantId}-${key}`.slice(0, 64);
      const exists = await tx.menuItem.findUnique({ where: { id }, select: { id: true } });
      if (!exists) {
        await tx.menuItem.create({
          data: { id, restaurantId, categoryId, sectionId: sid, name, description, imageKey, basePricePaise: rupees * 100, isVegetarian: veg, displayOrder: 100 + i },
        });
        created++;
      }
      if (ref) nutrition += await addNutrition(tx, id, ref);
    }
    for (const [id, f] of Object.entries(BASE_DISH_FACTS)) {
      if (f.ref && (await tx.menuItem.findUnique({ where: { id }, select: { id: true } }))) nutrition += await addNutrition(tx, id, f.ref);
    }
  }, { timeout: 60000 });
  return { created, nutrition };
}

async function addNutrition(tx: any, menuItemId: string, ref: string) {
  const n = NUTRITION_REF[ref];
  if (!n) throw new Error(`Unknown nutrition reference ${ref}`);
  const existing = await tx.menuItemNutrition.findUnique({ where: { menuItemId } });
  if (existing) return 0; // create-only: never overwrite curated values
  await tx.menuItemNutrition.create({
    data: { menuItemId, servingDescription: n.serving, servingGrams: n.grams, caloriesKcal: n.kcal, proteinG: n.p, carbsG: n.c, fatG: n.f, basis: 'ESTIMATE', source: NUTRITION_SOURCE },
  });
  return 1;
}

if (require.main === module) {
  const url = process.env.DATABASE_URL!;
  const db = createDatabase(url);
  expandCatalog(db)
    .then((r) => console.log(JSON.stringify({ event: 'catalog_expanded', database: new URL(url).pathname.slice(1), ...r })))
    .catch((e) => { console.error(e instanceof Error ? e.message : e); process.exitCode = 1; })
    .finally(() => db.$disconnect());
}
