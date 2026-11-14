import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseMessage, correctWord } from '../src/modules/food-finder/rule-parser';
import { applyUpdate, normalizeUpdate, EMPTY_INTENT } from '../src/modules/food-finder/finder-intent';
import { classify, sanitize, GeminiError, GeminiFinderService } from '../src/modules/food-finder/gemini-finder.service';
import { classifyDish, familySimilarity } from '../src/modules/food-finder/food-taxonomy';
import { resolveWant } from '../src/modules/food-finder/recommendation.engine';

test('rule parser: budget is the total in paise; protein/calories are never read as money', () => {
  assert.deepEqual(parseMessage('I want Chicken Biryani for ₹150'), { budgetPaise: 15000, dishQuery: 'chicken biryani', mainIngredient: 'chicken', newSearch: true });
  assert.equal(parseMessage('chicken biryani under 200 rupees').budgetPaise, 20000);
  const p = parseMessage('Find meals with 25g protein under ₹250');
  assert.equal(p.minProteinG, 25); assert.equal(p.budgetPaise, 25000);
  const c = parseMessage('show vegetarian dishes under 500 calories');
  assert.equal(c.maxCaloriesKcal, 500); assert.equal(c.budgetPaise, undefined); assert.equal(c.vegetarian, true); assert.equal(c.dishQuery, undefined);
  assert.equal(parseMessage('2 plates of masala dosa under 300').quantity, 2);
  assert.equal(parseMessage('biryani for 3 people').quantity, 3);
});

test('rule parser: follow-ups, clears, selection, exclusions, misspellings, taste', () => {
  assert.deepEqual(parseMessage('remove the budget limit').clearFields, ['budgetPaise']);
  assert.equal(parseMessage('Now show under ₹150').budgetPaise, 15000);
  assert.equal(parseMessage('increase budget to ₹300').budgetPaise, 30000);
  assert.equal(parseMessage('show cheaper options').cheaper, true);
  const spicier = parseMessage('Make it spicier');
  assert.deepEqual(spicier.addTastes, ['spicy']); assert.equal(spicier.minSpiceLevel, 2);
  const less = parseMessage('less spicy please');
  assert.equal(less.maxSpiceLevel, 1); assert.deepEqual(less.removeTastes, ['spicy']);
  assert.deepEqual(parseMessage('remove the taste preference').clearFields?.sort(), ['spice', 'tastes']);
  assert.equal(parseMessage('Give me a vegetarian option instead').vegetarian, true);
  assert.equal(parseMessage('non-veg please').vegetarian, false);
  assert.equal(parseMessage('add the second one').selectIndex, 2);
  assert.deepEqual(parseMessage('paneer curry without onion').excludeIngredients, ['onion']);
  assert.equal(parseMessage('chiken biriyani').dishQuery, 'chicken biryani');
  assert.equal(correctWord('panner'), 'paneer');
  assert.deepEqual(parseMessage('something creamy and vegetarian').addTastes, ['creamy']);
  assert.equal(parseMessage('south indian food').cuisine, 'South Indian');
  assert.equal(parseMessage('Find meals with 25g protein under ₹250').newSearch, true, 'self-contained request starts over');
  assert.equal(parseMessage('Now show under ₹150').newSearch, undefined);
  assert.equal(parseMessage('Give me a vegetarian option instead').newSearch, undefined, 'adjustment keeps the search');
});

test('intent merge: multi-turn memory, explicit clears, vegetarian switch drops meat, conflicting spice', () => {
  let i = applyUpdate(null, parseMessage('I want chicken biryani under ₹200'));
  i = applyUpdate(i, parseMessage('Make it spicier'));
  assert.equal(i.dishQuery, 'chicken biryani'); assert.equal(i.budgetPaise, 20000); assert.ok(i.tastes.includes('spicy'));
  i = applyUpdate(i, parseMessage('Now show under ₹150'));
  assert.equal(i.budgetPaise, 15000); assert.ok(i.tastes.includes('spicy'), 'taste kept');
  i = applyUpdate(i, parseMessage('Remove the budget limit'));
  assert.equal(i.budgetPaise, null); assert.equal(i.dishQuery, 'chicken biryani');
  i = applyUpdate(i, parseMessage('Give me a vegetarian option instead'));
  assert.equal(i.vegetarian, true); assert.equal(i.mainIngredient, null); assert.equal(i.dishQuery, 'biryani');
  i = applyUpdate(i, parseMessage('less spicy'));
  assert.ok(!i.tastes.includes('spicy') && i.tastes.includes('mild')); assert.equal(i.maxSpiceLevel, 1); assert.equal(i.minSpiceLevel, null);
  i = applyUpdate(i, parseMessage('remove the spice preference'));
  assert.equal(i.maxSpiceLevel, null); assert.ok(!i.tastes.includes('mild'));
  // A later explicit meat request replaces an earlier vegetarian preference (never "vegetarian chicken").
  let v = applyUpdate(null, parseMessage('Find vegetarian meals with 25g protein under ₹250'));
  assert.equal(v.vegetarian, true);
  v = applyUpdate(v, parseMessage('I want Chicken Biryani under ₹300'));
  assert.equal(v.vegetarian, null); assert.equal(v.mainIngredient, 'chicken'); assert.equal(v.dishQuery, 'chicken biryani');
  v = applyUpdate(v, parseMessage('Make it vegetarian'));
  assert.equal(v.vegetarian, true); assert.equal(v.mainIngredient, null); assert.equal(v.dishQuery, 'biryani'); assert.equal(v.budgetPaise, 30000, 'budget kept');
});

test('normalizeUpdate rejects unexpected fields and out-of-range values (model output is untrusted)', () => {
  assert.throws(() => normalizeUpdate({ pricePaise: 1 }), /Unexpected/);
  assert.throws(() => normalizeUpdate({ budgetPaise: -5 }), /budgetPaise/);
  assert.throws(() => normalizeUpdate({ quantity: 500 }), /quantity/);
  assert.throws(() => normalizeUpdate({ addTastes: ['umami'] }), /addTastes/);
  assert.throws(() => normalizeUpdate({ mainIngredient: 'unicorn' }), /mainIngredient/);
  assert.deepEqual(normalizeUpdate({ dishQuery: '  <b>biryani</b> ' }).dishQuery, 'b biryani /b');
});

test('Gemini sanitize: drops numbers the customer never typed and invalid selections', () => {
  const u = sanitize({ dishQuery: 'chicken biryani', budgetPaise: 9900, minProteinG: 40, quantity: 3, selectIndex: 9, addTastes: [], vegetarian: false }, 'non-veg chicken biryani please', 2);
  assert.equal(u.budgetPaise, undefined, 'invented budget dropped');
  assert.equal(u.minProteinG, undefined);
  assert.equal(u.quantity, undefined);
  assert.equal(u.selectIndex, undefined);
  const inferred = sanitize({ dishQuery: 'paneer', mainIngredient: 'paneer', vegetarian: true }, 'make it vegetarian', 0);
  assert.equal(inferred.vegetarian, true);
  assert.equal(inferred.dishQuery, undefined, 'dish the customer never mentioned is dropped');
  assert.equal(inferred.mainIngredient, undefined);
  assert.equal(sanitize({ vegetarian: false }, 'Find meals with 25g protein', 0).vegetarian, undefined, 'non-veg is never assumed');
  assert.equal(sanitize({ vegetarian: false }, 'I want chicken biryani', 0).vegetarian, undefined, 'a chicken dish is not a non-veg-only filter');
  assert.equal(sanitize({ vegetarian: false }, 'non-veg please', 0).vegetarian, false);
  assert.equal(sanitize({ dishQuery: 'biryani' }, 'chiken biriyani pls', 0).dishQuery, 'biryani', 'misspellings still match');
  assert.equal(u.vegetarian, false, 'explicit non-veg kept');
  assert.equal(sanitize({ budgetPaise: 15000 }, 'under ₹150', 0).budgetPaise, 15000);
  assert.throws(() => sanitize({ finalPayablePaise: 1 }, 'x', 0), (e: any) => e instanceof GeminiError && e.code === 'BAD_OUTPUT');
  assert.throws(() => sanitize('not json object', 'x', 0), (e: any) => e.code === 'BAD_OUTPUT');
});

test('Gemini failure classification and missing key', async () => {
  assert.equal(classify({ status: 429, message: 'RESOURCE_EXHAUSTED' }).code, 'QUOTA');
  assert.equal(classify({ status: 400, message: 'API key not valid' }).code, 'INVALID_KEY');
  assert.equal(classify({ name: 'AbortError', message: 'aborted' }).code, 'TIMEOUT');
  assert.equal(classify(new Error('fetch failed')).code, 'NETWORK');
  assert.equal(classify({ status: 404, message: 'model not found' }).code, 'MODEL_UNAVAILABLE');
  const saved = process.env.GEMINI_API_KEY; delete process.env.GEMINI_API_KEY;
  try {
    const s = new GeminiFinderService(); s.useClient(null, 'x');
    assert.equal(s.configured, false);
    await assert.rejects(s.extract('biryani', null, []), (e: any) => e.code === 'NOT_CONFIGURED');
  } finally { if (saved !== undefined) process.env.GEMINI_API_KEY = saved; }
});

test('Gemini: network errors retry once; timeouts and quota fall back immediately; empty and invalid JSON are typed errors', async () => {
  let calls = 0;
  const s = new GeminiFinderService();
  const list = async function* () { yield { name: 'models/embedding-001' }; yield { name: 'models/gemini-9.9-flash' }; };
  s.useClient({ models: { list: () => list(), generateContent: async () => { calls++; if (calls === 1) throw new Error('fetch failed'); return { text: JSON.stringify({ dishQuery: 'dosa', budgetPaise: null, quantity: null, vegetarian: null, addTastes: [], removeTastes: [], excludeIngredients: [], cheaper: false, selectIndex: null, newSearch: false, clearFields: [], clarificationQuestion: null }) }; } } }, 'm');
  assert.equal((await s.extract('dosa', null, [])).dishQuery, 'dosa'); assert.equal(calls, 2);
  calls = 0;
  s.useClient({ models: { list: () => list(), generateContent: async () => { calls++; throw { status: 429, message: 'quota' }; } } }, 'm');
  await assert.rejects(s.extract('dosa', null, []), (e: any) => e.code === 'QUOTA'); assert.equal(calls, 1);
  calls = 0;
  s.useClient({ models: { list: () => list(), generateContent: async () => { calls++; throw { name: 'AbortError' }; } } }, 'm');
  await assert.rejects(s.extract('dosa', null, []), (e: any) => e.code === 'TIMEOUT'); assert.equal(calls, 1, 'no retry after a timeout');
  assert.equal(classify({ status: 400, message: 'Manually set deadline 8s is too short' }).code, 'BAD_OUTPUT', 'a 400 is not a timeout');
  s.useClient({ models: { list: () => list(), generateContent: async () => ({ text: '' }) } }, 'm');
  await assert.rejects(s.extract('dosa', null, []), (e: any) => e.code === 'EMPTY');
  s.useClient({ models: { list: () => list(), generateContent: async () => ({ text: '{not json' }) } }, 'm');
  await assert.rejects(s.extract('dosa', null, []), (e: any) => e.code === 'BAD_OUTPUT');
  s.useClient({ models: { list: () => list(), generateContent: async () => ({ text: '{}' }) } }, null);
  assert.equal(await s.resolveModel(), 'gemini-9.9-flash', 'falls back to a discovered flash model, never an embedding model');
});

test('taxonomy: food families normalise equivalent dishes; similarity ranks related dishes', () => {
  for (const n of ['Chicken Dum Biryani', 'Hyderabadi Chicken Biryani', 'Mini Chicken Dum Biryani']) assert.equal(classifyDish({ name: n, description: '', isVegetarian: false }).foodFamily, 'chicken-biryani');
  assert.equal(classifyDish({ name: 'Chicken Pulao', description: '', isVegetarian: false }).foodFamily, 'chicken-rice');
  assert.equal(classifyDish({ name: 'Chicken Schezwan Fried Rice', description: '', isVegetarian: false }).spiceLevel, 3);
  assert.equal(classifyDish({ name: 'Masala Chai', description: '', isVegetarian: true }).dishGroup, 'beverage');
  assert.equal(classifyDish({ name: 'Malai Kulfi', description: '', isVegetarian: true }).dishGroup, 'dessert');
  assert.equal(classifyDish({ name: 'Wood-fired pepperoni', description: '', categoryId: 'pizza', isVegetarian: false }).mainIngredient, 'meat');
  const want = resolveWant({ ...EMPTY_INTENT, dishQuery: 'chicken biryani' });
  assert.equal(want.foodFamily, 'chicken-biryani');
  const sim = (name: string, veg = false) => familySimilarity(want, classifyDish({ name, description: '', isVegetarian: veg }));
  assert.equal(sim('Mini Chicken Dum Biryani'), 1);
  assert.ok(sim('Mutton Dum Biryani') > sim('Chicken Pulao') && sim('Chicken Pulao') > sim('Lemon Rice', true));
  assert.equal(sim('Gulab Jamun', true), 0);
});
