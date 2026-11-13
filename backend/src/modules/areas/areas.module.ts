import { Module } from '@nestjs/common';
import { CatalogModule } from '../catalog/catalog.module';
import { AreasController } from './areas.controller';

@Module({
  imports: [CatalogModule],
  controllers: [AreasController],
})
export class AreasModule {}
