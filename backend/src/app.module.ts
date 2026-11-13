
import { Module } from '@nestjs/common';

import { OperationsModule } from './modules/operations/operations.module';
import { AuthModule } from './modules/auth/auth.module';
import { CommerceModule } from './modules/commerce/commerce.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { PricingModule } from './modules/pricing/pricing.module';
import { DatabaseModule } from './database/database.module';
import { HealthModule } from './modules/health/health.module';
import { CatalogModule } from './modules/catalog/catalog.module';
import { RestaurantsModule } from './modules/restaurants/restaurants.module';
import { CategoriesModule } from './modules/categories/categories.module';
import { CuisinesModule } from './modules/cuisines/cuisines.module';
import { MenuModule } from './modules/menu/menu.module';
import { AreasModule } from './modules/areas/areas.module';
import { AiOrderingModule } from './modules/ai-ordering/ai-ordering.module';

@Module({
  imports: [
    OperationsModule,
    PaymentsModule,
    CommerceModule,
    AuthModule,
    PricingModule,
    DatabaseModule,
    HealthModule,
    CatalogModule,
    RestaurantsModule,
    CategoriesModule,
    CuisinesModule,
    MenuModule,
    AreasModule,
    AiOrderingModule,
  ],
})
export class AppModule {}
