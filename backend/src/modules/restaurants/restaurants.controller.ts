import { Controller, Get, Inject, Param, Query } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { CatalogService } from '../catalog/catalog.service';
import { CatalogQuery, IdParams } from '../../common/dto/catalog-query.dto';
@ApiTags('Restaurants') @Controller('restaurants')
export class RestaurantsController {
 constructor(@Inject(CatalogService) private readonly service:CatalogService){}
 @Get() @ApiOperation({summary:'List restaurants with bounded pagination'}) list(@Query() query:CatalogQuery){return this.service.restaurants(query);}
 @Get(':id') @ApiOperation({summary:'Restaurant details'}) details(@Param() params:IdParams){return this.service.restaurant(params.id);}
 @Get(':id/menu') @ApiOperation({summary:'Sectioned menu with availability and exact item prices'}) menu(@Param() params:IdParams){return this.service.menu(params.id);}
}
