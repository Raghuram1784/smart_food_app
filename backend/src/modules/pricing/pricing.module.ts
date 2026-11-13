import { Body, Controller, HttpCode, Inject, Module, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { QuoteInput, CompareInput } from './pricing.dto';
import { PricingService } from './pricing.service';

@ApiTags('Pricing') @Controller('pricing')
class PricingController {
  constructor(@Inject(PricingService) private readonly pricing: PricingService) {}
  @Post('quote') @HttpCode(200) @ApiOperation({summary:'Informational quote from current database records; never creates an order'})
  quote(@Body() input: QuoteInput) { return this.pricing.quote(input); }
  @Post('compare') @HttpCode(200) @ApiOperation({summary:'Compare 2–3 available items using the same pricing policy and locality'})
  compare(@Body() input: CompareInput) { return this.pricing.compare(input); }
}
@Module({ providers: [PricingService], controllers: [PricingController], exports: [PricingService] })
export class PricingModule {}
