
import { test } from 'node:test';
import assert from 'node:assert/strict';

const {
  normalizeFoodIntent,
  mergeIntentWithClears,
} = require('../dist/src/modules/ai-ordering/food-intent');

test('removes delivery limit and preserves other preferences', () => {
  const previous = normalizeFoodIntent({
    dishQuery: 'pizza',
    quantity: 2,
    vegetarian: true,
    maxPayablePaise: 80000,
    minRating: 4,
    maxDeliveryMinutes: 35,
  });

  const update = normalizeFoodIntent({});

  const result = mergeIntentWithClears(
    previous,
    update,
    ['maxDeliveryMinutes'],
  );

  assert.equal(result.maxDeliveryMinutes, null);
  assert.equal(result.dishQuery, 'pizza');
  assert.equal(result.quantity, 2);
  assert.equal(result.vegetarian, true);
  assert.equal(result.maxPayablePaise, 80000);
  assert.equal(result.minRating, 4);
});

test('rejects invalid fields and conflicting instructions', () => {
  const update = normalizeFoodIntent({
    maxPayablePaise: 80000,
  });

  assert.throws(() =>
    mergeIntentWithClears(null, update, ['password'])
  );

  assert.throws(() =>
    mergeIntentWithClears(
      null,
      update,
      ['maxPayablePaise'],
    )
  );

  assert.throws(() =>
    mergeIntentWithClears(null, update, [
      'maxDeliveryMinutes',
      'maxDeliveryMinutes',
    ])
  );
});

test('allows an explicit vegetarian preference change', () => {
  const previous = normalizeFoodIntent({
    dishQuery: 'pizza',
    vegetarian: true,
  });

  const update = normalizeFoodIntent({
    vegetarian: false,
  });

  const result = mergeIntentWithClears(previous, update);

  assert.equal(result.vegetarian, false);
  assert.equal(result.dishQuery, 'pizza');
});
