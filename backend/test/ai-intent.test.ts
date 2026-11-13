
import { test } from 'node:test';
import assert from 'node:assert/strict';

const { normalizeFoodIntent } =
  require('../dist/src/modules/ai-ordering/food-intent');

test('valid customer requirements are preserved', () => {
  const result = normalizeFoodIntent({
    dishQuery: 'pizza',
    quantity: 2,
    vegetarian: true,
    maxPayablePaise: 50000,
    minRating: 4.0,
    maxDeliveryMinutes: 35,
  });

  assert.equal(result.dishQuery, 'pizza');
  assert.equal(result.quantity, 2);
  assert.equal(result.vegetarian, true);
  assert.equal(result.maxPayablePaise, 50000);
  assert.equal(result.maxDeliveryMinutes, 35);
  assert.equal(result.clarificationQuestion, null);
});

test('invalid AI outputs are rejected', () => {
  assert.throws(() => normalizeFoodIntent({
    quantity: -2,
  }));

  assert.throws(() => normalizeFoodIntent({
    maxPayablePaise: '500',
  }));

  assert.throws(() => normalizeFoodIntent({
    vegetarian: 'yes',
  }));

  assert.throws(() => normalizeFoodIntent({
    dishQuery: 'pizza',
    placeOrderAutomatically: true,
  }));
});
