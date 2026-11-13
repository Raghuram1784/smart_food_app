
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PricingModule } from '../pricing/pricing.module';

import { AiOrderingController } from './ai-ordering.controller';
import { GeminiIntentService } from './gemini-intent.service';
import { RecommendationService } from './recommendation.service';
import { AiConversationService } from './ai-conversation.service';

@Module({
  imports: [AuthModule, PricingModule],
  controllers: [AiOrderingController],
  providers: [
    GeminiIntentService,
    RecommendationService,
    AiConversationService,
  ],
})
export class AiOrderingModule {}
