import { Controller, Get, Inject } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { CatalogService } from '../catalog/catalog.service';
@ApiTags('Cuisines') @Controller('cuisines')
export class CuisinesController {
 constructor(@Inject(CatalogService) private readonly service:CatalogService){}
 @Get() @ApiOperation({summary:'List cuisines'}) list(){return this.service.cuisines();}
}
