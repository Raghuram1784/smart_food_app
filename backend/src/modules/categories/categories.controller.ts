import { Controller, Get, Inject } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { CatalogService } from '../catalog/catalog.service';
@ApiTags('Categories') @Controller('categories')
export class CategoriesController {
 constructor(@Inject(CatalogService) private readonly service:CatalogService){}
 @Get() @ApiOperation({summary:'List categories'}) list(){return this.service.categories();}
}
