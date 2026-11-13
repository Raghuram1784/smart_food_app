import { Controller, Get, Inject, Param } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { CatalogService } from '../catalog/catalog.service';
import { IdParams } from '../../common/dto/catalog-query.dto';
@ApiTags('Menu') @Controller('menu-items')
export class MenuController {
 constructor(@Inject(CatalogService) private readonly service:CatalogService){}
 @Get(':id') @ApiOperation({summary:'Menu item with available variants and add-ons'}) details(@Param() params:IdParams){return this.service.item(params.id);}
}
