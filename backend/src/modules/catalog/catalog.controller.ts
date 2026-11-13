import { SmartQuery } from './smart-query.dto';
import { SmartSearchService } from './smart-search.service';
import { Controller, Get, Inject, Query } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { CatalogService } from './catalog.service';
import { CatalogQuery } from '../../common/dto/catalog-query.dto';
@ApiTags('Catalog') @Controller('catalog')
export class CatalogController {
 constructor(@Inject(CatalogService) private readonly service:CatalogService,@Inject(SmartSearchService) private readonly smart:SmartSearchService){}
 @Get('smart-search') @ApiOperation({summary:'Available, serviceable single-meal quotes with strict final-payable budgets'})
 smartSearch(@Query() query:SmartQuery){return this.smart.search(query);}
 @Get('search') @ApiOperation({summary:'Paginated database-backed dish, restaurant, category and cuisine search'})
 search(@Query() query:CatalogQuery){return this.service.search(query);}
}
