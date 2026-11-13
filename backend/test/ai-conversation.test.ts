
import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const { AiConversationService } = require(
  '../dist/src/modules/ai-ordering/ai-conversation.service'
);

const customer = (sessionId: string) => ({
  userId: 'demo-customer',
  sessionId,
  roles: ['CUSTOMER'],
  expiresAt: new Date(Date.now() + 3600000),
});

const emptyIntent = () => ({
  dishQuery: null,
  quantity: null,
  vegetarian: null,
  maxPayablePaise: null,
  minRating: null,
  maxDeliveryMinutes: null,
  clarificationQuestion: null,
});

function createHarness() {
  const receivedIntents: any[] = [];
  const gemini = {
    extract: async (message: string) => {
      if (message === 'start') {
        return {
          dishQuery: 'pizza',
          quantity: 2,
          vegetarian: true,
          maxPayablePaise: 50000,
          minRating: 4,
          maxDeliveryMinutes: 35,
          clarificationQuestion: null,
        };
      }

      if (message === 'increase budget') {
        return {
          ...emptyIntent(),
          maxPayablePaise: 80000,
        };
      }

      if (message === 'missing quantity') {
        return {
          ...emptyIntent(),
          dishQuery: 'pizza',
        };
      }

      if (message === 'two') {
        return {
          ...emptyIntent(),
          quantity: 2,
        };
      }

      if (message === 'clear ETA') {
        return emptyIntent();
      }

      throw new Error('Unexpected test message');
    },

    async extractUpdate(message: string) {
      const intent = await this.extract(message);

      return {
        intent,
        clearFields:
          message === 'clear ETA'
            ? ['maxDeliveryMinutes']
            : [],
      };
    },
  };


  const option = {
    menuItemId: 'wn-margherita',
    dishName: 'Classic Bufala Margherita',
    restaurantName: 'Woodstone Napoli',
    quantity: 2,
    finalPayablePaise: 67300,
    estimatedMinutes: 30,
    rating: 4.4,
  };

  const recommendations = {
    recommend: async (intent: any) => {
      receivedIntents.push({ ...intent });

      const matchesBudget =
        intent.maxPayablePaise === null ||
        intent.maxPayablePaise >= option.finalPayablePaise;

      return {
        matches: matchesBudget ? [option] : [],
        totalMatches: matchesBudget ? 1 : 0,
        closestOverBudget: matchesBudget ? null : option,
      };
    },
  };

  return {
    service: new AiConversationService(
      gemini,
      recommendations,
    ),
    receivedIntents,
  };
}

test('remembers requirements and updates only budget', async () => {
  const h = createHarness();
  const user = customer('session-one');

  const first = await h.service.ask(
    'start',
    'hitec-city',
    user,
  );

  assert.equal(first.status, 'NO_EXACT_MATCH');
  assert.ok(first.conversationId);

  const second = await h.service.ask(
    'increase budget',
    'hitec-city',
    user,
    first.conversationId,
  );

  assert.equal(second.status, 'MATCHES_FOUND');
  assert.equal(second.conversationId, first.conversationId);

  assert.equal(second.intent.dishQuery, 'pizza');
  assert.equal(second.intent.quantity, 2);
  assert.equal(second.intent.vegetarian, true);
  assert.equal(second.intent.maxPayablePaise, 80000);
  assert.equal(second.intent.minRating, 4);
  assert.equal(second.intent.maxDeliveryMinutes, 35);

  assert.deepEqual(
    h.receivedIntents.map(i => i.maxPayablePaise),
    [50000, 80000],
  );
});

test('does not expose another session history', async () => {
  const h = createHarness();

  const first = await h.service.ask(
    'start',
    'hitec-city',
    customer('session-one'),
  );

  await assert.rejects(
    h.service.ask(
      'increase budget',
      'hitec-city',
      customer('session-two'),
      first.conversationId,
    ),
    (error: any) => error.getStatus() === 404,
  );
});

test('remembers dish while clarifying quantity', async () => {
  const h = createHarness();
  const user = customer('session-three');

  const first = await h.service.ask(
    'missing quantity',
    'hitec-city',
    user,
  );

  assert.equal(first.status, 'NEEDS_CLARIFICATION');
  assert.equal(first.recommendations, null);
  assert.equal(h.receivedIntents.length, 0);

  const second = await h.service.ask(
    'two',
    'hitec-city',
    user,
    first.conversationId,
  );

  assert.equal(second.intent.dishQuery, 'pizza');
  assert.equal(second.intent.quantity, 2);
  assert.equal(second.status, 'MATCHES_FOUND');
});

test('old conversations are unavailable after restart', async () => {
  const user = customer('session-four');

  const original = createHarness();

  const first = await original.service.ask(
    'start',
    'hitec-city',
    user,
  );

  // Simulate a restart by creating a new service instance.
  const restarted = createHarness();

  await assert.rejects(
    restarted.service.ask(
      'increase budget',
      'hitec-city',
      user,
      first.conversationId,
    ),
    (error: any) => error.getStatus() === 404,
  );
});

test('clears ETA without forgetting other preferences', async () => {
  const h = createHarness();
  const user = customer('session-clear-eta');

  // Establish original preferences.
  const first = await h.service.ask(
    'start',
    'hitec-city',
    user,
  );

  assert.equal(first.intent.maxDeliveryMinutes, 35);

  // Customer removes only the delivery-time constraint.
  const second = await h.service.ask(
    'clear ETA',
    'hitec-city',
    user,
    first.conversationId,
  );

  // Original requirements remain unchanged.
  assert.equal(second.intent.dishQuery, 'pizza');
  assert.equal(second.intent.quantity, 2);
  assert.equal(second.intent.vegetarian, true);
  assert.equal(second.intent.maxPayablePaise, 50000);
  assert.equal(second.intent.minRating, 4);

  // The delivery-time limit must be removed.
  assert.equal(second.intent.maxDeliveryMinutes, null);

  // The ₹500 budget is still insufficient.
  assert.equal(second.status, 'NO_EXACT_MATCH');
});
