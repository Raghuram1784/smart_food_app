import { Body, Controller, Get, HttpCode, Inject, Module, Param, ParseUUIDPipe, Post, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsISO8601, IsNumber, IsOptional, Matches, Max, Min } from 'class-validator';
import { AuthGuard, CurrentUser, Roles, RolesGuard } from '../auth/auth.guards';
import type { AuthenticatedPrincipal } from '../auth/auth.types';
import { AuthModule } from '../auth/auth.module';
import { OperationsModule } from '../operations/operations.module';
import { TrackingService } from './tracking.service';

class FixInput {
  @IsNumber() @Min(-90) @Max(90) latitude!: number;
  @IsNumber() @Min(-180) @Max(180) longitude!: number;
  @IsNumber() @Min(0) @Max(100000) accuracyMeters!: number;
  @IsOptional() @IsNumber() headingDegrees?: number | null;
  @IsOptional() @IsNumber() speedMps?: number | null;
  @IsISO8601({ strict: true }) recordedAt!: string;
}
class PinInput {
  @IsNumber() @Min(-90) @Max(90) latitude!: number;
  @IsNumber() @Min(-180) @Max(180) longitude!: number;
  @IsOptional() @IsNumber() @Min(0) accuracyMeters?: number | null;
}
class RestaurantParam { @Matches(/^[a-z0-9-]{1,64}$/) id!: string; }

@ApiTags('Live tracking') @ApiBearerAuth()
@Controller('tracking') @UseGuards(AuthGuard, RolesGuard)
class TrackingController {
  constructor(@Inject(TrackingService) private readonly tracking: TrackingService) {}
  /** Assigned rider publishes a real device GPS fix for an active delivery. */
  @Post('orders/:id/location') @HttpCode(200) @Roles('DELIVERY_PARTNER')
  publish(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Body() b: FixInput) { return this.tracking.publish(p, id, b); }
  /** Customer of the order, assigned rider, restaurant owner or admin. */
  @Get('orders/:id') @Roles('CUSTOMER', 'DELIVERY_PARTNER', 'RESTAURANT_OWNER', 'ADMIN')
  view(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string) { return this.tracking.view(p, id); }
  /** Customer confirms the drop pin for this order (GPS or map). */
  @Put('orders/:id/destination') @Roles('CUSTOMER')
  destination(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Body() b: PinInput) { return this.tracking.setDestination(p, id, b); }
  /** Restaurant owner confirms the outlet's pickup point. */
  @Put('restaurants/:id/pickup-location') @Roles('RESTAURANT_OWNER')
  pickup(@CurrentUser() p: AuthenticatedPrincipal, @Param() r: RestaurantParam, @Body() b: PinInput) { return this.tracking.setPickupLocation(p, r.id, b); }
}

@Module({ imports: [AuthModule, OperationsModule], controllers: [TrackingController], providers: [TrackingService], exports: [TrackingService] })
export class TrackingModule {}
