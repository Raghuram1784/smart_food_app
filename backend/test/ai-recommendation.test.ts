
import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const { RecommendationService } = require(
  '../dist/src/modules/ai-ordering/recommendation.service'
);

const baseIntent = {
  dishQuery: 'pizza',
  quantity: 2,
  vegetarian: true,
  maxPayablePaise: 50000,
  minRating: 4,
  maxDeliveryMinutes: 35,
  clarificationQuestion: null,
};

function createHarness() {
  const priceCalls: any[] = [];
  let capturedQuery: any;

  const items = [
    {
      id: 'wn-margherita',
      name: 'Classic Bufala Margherita',
      restaurantId: 'woodstone-hitec',
      basePricePaise: 31900,
      isVegetarian: true,
      restaurant: {
        name: 'Woodstone Napoli',
        rating: 4.4,
      },
    },
    {
      id: 'wn-farmhouse-pesto',
      name: 'Roasted Veggie & Basil Pesto Pizza',
      restaurantId: 'woodstone-hitec',
      basePricePaise: 34900,
      isVegetarian: true,
      restaurant: {
        name: 'Woodstone Napoli',
        rating: 4.4,
      },
    },
  ];

  const db = {
    client: {
      $transaction: async (callback: any) =>
        callback({
          menuItem: {
            findMany: async (query: any) => {
              capturedQuery = query;
              return items;
            },
          },
        }),
    },
  };

  const pricing = {
    validateArea: async () => ({
      id: 'hitec-city',
      name: 'HITEC City',
    }),

    rules: async () => [],

    price: (item: any, input: any) => {
      priceCalls.push(input);

      const subtotal = item.basePricePaise * input.quantity;

      return {
        subtotalPaise: subtotal,
        finalPayablePaise: subtotal + 3500,
        packagingPaise: 1000,
        deliveryPaise: 2000,
        platformPaise: 500,
        taxPaise: 0,
        estimatedMinutes: 30,
        expiresAt: '2026-11-13T15:00:00.000Z',
      };
    },
  };

  return {
    service: new RecommendationService(db, pricing),
    priceCalls,
    getQuery: () => capturedQuery,
  };
}

test('rejects pizzas exceeding total budget', async () => {
  const h = createHarness();

  const result = await h.service.recommend(
    baseIntent,
    'hitec-city'
  );

  assert.equal(result.totalMatches, 0);
  assert.equal(result.matches.length, 0);
  assert.equal(
    result.closestOverBudget.menuItemId,
    'wn-margherita'
  );
  assert.equal(
    result.closestOverBudget.finalPayablePaise,
    67300
  );

  assert.deepEqual(
    h.priceCalls.map(c => c.quantity),
    [2, 2]
  );
});

test('finds a valid pizza when budget increases', async () => {
  const h = createHarness();

  const result = await h.service.recommend(
    { ...baseIntent, maxPayablePaise: 70000 },
    'hitec-city'
  );

  assert.equal(result.totalMatches, 1);
  assert.equal(result.matches[0].menuItemId, 'wn-margherita');
  assert.equal(result.matches[0].finalPayablePaise, 67300);
  assert.equal(result.closestOverBudget, null);
});

test('rejects candidates exceeding the ETA limit', async () => {
  const h = createHarness();

  const result = await h.service.recommend(
    {
      ...baseIntent,
      maxPayablePaise: 100000,
      maxDeliveryMinutes: 25,
    },
    'hitec-city'
  );

  assert.equal(result.totalMatches, 0);
  assert.equal(result.closestOverBudget, null);
});

test('query applies hard catalog constraints', async () => {
  const h = createHarness();

  await h.service.recommend(baseIntent, 'hitec-city');

  const where = h.getQuery().where;

  assert.equal(where.availabilityStatus, 'AVAILABLE');
  assert.equal(where.isVegetarian, true);
  assert.equal(where.restaurant.operatingStatus, 'OPEN');
  assert.equal(where.restaurant.rating.gte, 4);
  assert.equal(
    where.restaurant.zones.some.zoneId,
    'hitec-city'
  );

  const searchFields = JSON.stringify(where.OR);

  assert.match(searchFields, /"name"/);
  assert.match(searchFields, /"category"/);
  assert.doesNotMatch(searchFields, /"restaurant"/);
});
