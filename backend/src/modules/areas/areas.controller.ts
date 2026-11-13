import { Controller, Get, Inject } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { CatalogService } from '../catalog/catalog.service';

@ApiTags('Areas')
@Controller('areas')
export class AreasController {
  constructor(@Inject(CatalogService) private readonly service: CatalogService) {}

  @Get()
  @ApiOperation({ summary: 'List active Hyderabad service areas with serviceable restaurant counts' })
  list() {
    return this.service.areas();
  }
}
