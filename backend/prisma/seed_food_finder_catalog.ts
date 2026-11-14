/**
 * F1 Smart Food Finder catalog: grows the synthetic demo catalog to ~500 items and
 * profiles EVERY menu item (food family, taste tags, spice level, synonyms).
 *
 *   npx tsx prisma/seed_food_finder_catalog.ts            (dev DB from DATABASE_URL)
 *
 * Safety
 * - Create-only. Existing items, prices, sections, nutrition and profiles are never
 *   modified or deleted, so historical orders, carts and favourites stay intact.
 * - A dish is skipped when its restaurant already sells a dish with the same name.
 * - Restaurants are synthetic demo kitchens; prices are illustrative, not real menus.
 * - Nutrition only where a dish matches a reference preparation; values are labelled
 *   ESTIMATE with the source note. Everything else stays null ("Nutrition unavailable").
 */
import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import { classifyDish, TASTES, type Taste } from '../src/modules/food-finder/food-taxonomy';
import { NUTRITION_REF as BASE_REF, NUTRITION_SOURCE } from './seed_catalog_expansion';

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

/** Additional approximate per-serving references (rounded; kcal to 10, grams to 1). */
export const EXTRA_REF: Record<string, { serving: string; grams: number; kcal: number; p: number; c: number; f: number }> = {
  chickenBiryaniHalf: { serving: '1 half plate', grams: 200, kcal: 350, p: 17, c: 40, f: 13 },
  paneerBiryani: { serving: '1 plate', grams: 300, kcal: 560, p: 18, c: 68, f: 22 },
  chickenPulao: { serving: '1 plate', grams: 300, kcal: 480, p: 24, c: 60, f: 15 },
  eggFriedRice: { serving: '1 plate', grams: 300, kcal: 450, p: 15, c: 65, f: 14 },
  vegFriedRice: { serving: '1 plate', grams: 300, kcal: 400, p: 8, c: 68, f: 10 },
  chickenRiceBowl: { serving: '1 bowl', grams: 350, kcal: 520, p: 35, c: 55, f: 14 },
  dalMakhani: { serving: '1 bowl', grams: 200, kcal: 300, p: 11, c: 26, f: 17 },
  butterChicken: { serving: '1 bowl', grams: 250, kcal: 490, p: 30, c: 12, f: 36 },
  vegThali: { serving: '1 thali (rice, 2 rotis, dal, 2 sabzis, curd)', grams: 550, kcal: 720, p: 20, c: 105, f: 22 },
  chickenNoodles: { serving: '1 plate', grams: 300, kcal: 520, p: 24, c: 62, f: 18 },
  vegMomos: { serving: '6 pieces', grams: 180, kcal: 260, p: 8, c: 40, f: 7 },
  chickenMomos: { serving: '6 pieces', grams: 180, kcal: 300, p: 18, c: 34, f: 9 },
  paneerWrap: { serving: '1 wrap', grams: 220, kcal: 450, p: 18, c: 45, f: 22 },
  chickenWrap: { serving: '1 roll', grams: 220, kcal: 430, p: 26, c: 40, f: 18 },
  tandooriChickenHalf: { serving: 'half chicken, about 4 pieces', grams: 250, kcal: 380, p: 45, c: 6, f: 19 },
  proteinChickenBowl: { serving: '1 bowl', grams: 400, kcal: 560, p: 45, c: 50, f: 16 },
  paneerBowl: { serving: '1 bowl', grams: 380, kcal: 520, p: 28, c: 45, f: 24 },
  sproutsSalad: { serving: '1 bowl', grams: 200, kcal: 180, p: 12, c: 28, f: 3 },
  vadaPav: { serving: '1 vada pav', grams: 150, kcal: 300, p: 7, c: 42, f: 12 },
  pavBhaji: { serving: '2 pavs with bhaji', grams: 350, kcal: 560, p: 13, c: 70, f: 25 },
  frenchFries: { serving: '1 medium portion', grams: 120, kcal: 370, p: 4, c: 46, f: 18 },
};
export const ALL_REF = { ...BASE_REF, ...EXTRA_REF };

/** [key, name, description, categoryId, imageKey, rupees, veg, nutritionRef, curated tastes, spice 0-3] */
type T = [string, string, string, string, string, number, boolean, string | null, string, number];

// prettier-ignore
export const TEMPLATES: T[] = [
  // Biryani & rice
  ['mini-chicken-biryani','Mini Chicken Dum Biryani','Half portion of chicken dum biryani with mirchi salan and raita.','biryani','chicken-biryani',109,false,'chickenBiryaniHalf','spicy aromatic savory',2],
  ['chicken-dum-biryani','Chicken Dum Biryani','Basmati rice and marinated chicken slow-cooked on dum with saffron and fried onions.','biryani','chicken-biryani',189,false,'chickenBiryani','spicy aromatic rich savory',2],
  ['hyd-chicken-biryani','Hyderabadi Chicken Biryani','Kacchi-style chicken biryani with mint, saffron and whole spices.','biryani','chicken-biryani',229,false,'chickenBiryani','spicy aromatic rich savory',2],
  ['spicy-chicken-biryani','Spicy Andhra Chicken Biryani','Fiery Guntur-chilli chicken biryani for spice lovers.','biryani','chicken-biryani',199,false,'chickenBiryani','spicy aromatic savory',3],
  ['chicken-65-biryani','Chicken 65 Biryani','Biryani rice layered with crisp, spicy chicken 65.','biryani','chicken-biryani',219,false,null,'spicy crunchy aromatic savory',3],
  ['mutton-dum-biryani','Mutton Dum Biryani','Tender goat meat and basmati rice dum-cooked with saffron.','biryani','mutton-biryani',299,false,'muttonBiryani','spicy aromatic rich savory',2],
  ['egg-biryani','Egg Dum Biryani','Basmati rice dum-cooked with spiced boiled eggs.','biryani','biryani',139,false,'eggBiryani','spicy aromatic savory',2],
  ['veg-dum-biryani','Veg Dum Biryani','Seasonal vegetables and basmati rice cooked on dum with mint.','biryani','biryani',159,true,'vegBiryani','aromatic savory mild',1],
  ['paneer-biryani','Paneer Tikka Biryani','Smoky paneer tikka layered with saffron basmati rice.','biryani','biryani',199,true,'paneerBiryani','spicy smoky aromatic savory',2],
  ['mushroom-biryani','Mushroom Biryani','Button mushrooms and basmati rice with whole spices.','biryani','biryani',179,true,null,'spicy aromatic savory',2],
  ['chicken-pulao','Chicken Pulao','Mildly spiced chicken and rice cooked together in stock.','biryani','chicken-biryani',129,false,'chickenPulao','mild aromatic savory',1],
  ['chicken-schezwan-rice','Chicken Schezwan Fried Rice','Wok-tossed rice with chicken and fiery schezwan sauce.','indo-chinese','noodles',149,false,'chickenFriedRice','spicy tangy savory',3],
  ['chicken-fried-rice','Chicken Fried Rice','Wok-fried rice with chicken, egg and spring onion.','indo-chinese','noodles',139,false,'chickenFriedRice','savory mild',1],
  ['egg-fried-rice','Egg Fried Rice','Wok-fried rice with scrambled egg and vegetables.','indo-chinese','noodles',119,false,'eggFriedRice','savory mild',1],
  ['veg-fried-rice','Veg Fried Rice','Wok-fried rice with carrot, beans, cabbage and spring onion.','indo-chinese','noodles',109,true,'vegFriedRice','savory mild light',1],
  ['jeera-rice','Jeera Rice','Basmati rice tempered with cumin and ghee.','meals','meals',99,true,null,'aromatic mild light',0],
  ['veg-pulao','Veg Pulao','Basmati rice with peas, carrot and whole spices.','meals','meals',119,true,null,'aromatic mild savory',1],
  ['bisi-bele-bath','Bisi Bele Bath','Karnataka rice-lentil dish with vegetables, tamarind and spice powder.','meals','meals',119,true,null,'spicy tangy savory',2],
  ['lemon-rice','Lemon Rice','Rice tempered with mustard, peanuts, curry leaves and lemon.','meals','meals',89,true,null,'tangy light savory',1],
  ['chicken-rice-bowl','Grilled Chicken Rice Bowl','Grilled chicken, brown rice, sautéed vegetables and mint chutney.','bowls','salad',199,false,'chickenRiceBowl','smoky savory light',1],
  // South Indian breakfast
  ['masala-dosa','Masala Dosa','Crisp rice crepe with potato masala, chutney and sambar.','dosa','dosa',99,true,'masalaDosa','crunchy savory',1],
  ['mysore-masala-dosa','Mysore Masala Dosa','Dosa spread with red chilli-garlic chutney and potato masala.','dosa','dosa',119,true,'masalaDosa','spicy crunchy savory',2],
  ['ghee-roast-dosa','Ghee Roast Dosa','Paper-thin dosa roasted crisp in ghee.','dosa','dosa',129,true,null,'crunchy rich aromatic',1],
  ['onion-uttapam','Onion Uttapam','Thick rice pancake topped with onion, chilli and coriander.','dosa','uttapam',99,true,null,'savory',1],
  ['pesarattu','Pesarattu Upma','Andhra green moong crepe filled with upma.','dosa','uttapam',109,true,null,'savory light',1],
  ['ragi-dosa','Ragi Dosa','Finger-millet dosa with coconut chutney.','dosa','dosa',99,true,null,'light savory',1],
  ['idli-sambar','Idli Sambar','Two steamed rice idlis with sambar and chutney.','idli','idli',59,true,'idli','light mild tangy',1],
  ['rava-idli','Rava Idli','Semolina idlis with cashew and curry leaves.','idli','idli',79,true,null,'light mild',1],
  ['medu-vada','Medu Vada','Two crisp urad dal vadas with chutney and sambar.','idli','vada',69,true,'vada','crunchy savory',1],
  ['sambar-vada','Sambar Vada','Medu vadas soaked in hot sambar.','idli','vada',79,true,null,'tangy savory',1],
  ['poori-bhaji','Poori Bhaji','Three puffed pooris with potato bhaji.','idli','meals',99,true,null,'savory',1],
  // North Indian
  ['paneer-butter-masala','Paneer Butter Masala','Paneer cubes in a buttery tomato-cashew gravy.','paneer','paneer',219,true,'paneerCurry','creamy rich mild savory',1],
  ['kadai-paneer','Kadai Paneer','Paneer with capsicum and onion in kadai masala.','paneer','paneer',229,true,'paneerCurry','spicy savory',2],
  ['palak-paneer','Palak Paneer','Paneer in a smooth spinach gravy.','paneer','paneer',209,true,null,'mild creamy savory',1],
  ['dal-makhani','Dal Makhani','Black lentils slow-cooked with butter and cream.','paneer','dal-curry',189,true,'dalMakhani','creamy rich mild',1],
  ['chole','Amritsari Chole','Chickpeas in a tangy, spiced onion-tomato gravy.','paneer','dal-curry',169,true,null,'spicy tangy savory',2],
  ['veg-kolhapuri','Veg Kolhapuri','Mixed vegetables in a hot Kolhapuri masala.','paneer','paneer',199,true,null,'spicy savory',3],
  ['butter-chicken','Butter Chicken','Tandoori chicken in a creamy tomato-butter gravy.','kebabs','paneer',279,false,'butterChicken','creamy rich mild savory',1],
  ['chicken-tikka-masala','Chicken Tikka Masala','Charred chicken tikka in a spiced onion-tomato masala.','kebabs','paneer',289,false,'chickenCurry','spicy smoky creamy savory',2],
  ['kadai-chicken','Kadai Chicken','Chicken tossed with peppers in a hot kadai masala.','kebabs','paneer',269,false,'chickenCurry','spicy savory',3],
  ['mutton-rogan-josh','Mutton Rogan Josh','Kashmiri-style goat curry with whole spices.','kebabs','paneer',339,false,null,'spicy aromatic rich',2],
  ['butter-naan','Butter Naan','Tandoor-baked naan brushed with butter.','paneer','roti-naan',49,true,'naan','rich mild',0],
  ['tandoori-roti','Tandoori Roti','Whole-wheat flatbread from the tandoor.','paneer','roti-naan',29,true,'roti','light mild',0],
  ['garlic-naan','Garlic Naan','Naan topped with garlic and coriander.','paneer','roti-naan',59,true,null,'aromatic savory',0],
  // Thalis
  ['veg-thali','Veg Mini Thali','Rice, two rotis, dal, two sabzis, curd and pickle.','meals','meals',149,true,'vegThali','savory mild',1],
  ['north-thali','North Indian Veg Thali','Paneer curry, dal, jeera rice, two rotis, salad and dessert.','meals','meals',199,true,null,'savory rich',1],
  ['chicken-thali','Chicken Curry Thali','Chicken curry, rice, two rotis, dal and salad.','meals','meals',229,false,null,'spicy savory',2],
  ['andhra-meals','Andhra Veg Meals','Rice, pappu, two curries, rasam, sambar, curd and gongura pickle.','telangana-andhra','meals',179,true,null,'spicy tangy savory',3],
  // Indo-Chinese & momos
  ['veg-hakka-noodles','Veg Hakka Noodles','Wok-tossed noodles with crunchy vegetables.','indo-chinese','noodles',139,true,'vegNoodles','savory light',1],
  ['chicken-hakka-noodles','Chicken Hakka Noodles','Wok-tossed noodles with chicken and vegetables.','indo-chinese','noodles',169,false,'chickenNoodles','savory',1],
  ['schezwan-noodles','Veg Schezwan Noodles','Noodles tossed in hot schezwan sauce.','indo-chinese','noodles',149,true,null,'spicy tangy savory',3],
  ['chilli-chicken','Chilli Chicken','Crisp chicken tossed with green chilli, capsicum and soy.','indo-chinese','kebab',219,false,null,'spicy tangy crunchy savory',3],
  ['gobi-manchurian','Gobi Manchurian','Crisp cauliflower in tangy Manchurian sauce.','indo-chinese','noodles',159,true,null,'tangy crunchy spicy savory',2],
  ['chilli-paneer','Chilli Paneer','Paneer tossed with chilli, capsicum and soy.','indo-chinese','paneer',199,true,null,'spicy tangy savory',2],
  ['veg-momos','Steamed Veg Momos','Six steamed dumplings with vegetable filling and red chutney.','indo-chinese','noodles',99,true,'vegMomos','light savory',1],
  ['chicken-momos','Steamed Chicken Momos','Six steamed chicken dumplings with spicy red chutney.','indo-chinese','noodles',129,false,'chickenMomos','savory light',1],
  ['fried-chicken-momos','Fried Chicken Momos','Six crisp-fried chicken dumplings.','indo-chinese','noodles',149,false,null,'crunchy spicy savory',2],
  ['paneer-momos','Paneer Momos','Six steamed paneer and onion dumplings.','indo-chinese','noodles',119,true,null,'mild savory',1],
  // Pizza & pasta
  ['farmhouse-pizza','Farmhouse Veg Pizza','Onion, capsicum, tomato, mushroom and mozzarella.','pizza','pizza',349,true,null,'savory rich',1],
  ['paneer-tikka-pizza','Paneer Tikka Pizza','Tandoori paneer, onion and capsicum on mozzarella.','pizza','pizza',379,true,null,'spicy smoky savory',2],
  ['chicken-tikka-pizza','Chicken Tikka Pizza','Chicken tikka, onion and jalapeño on mozzarella.','pizza','pizza',419,false,null,'spicy smoky savory',2],
  ['bbq-chicken-pizza','BBQ Chicken Pizza','Smoky barbecue chicken, onion and mozzarella.','pizza','pizza',429,false,null,'smoky sweet savory',1],
  ['mini-margherita','Personal Margherita Pizza','7-inch margherita with tomato, mozzarella and basil.','pizza','pizza',199,true,null,'savory mild',0],
  ['penne-arrabbiata','Penne Arrabbiata','Penne in a spicy garlic-tomato sauce.','pasta','pasta',249,true,null,'spicy tangy savory',2],
  ['alfredo','Creamy Alfredo Pasta','Penne in a parmesan cream sauce with mushrooms.','pasta','pasta',269,true,null,'creamy rich mild',0],
  ['chicken-pesto-pasta','Chicken Pesto Pasta','Penne with grilled chicken and basil pesto.','pasta','pasta',299,false,null,'aromatic savory',1],
  // Burgers, wraps, snacks
  ['aloo-tikki-burger','Aloo Tikki Burger','Spiced potato patty, onion and mint mayo.','burgers','burger',99,true,'vegBurger','savory crunchy',1],
  ['paneer-burger','Crispy Paneer Burger','Crumb-fried paneer slab, lettuce and tandoori mayo.','burgers','burger',149,true,null,'crunchy creamy savory',1],
  ['chicken-zinger','Spicy Chicken Zinger Burger','Hot and crispy fried chicken fillet with lettuce and mayo.','burgers','burger',179,false,null,'spicy crunchy savory',3],
  ['grilled-chicken-burger','Grilled Chicken Burger','Grilled chicken breast, lettuce, tomato and mustard mayo.','burgers','burger',189,false,null,'smoky light savory',1],
  ['double-chicken-burger','Double Chicken Burger','Two crispy chicken patties with cheese.','burgers','burger',249,false,null,'rich crunchy savory',1],
  ['paneer-tikka-wrap','Paneer Tikka Wrap','Paneer tikka, onion and mint chutney in a soft wrap.','burgers','kebab',149,true,'paneerWrap','smoky spicy savory',2],
  ['chicken-tikka-roll','Chicken Tikka Roll','Chicken tikka, onion and chutney rolled in a paratha.','burgers','kebab',159,false,'chickenWrap','smoky spicy savory',2],
  ['egg-roll','Egg Kathi Roll','Paratha layered with egg, onion and sauces.','burgers','kebab',99,false,null,'savory',1],
  ['falafel-wrap','Falafel Hummus Wrap','Falafel, hummus, pickled onion and greens.','bowls','salad',169,true,null,'savory light crunchy',1],
  ['french-fries','Salted French Fries','Crisp potato fries with ketchup.','burgers','burger',99,true,'frenchFries','crunchy savory',0],
  ['peri-fries','Peri Peri Fries','Fries tossed in peri peri seasoning.','burgers','burger',119,true,null,'spicy crunchy savory',2],
  ['chicken-nuggets','Chicken Nuggets','Six crumb-fried chicken nuggets with dip.','burgers','burger',149,false,null,'crunchy savory mild',0],
  ['veg-samosa','Samosa (2 pc)','Crisp pastry with spiced potato and peas.','chaat','chaat',49,true,'samosa','crunchy spicy savory',2],
  ['onion-pakoda','Onion Pakoda','Crisp gram-flour onion fritters.','chaat','chaat',69,true,null,'crunchy spicy savory',2],
  ['mirchi-bajji','Mirchi Bajji','Stuffed green chillies fried in gram-flour batter.','telangana-andhra','chaat',59,true,null,'spicy crunchy savory',3],
  // Tandoor & kebabs
  ['tandoori-chicken-half','Tandoori Chicken (Half)','Half chicken marinated in yogurt and spices, charred in the tandoor.','kebabs','kebab',249,false,'tandooriChickenHalf','smoky spicy savory',2],
  ['chicken-tikka','Chicken Tikka','Six pieces of boneless chicken tikka from the tandoor.','kebabs','kebab',229,false,'chickenTikka','smoky spicy savory',2],
  ['paneer-tikka','Paneer Tikka','Six pieces of tandoor-charred paneer with peppers.','kebabs','kebab',219,true,'paneerTikka','smoky spicy savory',2],
  ['seekh-kebab','Mutton Seekh Kebab','Minced goat kebabs grilled on skewers.','kebabs','kebab',289,false,null,'smoky spicy rich',2],
  ['malai-tikka','Chicken Malai Tikka','Cream-and-cheese marinated chicken from the tandoor.','kebabs','kebab',249,false,null,'creamy mild smoky',1],
  ['tangdi','Chicken Tangdi Kebab','Tandoori chicken drumsticks.','kebabs','kebab',269,false,null,'smoky spicy savory',2],
  // Chaat
  ['pani-puri','Pani Puri (6 pc)','Crisp puris with spiced potato and tangy mint water.','chaat','chaat',49,true,'paniPuri','tangy spicy crunchy',2],
  ['dahi-puri','Dahi Puri','Puris filled with potato, curd and sweet-tangy chutneys.','chaat','chaat',69,true,null,'tangy sweet crunchy',1],
  ['papdi-chaat','Dahi Papdi Chaat','Papdi, potato, chickpeas, curd and chutneys.','chaat','chaat',79,true,null,'tangy sweet crunchy',1],
  ['samosa-chaat','Samosa Chaat','Crushed samosa with chole, curd and chutneys.','chaat','chaat',79,true,null,'tangy spicy savory',2],
  ['pav-bhaji','Pav Bhaji','Buttery mashed-vegetable bhaji with two toasted pavs.','chaat','chaat',109,true,'pavBhaji','spicy rich savory',2],
  ['vada-pav','Vada Pav','Spiced potato vada in a pav with garlic chutney.','chaat','chaat',39,true,'vadaPav','spicy savory',2],
  ['bhel','Bhel Puri','Puffed rice, sev, onion, tomato and tangy chutneys.','chaat','chaat',59,true,null,'tangy crunchy light',1],
  ['aloo-tikki-chaat','Aloo Tikki Chaat','Crisp potato tikkis with chole and chutneys.','chaat','chaat',79,true,null,'tangy spicy crunchy',2],
  // Healthy & high protein
  ['quinoa-bowl','Quinoa Veg Bowl','Quinoa, roasted vegetables, chickpeas and lemon-tahini.','bowls','salad',229,true,null,'light savory tangy',0],
  ['chicken-protein-bowl','High-Protein Chicken Bowl','Grilled chicken breast, brown rice, beans, egg and greens.','bowls','salad',279,false,'proteinChickenBowl','savory light smoky',1],
  ['paneer-protein-bowl','Paneer Protein Bowl','Grilled paneer, brown rice, chickpeas and vegetables.','bowls','salad',249,true,'paneerBowl','savory light',1],
  ['egg-protein-bowl','Egg & Chickpea Protein Bowl','Boiled eggs, chickpeas, quinoa and greens.','bowls','salad',219,false,null,'savory light',1],
  ['sprouts-salad','Sprouts Salad','Moong sprouts, cucumber, tomato, onion and lemon.','bowls','salad',129,true,'sproutsSalad','tangy light crunchy',1],
  ['grilled-fish-bowl','Grilled Fish Rice Bowl','Grilled basa fillet, herbed rice and sautéed greens.','bowls','salad',299,false,null,'light savory smoky',1],
  ['millet-khichdi','Millet Khichdi','Foxtail millet and moong dal khichdi with ghee.','bowls','meals',169,true,null,'light mild savory',0],
  // Desserts
  ['double-ka-meetha','Double Ka Meetha','Hyderabadi bread pudding with saffron milk and nuts.','desserts','dessert',109,true,null,'sweet rich',0],
  ['qubani','Qubani Ka Meetha','Stewed apricot dessert with cream.','desserts','dessert',129,true,null,'sweet',0],
  ['rasmalai','Rasmalai (2 pc)','Soft chenna discs in saffron milk.','desserts','dessert',119,true,null,'sweet creamy',0],
  ['gulab-jamun-2','Gulab Jamun (2 pc)','Milk-solid dumplings in cardamom syrup.','desserts','dessert',79,true,'gulabJamun','sweet rich',0],
  ['brownie','Chocolate Brownie','Fudgy chocolate brownie.','desserts','bakery',119,true,null,'sweet rich',0],
  ['kulfi','Malai Kulfi','Traditional slow-reduced milk ice cream.','desserts','dessert',89,true,null,'sweet creamy',0],
  ['phirni','Phirni','Ground-rice and milk pudding with cardamom.','desserts','dessert',99,true,null,'sweet creamy',0],
  // Bakery
  ['osmania-biscuits','Osmania Biscuits (200 g)','Hyderabadi sweet-salty butter biscuits.','bakery','bakery',120,true,null,'sweet crunchy',0],
  ['veg-puff','Veg Puff','Flaky pastry with spiced vegetable filling.','bakery','bakery',35,true,null,'crunchy savory',1],
  ['egg-puff','Egg Puff','Flaky pastry with masala egg.','bakery','bakery',40,false,null,'crunchy savory',1],
  ['chicken-puff','Chicken Puff','Flaky pastry with spiced chicken.','bakery','bakery',50,false,null,'crunchy savory',1],
  // Beverages
  ['masala-chai','Masala Chai','Tea brewed with milk, ginger and cardamom.','beverages','chai',30,true,'masalaChai','aromatic sweet',0],
  ['irani-chai','Irani Chai','Slow-brewed Hyderabadi tea with thick milk.','beverages','chai',25,true,null,'sweet creamy',0],
  ['sweet-lassi','Sweet Lassi','Chilled sweetened yogurt drink.','beverages','cold-beverage',69,true,'sweetLassi','sweet creamy',0],
  ['mango-lassi','Mango Lassi','Yogurt blended with mango pulp.','beverages','cold-beverage',89,true,null,'sweet creamy',0],
  ['cold-coffee','Cold Coffee','Chilled coffee blended with milk and ice cream.','beverages','cold-beverage',119,true,null,'sweet creamy',0],
  ['fresh-lime','Fresh Lime Soda','Lime, soda and a pinch of salt or sugar.','beverages','cold-beverage',59,true,null,'tangy light',0],
  ['buttermilk','Masala Buttermilk','Spiced chaas with ginger, curry leaves and coriander.','beverages','cold-beverage',39,true,null,'tangy light',0],
  ['badam-milk','Badam Milk','Warm almond milk with saffron.','beverages','cold-beverage',69,true,null,'sweet creamy',0],
  // Haleem
  ['mutton-haleem','Mutton Haleem','Slow-pounded wheat, lentils and goat meat with ghee and fried onions.','biryani','haleem',249,false,null,'rich aromatic spicy savory',2],
  ['chicken-haleem','Chicken Haleem','Slow-pounded wheat, lentils and chicken with ghee.','biryani','haleem',199,false,null,'rich aromatic savory',2],
];

/** Restaurant concept → dishes that fit it. */
// prettier-ignore
export const ASSIGNMENTS: Record<string, string[]> = {
  'tiffin': ['masala-dosa','mysore-masala-dosa','ghee-roast-dosa','onion-uttapam','idli-sambar','medu-vada','rava-idli','ragi-dosa','poori-bhaji','lemon-rice','bisi-bele-bath','veg-thali','masala-chai','buttermilk'],
  'hearth': ['farmhouse-pizza','paneer-tikka-pizza','chicken-tikka-pizza','bbq-chicken-pizza','mini-margherita','penne-arrabbiata','alfredo','chicken-pesto-pasta','brownie','cold-coffee','fresh-lime','peri-fries'],
  'table': ['quinoa-bowl','chicken-protein-bowl','paneer-protein-bowl','egg-protein-bowl','sprouts-salad','falafel-wrap','grilled-fish-bowl','chicken-rice-bowl','millet-khichdi','fresh-lime','buttermilk','brownie'],
  'bun': ['aloo-tikki-burger','paneer-burger','chicken-zinger','grilled-chicken-burger','double-chicken-burger','french-fries','peri-fries','chicken-nuggets','cold-coffee','chicken-tikka-roll','paneer-tikka-wrap','brownie'],
  'deccan-handi-gachi': ['mini-chicken-biryani','spicy-chicken-biryani','chicken-65-biryani','paneer-biryani','chicken-pulao','mutton-haleem','double-ka-meetha','qubani'],
  'gachibowli-tiffin': ['masala-dosa','ghee-roast-dosa','pesarattu','idli-sambar','sambar-vada','poori-bhaji','mirchi-bajji'],
  'fd-smash-gachi': ['chicken-zinger','grilled-chicken-burger','paneer-burger','chicken-tikka-roll','paneer-tikka-wrap','peri-fries','chicken-nuggets'],
  'cyberabad-wok-madhapur': ['veg-hakka-noodles','chicken-hakka-noodles','schezwan-noodles','chicken-schezwan-rice','egg-fried-rice','veg-fried-rice','chilli-chicken','gobi-manchurian','chilli-paneer','veg-momos','chicken-momos','fried-chicken-momos'],
  'pind-handi-madhapur': ['butter-chicken','kadai-chicken','dal-makhani','chole','kadai-paneer','butter-naan','garlic-naan','jeera-rice','sweet-lassi'],
  'botanical-bowl-madhapur': ['quinoa-bowl','chicken-protein-bowl','paneer-protein-bowl','egg-protein-bowl','sprouts-salad','chicken-rice-bowl','millet-khichdi','fresh-lime'],
  'woodstone-hitec': ['farmhouse-pizza','chicken-tikka-pizza','bbq-chicken-pizza','mini-margherita','penne-arrabbiata','alfredo','chicken-pesto-pasta'],
  'charcoal-hitec': ['tandoori-chicken-half','malai-tikka','seekh-kebab','tangdi','paneer-tikka','chicken-tikka-roll','butter-naan','mutton-rogan-josh'],
  'oven-crumb-kondapur': ['brownie','veg-puff','egg-puff','chicken-puff','cold-coffee','osmania-biscuits','french-fries'],
  'chaat-mandi-kondapur': ['pani-puri','dahi-puri','papdi-chaat','samosa-chaat','pav-bhaji','vada-pav','bhel','aloo-tikki-chaat','veg-samosa','masala-chai'],
  'kaveri-veg-biryani-kuka': ['veg-dum-biryani','paneer-biryani','mushroom-biryani','veg-pulao','jeera-rice','veg-thali','double-ka-meetha','buttermilk'],
  'suprabhat-tiffins-kuka': ['masala-dosa','pesarattu','andhra-meals','bisi-bele-bath','lemon-rice','medu-vada','onion-pakoda'],
  'crunch-box-kuka': ['chicken-zinger','aloo-tikki-burger','egg-roll','chicken-tikka-roll','french-fries','peri-fries','chicken-nuggets','cold-coffee'],
  'kesar-clove-jubilee': ['butter-chicken','chicken-tikka-masala','mutton-rogan-josh','paneer-butter-masala','palak-paneer','dal-makhani','garlic-naan','phirni'],
  'zafran-mithai-jubilee': ['double-ka-meetha','qubani','rasmalai','gulab-jamun-2','kulfi','phirni','irani-chai','badam-milk'],
  'prana-bowls-jubilee': ['chicken-protein-bowl','paneer-protein-bowl','quinoa-bowl','egg-protein-bowl','sprouts-salad','chicken-rice-bowl','grilled-fish-bowl','millet-khichdi'],
  'banjara-courtyard': ['hyd-chicken-biryani','chicken-dum-biryani','veg-dum-biryani','farmhouse-pizza','alfredo','butter-chicken','chilli-chicken','double-ka-meetha'],
  'koyla-seekh-banjara': ['tandoori-chicken-half','chicken-tikka','malai-tikka','seekh-kebab','tangdi','paneer-tikka','tandoori-roti','mutton-rogan-josh'],
  'deccan-leaf-ameerpet': ['andhra-meals','veg-thali','chicken-thali','bisi-bele-bath','lemon-rice','mirchi-bajji','buttermilk'],
  'begum-chaat-ameerpet': ['pani-puri','dahi-puri','papdi-chaat','bhel','vada-pav','samosa-chaat','masala-chai','onion-pakoda'],
  'golconda-zafran-mehdi': ['mutton-dum-biryani','chicken-dum-biryani','mini-chicken-biryani','egg-biryani','chicken-haleem','mutton-haleem','qubani','chicken-pulao'],
  'irani-bakery-mehdi': ['osmania-biscuits','irani-chai','veg-puff','egg-puff','chicken-puff','brownie','badam-milk'],
  'dakshin-sunrise-secund': ['masala-dosa','mysore-masala-dosa','rava-idli','idli-sambar','medu-vada','sambar-vada','onion-uttapam','ragi-dosa'],
  'clock-tower-secund': ['veg-thali','north-thali','chicken-thali','chole','kadai-paneer','egg-biryani','jeera-rice','mini-chicken-biryani'],
};

/** Illustrative price positioning per kitchen (budget ×0.9, premium ×1.15). */
const BUDGET = new Set(['clock-tower-secund','begum-chaat-ameerpet','irani-bakery-mehdi','crunch-box-kuka','gachibowli-tiffin','suprabhat-tiffins-kuka','dakshin-sunrise-secund','chaat-mandi-kondapur','kaveri-veg-biryani-kuka']);
const PREMIUM = new Set(['kesar-clove-jubilee','banjara-courtyard','woodstone-hitec','hearth','prana-bowls-jubilee','charcoal-hitec','koyla-seekh-banjara']);
export function priceFor(restaurantId: string, rupees: number) {
  const f = BUDGET.has(restaurantId) ? 0.9 : PREMIUM.has(restaurantId) ? 1.15 : 1;
  if (f === 1 || rupees < 60) return rupees;
  return Math.max(19, Math.round((rupees * f) / 10) * 10 - 1);
}

const SECTION: Record<string, string> = {
  biryani: 'Biryani & Rice', haleem: 'Biryani & Rice', rice: 'Biryani & Rice', dosa: 'Dosas & Tiffins', 'idli-vada': 'Dosas & Tiffins',
  breakfast: 'Dosas & Tiffins', curry: 'Curries', bread: 'Breads', thali: 'Meals & Thalis', noodles: 'Noodles & Rice', momos: 'Momos & Starters',
  starter: 'Momos & Starters', kebab: 'Tandoor & Rolls', wrap: 'Tandoor & Rolls', pizza: 'Pizzas', pasta: 'Pasta', burger: 'Burgers & Sides',
  bowl: 'Bowls & Salads', chaat: 'Chaat & Snacks', snack: 'Chaat & Snacks', puff: 'Bakery', dessert: 'Desserts', beverage: 'Beverages',
};

const norm = (s: string) => s.toLowerCase().replace(/\(.*?\)/g, '').replace(/[^a-z0-9]+/g, ' ').trim();

export async function seedFoodFinderCatalog(db: ReturnType<typeof createDatabase>) {
  const byKey = new Map(TEMPLATES.map((t) => [t[0], t]));
  for (const keys of Object.values(ASSIGNMENTS)) for (const k of keys) if (!byKey.has(k)) throw new Error(`Unknown template ${k}`);
  let created = 0, skippedDuplicate = 0, nutrition = 0, profiles = 0;
  await db.$transaction(async (tx) => {
    const restaurants = new Set((await tx.restaurant.findMany({ select: { id: true } })).map((r) => r.id));
    const existing = await tx.menuItem.findMany({ select: { id: true, restaurantId: true, name: true } });
    const names = new Set(existing.map((i) => `${i.restaurantId}|${norm(i.name)}`));
    const ids = new Set(existing.map((i) => i.id));
    const sections = await tx.menuSection.findMany({ select: { id: true, restaurantId: true, name: true } });
    for (const [restaurantId, keys] of Object.entries(ASSIGNMENTS)) {
      if (!restaurants.has(restaurantId)) continue; // never create orphans
      for (const [i, key] of keys.entries()) {
        const [, name, description, categoryId, imageKey, rupees, veg, ref, tastes, spice] = byKey.get(key)!;
        const id = `f1-${restaurantId}-${key}`.slice(0, 64);
        if (!ids.has(id)) {
          if (names.has(`${restaurantId}|${norm(name)}`)) { skippedDuplicate++; continue; }
          const profile = classifyDish({ name, description, categoryId, isVegetarian: veg });
          const sectionName = SECTION[profile.dishGroup] ?? 'More to explore';
          let section = sections.find((s) => s.restaurantId === restaurantId && s.name === sectionName);
          if (!section) {
            section = { id: `${restaurantId}-${slug(sectionName)}`.slice(0, 100), restaurantId, name: sectionName };
            if (!sections.some((s) => s.id === section!.id)) await tx.menuSection.create({ data: { ...section, displayOrder: 60 } });
            sections.push(section);
          }
          await tx.menuItem.create({ data: { id, restaurantId, categoryId, sectionId: section.id, name, description, imageKey,
            basePricePaise: priceFor(restaurantId, rupees) * 100, isVegetarian: veg, displayOrder: 200 + i } });
          ids.add(id); names.add(`${restaurantId}|${norm(name)}`);
          created++;
          const curated = tastes.split(' ').filter((t): t is Taste => (TASTES as readonly string[]).includes(t));
          await tx.menuItemProfile.create({ data: { menuItemId: id, ...profile, tasteTags: TASTES.filter((t) => curated.includes(t)), spiceLevel: spice, tagSource: 'CURATED' } });
          profiles++;
        }
        if (ref) nutrition += await addNutrition(tx, id, ref);
      }
    }
    // Profile every other item from its own name/description (tagSource RULES). Rule-derived
    // profiles are refreshed when the rules improve; CURATED profiles are never touched.
    const rest = await tx.menuItem.findMany({ where: { OR: [{ profile: { is: null } }, { profile: { tagSource: 'RULES' } }] },
      select: { id: true, name: true, description: true, categoryId: true, isVegetarian: true, profile: true } });
    for (const item of rest) {
      const p = classifyDish(item);
      const cur = item.profile;
      if (!cur) await tx.menuItemProfile.create({ data: { menuItemId: item.id, ...p, tagSource: 'RULES' } });
      else if (JSON.stringify([cur.cuisine, cur.foodFamily, cur.dishGroup, cur.mainIngredient, cur.tasteTags, cur.spiceLevel, cur.synonyms])
        === JSON.stringify([p.cuisine, p.foodFamily, p.dishGroup, p.mainIngredient, p.tasteTags, p.spiceLevel, p.synonyms])) continue;
      else await tx.menuItemProfile.update({ where: { menuItemId: item.id }, data: p });
      profiles++;
    }
  }, { timeout: 120000 });
  return { created, skippedDuplicate, nutrition, profiles };
}

async function addNutrition(tx: any, menuItemId: string, ref: string) {
  const n = ALL_REF[ref];
  if (!n) throw new Error(`Unknown nutrition reference ${ref}`);
  if (await tx.menuItemNutrition.findUnique({ where: { menuItemId } })) return 0; // never overwrite
  await tx.menuItemNutrition.create({ data: { menuItemId, servingDescription: n.serving, servingGrams: n.grams, caloriesKcal: n.kcal,
    proteinG: n.p, carbsG: n.c, fatG: n.f, basis: 'ESTIMATE', source: NUTRITION_SOURCE } });
  return 1;
}

if (require.main === module) {
  const url = process.env.DATABASE_URL!;
  const db = createDatabase(url);
  seedFoodFinderCatalog(db)
    .then((r) => console.log(JSON.stringify({ event: 'food_finder_catalog', database: new URL(url).pathname.slice(1), ...r })))
    .catch((e) => { console.error(e instanceof Error ? e.message : e); process.exitCode = 1; })
    .finally(() => db.$disconnect());
}
