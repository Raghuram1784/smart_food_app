import { Module } from '@nestjs/common';
import { CatalogModule } from '../catalog/catalog.module';
import { MenuController } from './menu.controller';
@Module({imports:[CatalogModule],controllers:[MenuController]})
export class MenuModule{}
