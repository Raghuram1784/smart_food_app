import { Module } from '@nestjs/common';
import { CatalogModule } from '../catalog/catalog.module';
import { RestaurantsController } from './restaurants.controller';
@Module({imports:[CatalogModule],controllers:[RestaurantsController]})
export class RestaurantsModule{}
