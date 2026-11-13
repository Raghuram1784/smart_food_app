import { Module } from '@nestjs/common';
import { CatalogModule } from '../catalog/catalog.module';
import { CuisinesController } from './cuisines.controller';
@Module({imports:[CatalogModule],controllers:[CuisinesController]})
export class CuisinesModule{}
