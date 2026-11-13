
import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';

const { InterpretInput } = require(
  '../dist/src/modules/ai-ordering/ai-ordering.dto'
);

const { AiOrderingController } = require(
  '../dist/src/modules/ai-ordering/ai-ordering.controller'
);

test('accepts valid messages and rejects invalid ones', async () => {
  const valid = plainToInstance(InterpretInput, {
    message: '  Find 2 veg pizzas under 500  ',
  });

  assert.equal(valid.message, 'Find 2 veg pizzas under 500');
  assert.equal((await validate(valid)).length, 0);

  for (const message of ['', '   ', 'x'.repeat(1001)]) {
    const input = plainToInstance(InterpretInput, { message });
    assert.ok((await validate(input)).length > 0);
  }
});

test('controller delegates to the extraction service', async () => {
  let receivedMessage = '';

  const mockService = {
    async extract(message: string) {
      receivedMessage = message;
      return {
        dishQuery: 'pizza',
        quantity: 2,
        vegetarian: true,
        maxPayablePaise: 50000,
        minRating: null,
        maxDeliveryMinutes: null,
        clarificationQuestion: null,
      };
    },
  };

  const controller = new AiOrderingController(mockService);

  const response = await controller.interpret({
    message: 'Find 2 veg pizzas under 500',
  });

  assert.equal(receivedMessage, 'Find 2 veg pizzas under 500');
  assert.equal(response.quantity, 2);
  assert.equal(response.maxPayablePaise, 50000);
});
