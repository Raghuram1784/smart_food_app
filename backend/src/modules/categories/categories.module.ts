import { Module } from '@nestjs/common';
import { CatalogModule } from '../catalog/catalog.module';
import { CategoriesController } from './categories.controller';
@Module({imports:[CatalogModule],controllers:[CategoriesController]})
export class CategoriesModule{}
