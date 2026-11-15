/**
 * Multi-turn Smart Food Finder conversations.
 *
 * Adapted from Jeevan's AiConversationService (feature/f1-ai-ordering): conversations are
 * keyed by the authenticated user AND session, expire after 30 minutes, are bounded in
 * memory, and one message per conversation is processed at a time. Logging out (new
 * session) or a backend restart simply starts a fresh conversation.
 */
import { ConflictException, HttpException, Inject, Injectable, Logger, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { AuthenticatedPrincipal } from '../auth/auth.types';
import { DatabaseService } from '../../database/database.module';
import { applyUpdate, hasSearchCriteria, type FinderIntent, type IntentUpdate } from './finder-intent';
import { GeminiError, GeminiFinderService } from './gemini-finder.service';
import { describeIntent, RecommendationEngine, type FinderResult, type Recommendation } from './recommendation.engine';
import { parseMessage } from './rule-parser';

const TTL_MS = 30 * 60 * 1000;
const MAX_CONVERSATIONS = 2000;
/** Messages per customer per minute (FINDER_RATE_PER_MINUTE, default 15). */
const perMinute = () => Math.max(1, Number(process.env.FINDER_RATE_PER_MINUTE ?? 15) || 15);

interface Conversation { userId: string; intent: FinderIntent | null; shown: Recommendation[]; area: string | null; expiresAt: number; turns: number }

const AI_NOTICE: Record<string, string> = {
  NOT_CONFIGURED: 'AI is not set up on this server yet, so I used basic keyword understanding.',
  INVALID_KEY: 'The AI service rejected its key, so I used basic keyword understanding.',
  QUOTA: 'The AI service is busy right now, so I used basic keyword understanding.',
  TIMEOUT: 'The AI service took too long, so I used basic keyword understanding.',
  NETWORK: 'The AI service is unreachable, so I used basic keyword understanding.',
  EMPTY: 'The AI service gave no answer, so I used basic keyword understanding.',
  BAD_OUTPUT: 'The AI reply could not be used safely, so I used basic keyword understanding.',
  MODEL_UNAVAILABLE: 'The AI model is unavailable, so I used basic keyword understanding.',
};

export interface AskInputShape { message?: string; conversationId?: string; area?: string; refresh?: boolean }

@Injectable()
export class FinderConversationService {
  private readonly logger = new Logger('SmartFoodFinder');
  private readonly conversations = new Map<string, Conversation>();
  private readonly inFlight = new Set<string>();
  private readonly rate = new Map<string, number[]>();

  constructor(
    @Inject(GeminiFinderService) private readonly gemini: GeminiFinderService,
    @Inject(RecommendationEngine) private readonly engine: RecommendationEngine,
    @Inject(DatabaseService) private readonly database: DatabaseService,
  ) {}

  status() { return { aiConfigured: this.gemini.configured, nearBudgetPercent: 15 }; }

  end(p: AuthenticatedPrincipal, conversationId: string) { this.conversations.delete(this.key(p, conversationId)); return { ended: true }; }

  private key(p: AuthenticatedPrincipal, id: string) { return `${p.userId}:${p.sessionId}:${id}`; }

  private sweep(now = Date.now()) {
    for (const [k, c] of this.conversations) if (c.expiresAt <= now) this.conversations.delete(k);
    for (const [k, times] of this.rate) { const live = times.filter((t) => t > now - 60_000); if (live.length) this.rate.set(k, live); else this.rate.delete(k); }
  }

  private limit(userId: string) {
    const now = Date.now(), times = (this.rate.get(userId) ?? []).filter((t) => t > now - 60_000);
    if (times.length >= perMinute()) throw new HttpException('You are sending messages too quickly. Please wait a moment.', 429);
    times.push(now); this.rate.set(userId, times);
  }

  async ask(p: AuthenticatedPrincipal, input: AskInputShape) {
    this.sweep();
    const message = (input.message ?? '').trim();
    if (!message && !input.refresh) throw new UnprocessableEntityException('Tell me what you would like to eat.');
    const id = input.conversationId ?? randomUUID();
    const key = this.key(p, id);
    const existing = input.conversationId ? this.conversations.get(key) : undefined;
    if (input.conversationId && (!existing || existing.userId !== p.userId)) throw new NotFoundException('This conversation has expired. Start a new search.');
    if (this.inFlight.has(key)) throw new ConflictException('Still working on your previous message.');
    if (!existing && this.conversations.size >= MAX_CONVERSATIONS) throw new HttpException('The food finder is busy. Please try again shortly.', 503);
    this.limit(p.userId);
    this.inFlight.add(key);
    try {
      const conv: Conversation = existing ?? { userId: p.userId, intent: null, shown: [], area: null, expiresAt: 0, turns: 0 };
      const previousIntent = conv.intent; // before this message changes it
      conv.expiresAt = Date.now() + TTL_MS; conv.turns++;
      if (input.area) conv.area = input.area;
      this.conversations.set(key, conv);

      let update: IntentUpdate = {};
      let interpreter: 'gemini' | 'rules' | 'none' = 'none';
      let aiNotice: string | null = null;
      if (message) {
        if (this.gemini.configured) {
          try { update = await this.gemini.extract(message, conv.intent, conv.shown.map((r) => `${r.name} — ${r.restaurantName}`)); interpreter = 'gemini'; }
          catch (e) {
            const code = e instanceof GeminiError ? e.code : 'BAD_OUTPUT';
            this.logger.warn(`Gemini unavailable (${code}); using rule parser`); // never logs the message text
            aiNotice = AI_NOTICE[code] ?? AI_NOTICE.BAD_OUTPUT;
          }
        } else aiNotice = AI_NOTICE.NOT_CONFIGURED;
        if (interpreter !== 'gemini') { update = parseMessage(message); interpreter = 'rules'; }
        else if (!Object.keys(update).length) { update = parseMessage(message); }
      }

      const base = { conversationId: id, interpreter, aiNotice, expiresAt: new Date(conv.expiresAt).toISOString() };

      // Picking a shown recommendation needs no new search.
      if (update.selectIndex && conv.shown[update.selectIndex - 1]) {
        const selected = conv.shown[update.selectIndex - 1];
        return { ...base, status: 'SELECTED' as const, intent: conv.intent, intentSummary: conv.intent ? describeIntent(conv.intent) : null,
          reply: selected.matchType === 'NEAR_BUDGET'
            ? `${selected.name} from ${selected.restaurantName} is ${rupee(selected.budgetDifferencePaise!)} above your budget. Add it anyway?`
            : `Adding ${selected.name} from ${selected.restaurantName} to your cart — I'll check the latest price first.`,
          selected, requiresBudgetConfirmation: selected.matchType === 'NEAR_BUDGET', result: null };
      }

      // "Show cheaper options": strictly cheaper than the cheapest in-budget option already shown.
      if (update.cheaper) {
        // Cheaper than the cheapest matching dish shown (or, with no matches, the cheapest alternative).
        const exactShown = conv.shown.filter((r) => r.matchType === 'EXACT');
        const inBudget = (exactShown.length ? exactShown : conv.shown.filter((r) => r.matchType !== 'NEAR_BUDGET')).map((r) => r.pricing.totalPaise);
        if (inBudget.length) update.budgetPaise = Math.max(100, Math.min(...inBudget) - 100);
        update.sort = 'cheapest';
      }
      const intent = applyUpdate(conv.intent, update);

      if (update.clarificationQuestion && !hasSearchCriteria(intent)) {
        conv.intent = intent;
        return { ...base, status: 'NEEDS_CLARIFICATION' as const, reply: update.clarificationQuestion, intent, intentSummary: null, result: null };
      }
      if (!hasSearchCriteria(intent)) {
        conv.intent = intent;
        return { ...base, status: 'NEEDS_CLARIFICATION' as const, reply: 'What are you in the mood for? Tell me a dish, a budget, a taste (like spicy or creamy) or a nutrition goal.', intent, intentSummary: null, result: null };
      }
      conv.intent = intent;
      if (!conv.area) {
        return { ...base, status: 'NEEDS_AREA' as const, intent, intentSummary: describeIntent(intent),
          reply: 'Which area should I deliver to? Delivery fees depend on it, so I need it to show real totals.', areas: await this.areas(), result: null };
      }
      let result: FinderResult;
      try {
        result = await this.engine.recommend(intent, conv.area);
        // "Cheaper" with nothing cheaper: say so and keep the previous budget instead of an empty page.
        if (update.cheaper && previousIntent && !result.exact.length && !result.similar.length && conv.shown.some((r) => r.matchType !== 'NEAR_BUDGET')) {
          const pool = conv.shown.filter((r) => r.matchType === 'EXACT');
          const lowest = Math.min(...(pool.length ? pool : conv.shown.filter((r) => r.matchType !== 'NEAR_BUDGET')).map((r) => r.pricing.totalPaise));
          intent.budgetPaise = previousIntent.budgetPaise;
          result = await this.engine.recommend(intent, conv.area);
          result = { ...result, summary: `${rupee(lowest)} is already the lowest total I can find for ${describeIntent(intent)} near you. Here are your options, cheapest first.` };
        }
      }
      catch (e) {
        if (e instanceof UnprocessableEntityException) { conv.area = null; return { ...base, status: 'NEEDS_AREA' as const, intent, intentSummary: describeIntent(intent), reply: 'I couldn\'t use that delivery area. Please pick one of these.', areas: await this.areas(), result: null }; }
        throw e;
      }
      conv.intent = intent;
      conv.shown = [...result.exact, ...result.similar, ...result.nearBudget];
      return { ...base, status: 'RESULTS' as const, reply: result.summary, intent, intentSummary: describeIntent(intent), result };
    } finally {
      this.inFlight.delete(key);
    }
  }

  private async areas() {
    const zones = await this.database.client.deliveryZone.findMany({ where: { isActive: true, restaurants: { some: { isEligible: true } } }, select: { id: true, name: true }, orderBy: { name: 'asc' } });
    return zones;
  }
}

const rupee = (p: number) => `₹${(p / 100).toFixed(p % 100 ? 2 : 0)}`;
