
import {
  ConflictException,
  Inject,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';

import { AuthenticatedPrincipal } from '../auth/auth.types';
import {
  FoodIntent,
  mergeIntentWithClears,
} from './food-intent';
import { GeminiIntentService } from './gemini-intent.service';
import { RecommendationService } from './recommendation.service';

const TTL_MS = 30 * 60 * 1000;
const MAX_CONVERSATIONS = 1000;

const rupees = (paise: number) =>
  `₹${(paise / 100).toFixed(2)}`;

export function mergeIntents(
  previous: FoodIntent | null,
  update: FoodIntent,
): FoodIntent {
  return {
    dishQuery: update.dishQuery ?? previous?.dishQuery ?? null,
    quantity: update.quantity ?? previous?.quantity ?? null,
    vegetarian: update.vegetarian ?? previous?.vegetarian ?? null,
    maxPayablePaise:
      update.maxPayablePaise ?? previous?.maxPayablePaise ?? null,
    minRating: update.minRating ?? previous?.minRating ?? null,
    maxDeliveryMinutes:
      update.maxDeliveryMinutes ??
      previous?.maxDeliveryMinutes ??
      null,
    clarificationQuestion: update.clarificationQuestion,
  };
}

@Injectable()
export class AiConversationService {
  private readonly conversations = new Map<
    string,
    { intent: FoodIntent; expiresAt: number }
  >();

  private readonly inFlight = new Set<string>();

  constructor(
    @Inject(GeminiIntentService)
    private readonly gemini: GeminiIntentService,

    @Inject(RecommendationService)
    private readonly recommendations: RecommendationService,
  ) {}

  private cleanup() {
    const now = Date.now();

    for (const [key, value] of this.conversations) {
      if (value.expiresAt <= now) {
        this.conversations.delete(key);
      }
    }
  }

  private remember(key: string, intent: FoodIntent) {
    this.cleanup();

    if (
      !this.conversations.has(key) &&
      this.conversations.size >= MAX_CONVERSATIONS
    ) {
      throw new ServiceUnavailableException(
        'Too many active AI conversations',
      );
    }

    this.conversations.set(key, {
      intent,
      expiresAt: Date.now() + TTL_MS,
    });
  }

  async ask(
    message: string,
    area: string,
    principal: AuthenticatedPrincipal,
    conversationId?: string,
  ) {
    this.cleanup();

    const id = conversationId ?? randomUUID();

    // Trusted authenticated session ID prevents one
    // session from accessing another session's history.
    const key = `${principal.sessionId}:${id}`;

    const previous = conversationId
      ? this.conversations.get(key)
      : undefined;

    if (conversationId && !previous) {
      throw new NotFoundException(
        'Conversation expired or unavailable. Start a new request.',
      );
    }

    // Prevent overlapping updates to the same conversation.
    if (this.inFlight.has(key)) {
      throw new ConflictException(
        'A message is already being processed for this conversation',
      );
    }

    this.inFlight.add(key);

    try {
      const update = await this.gemini.extractUpdate(message);

      const intent = mergeIntentWithClears(
        previous?.intent ?? null,
        update.intent,
	update.clearFields,
      );

      if (
        intent.clarificationQuestion ||
        !intent.dishQuery ||
        !intent.quantity
      ) {
        const reply =
          intent.clarificationQuestion ??
          (!intent.dishQuery
            ? 'What would you like to eat?'
            : `How many ${intent.dishQuery} would you like?`);

        this.remember(key, intent);

        return {
          conversationId: id,
          status: 'NEEDS_CLARIFICATION',
          reply,
          intent,
          recommendations: null,
        };
      }

      const result = await this.recommendations.recommend(
        intent,
        area,
      );

      this.remember(key, intent);

      if (result.matches.length > 0) {
        const best = result.matches[0];

        return {
          conversationId: id,
          status: 'MATCHES_FOUND',
          reply:
            `I found ${result.totalMatches} matching option(s). ` +
            `The lowest-priced option is ${best.dishName} ` +
            `from ${best.restaurantName}. ` +
            `For ${best.quantity} item(s), the total is ` +
            `${rupees(best.finalPayablePaise)}, ` +
            `including configured charges. ` +
            `The illustrative delivery estimate is ` +
            `${best.estimatedMinutes} minutes. ` +
            `Prices must be confirmed again before checkout.`,
          intent,
          recommendations: result,
        };
      }

      const alternative = result.closestOverBudget;

      if (
        alternative &&
        intent.maxPayablePaise !== null
      ) {
        const extra =
          alternative.finalPayablePaise -
          intent.maxPayablePaise;

        return {
          conversationId: id,
          status: 'NO_EXACT_MATCH',
          reply:
            `I couldn't find an option satisfying all your ` +
            `requirements. The closest over-budget option is ` +
            `${alternative.dishName} from ` +
            `${alternative.restaurantName}, costing ` +
            `${rupees(alternative.finalPayablePaise)} ` +
            `for ${alternative.quantity} item(s). ` +
            `That's ${rupees(extra)} above your budget. ` +
            `Would you like to increase your budget?`,
          intent,
          recommendations: result,
        };
      }

      return {
        conversationId: id,
        status: 'NO_EXACT_MATCH',
        reply:
          `I couldn't find an available option matching ` +
          `all your requirements in the selected locality. ` +
          `Would you like to adjust your preferences?`,
        intent,
        recommendations: result,
      };
    } finally {
      this.inFlight.delete(key);
    }
  }
}
