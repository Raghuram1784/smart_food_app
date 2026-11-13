import { PricingModule } from '../pricing/pricing.module';
import { SmartSearchService } from './smart-search.service';
import { Module } from '@nestjs/common';
import { CatalogService } from './catalog.service';
import { CatalogController } from './catalog.controller';
@Module({imports:[PricingModule],providers:[CatalogService,SmartSearchService],controllers:[CatalogController],exports:[CatalogService]})
export class CatalogModule{}
