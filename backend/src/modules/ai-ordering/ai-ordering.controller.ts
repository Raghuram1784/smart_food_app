
import {
  Body,
  Controller,
  HttpCode,
  Inject,
  Post,
  SetMetadata,
  UseGuards,
} from '@nestjs/common';

import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import {
  AuthGuard,
  CurrentUser,
  Roles,
  RolesGuard,
} from '../auth/auth.guards';

import { AuthenticatedPrincipal } from '../auth/auth.types';

import { GeminiIntentService } from './gemini-intent.service';
import { RecommendationService } from './recommendation.service';
import { AiConversationService } from './ai-conversation.service';

import { InterpretInput } from './ai-ordering.dto';
import { RecommendationInput } from './recommendation.dto';
import { AskInput } from './ai-conversation.dto';

import {
  REQUEST_TIMEOUT_KEY,
} from '../../common/interceptors/response.interceptor';

@ApiTags('AI Food Ordering')
@ApiBearerAuth()
@Controller('ai')
@UseGuards(AuthGuard, RolesGuard)
@Roles('CUSTOMER')
export class AiOrderingController {
  constructor(
    @Inject(GeminiIntentService)
    private readonly service: GeminiIntentService,

    @Inject(RecommendationService)
    private readonly recommendations: RecommendationService,

    @Inject(AiConversationService)
    private readonly conversation: AiConversationService,
  ) {}

  // F1: Extract structured intent using Gemini.
  @Post('interpret')
  @HttpCode(200)
  interpret(@Body() input: InterpretInput) {
    return this.service.extract(input.message);
  }

  // F1: Retrieve verified food recommendations.
  @Post('recommend')
  @HttpCode(200)
  recommend(@Body() input: RecommendationInput) {
    return this.recommendations.recommend(
      input.intent,
      input.area,
    );
  }

  // F1: Multi-turn conversational food ordering.
  @Post('ask')
  @HttpCode(200)
  @SetMetadata(REQUEST_TIMEOUT_KEY, 20000)
  ask(
    @Body() input: AskInput,
    @CurrentUser() principal: AuthenticatedPrincipal,
  ) {
    return this.conversation.ask(
      input.message,
      input.area,
      principal,
      input.conversationId,
    );
  }
}
