import { Body, Controller, Delete, Get, HttpCode, Inject, Module, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, IsUUID, Matches, MaxLength } from 'class-validator';
import { AuthGuard, CurrentUser, Roles, RolesGuard } from '../auth/auth.guards';
import type { AuthenticatedPrincipal } from '../auth/auth.types';
import { AuthModule } from '../auth/auth.module';
import { PricingModule } from '../pricing/pricing.module';
import { RequestTimeout } from '../../common/interceptors/response.interceptor';
import { FinderConversationService } from './finder-conversation.service';
import { GeminiFinderService } from './gemini-finder.service';
import { RecommendationEngine } from './recommendation.engine';

export class FinderAskInput {
  @ApiPropertyOptional({ maxLength: 500 }) @IsOptional() @IsString() @MaxLength(500) message?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() conversationId?: string;
  /** Delivery area (locality id of the selected address). Needed for real fees. */
  @ApiPropertyOptional() @IsOptional() @IsString() @Matches(/^[a-z0-9-]{1,64}$/) area?: string;
  /** Re-run the remembered search (e.g. after choosing an area). */
  @ApiPropertyOptional() @IsOptional() @IsBoolean() refresh?: boolean;
}
class ConversationParam { @IsUUID() id!: string; }

@ApiTags('Smart Food Finder') @ApiBearerAuth()
@Controller('food-finder') @UseGuards(AuthGuard, RolesGuard) @Roles('CUSTOMER')
class FoodFinderController {
  constructor(@Inject(FinderConversationService) private readonly service: FinderConversationService) {}
  @Get('status') status() { return this.service.status(); }
  @Post('ask') @HttpCode(200) @RequestTimeout(25000)
  @ApiOperation({ summary: 'Natural-language food search: Gemini extracts intent; the catalog and pricing engine produce the results' })
  ask(@CurrentUser() p: AuthenticatedPrincipal, @Body() input: FinderAskInput) { return this.service.ask(p, input); }
  @Delete('conversations/:id') end(@CurrentUser() p: AuthenticatedPrincipal, @Param() ids: ConversationParam) { return this.service.end(p, ids.id); }
}

@Module({ imports: [AuthModule, PricingModule], controllers: [FoodFinderController], providers: [GeminiFinderService, RecommendationEngine, FinderConversationService], exports: [RecommendationEngine, GeminiFinderService] })
export class FoodFinderModule {}
