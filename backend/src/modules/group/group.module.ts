import { Body, Controller, Delete, Get, HttpCode, Inject, Module, NotFoundException, Param, ParseUUIDPipe, Post, Patch, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { ArrayMaxSize, ArrayUnique, IsArray, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Matches, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, CurrentUser, Roles, RolesGuard } from '../auth/auth.guards';
import type { AuthenticatedPrincipal } from '../auth/auth.types';
import { AuthModule } from '../auth/auth.module';
import { PricingModule } from '../pricing/pricing.module';
import { OperationsModule } from '../operations/operations.module';
import { CartPricingService } from '../commerce/cart-pricing.service';
import { GroupService } from './group.service';

class CreateGroupInput {
  @Matches(/^[a-z0-9-]{1,64}$/) restaurantId!: string;
  @IsUUID() addressId!: string;
  @IsOptional() @IsString() @MaxLength(60) name?: string;
  @IsOptional() @IsInt() @Min(30) @Max(240) lifetimeMinutes?: number;
}
class JoinGroupInput {
  @IsOptional() @IsString() @Length(20, 100) @Matches(/^[A-Za-z0-9_-]+$/) token?: string;
  @IsOptional() @IsString() @Length(4, 20) code?: string;
}
class AddGroupItemInput {
  @Matches(/^[a-z0-9-]{1,64}$/) menuItemId!: string;
  @IsInt() @Min(1) @Max(20) quantity!: number;
  @IsOptional() @IsUUID() variantId?: string;
  @IsArray() @ArrayMaxSize(10) @ArrayUnique() @IsUUID('all', { each: true }) addOnIds: string[] = [];
  @IsInt() @Min(1) expectedRevision!: number;
}
class UpdateGroupItemInput { @IsInt() @Min(1) @Max(20) quantity!: number; @IsInt() @Min(1) expectedRevision!: number; }
class RevisionQuery { @Type(() => Number) @IsInt() @Min(1) expectedRevision!: number; }
class VersionInput { @IsInt() @Min(1) expectedVersion!: number; }
class ProposeInput { @IsInt() @Min(100) @Max(100_000_000) proposedTotalPaise!: number; @IsInt() @Min(1) expectedVersion!: number; }
class CounterAnswerInput { @IsIn(['accept', 'decline']) answer!: 'accept' | 'decline'; @IsInt() @Min(1) expectedVersion!: number; }
class SwitchInput { @Matches(/^[a-z0-9-]{1,64}$/) restaurantId!: string; @IsInt() @Min(1) expectedVersion!: number; }
class GroupCheckoutInput { @IsUUID() proposalId!: string; @IsInt() @Min(1) expectedVersion!: number; @IsUUID() idempotencyKey!: string; }
class OwnerQuery { @IsOptional() @Matches(/^[a-z0-9-]{1,64}$/) restaurantId?: string; }
class OwnerResponseInput { @IsOptional() @IsInt() @Min(100) @Max(100_000_000) counterTotalPaise?: number; @IsOptional() @IsString() @MaxLength(300) note?: string; }

@ApiTags('Group orders') @ApiBearerAuth()
@Controller('groups') @UseGuards(AuthGuard, RolesGuard) @Roles('CUSTOMER')
class GroupController {
  constructor(@Inject(GroupService) private readonly groups: GroupService) {}
  @Post() @HttpCode(200) create(@CurrentUser() p: AuthenticatedPrincipal, @Body() b: CreateGroupInput) { return this.groups.create(p, b); }
  @Post('join') @HttpCode(200) join(@CurrentUser() p: AuthenticatedPrincipal, @Body() b: JoinGroupInput) { return this.groups.join(p, b); }
  @Get() mine(@CurrentUser() p: AuthenticatedPrincipal) { return this.groups.mine(p); }
  @Get(':id') get(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string) { return this.groups.get(p, id); }
  @Post(':id/invite') @HttpCode(200) invite(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string) { return this.groups.rotateInvite(p, id); }
  @Post(':id/items') @HttpCode(200) add(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Body() b: AddGroupItemInput) { return this.groups.addItem(p, id, b); }
  @Patch(':id/items/:itemId') update(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Param('itemId', ParseUUIDPipe) itemId: string, @Body() b: UpdateGroupItemInput) { return this.groups.updateItem(p, id, itemId, b); }
  @Delete(':id/items/:itemId') remove(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Param('itemId', ParseUUIDPipe) itemId: string, @Query() q: RevisionQuery) { return this.groups.removeItem(p, id, itemId, Number(q.expectedRevision)); }
  @Post(':id/leave') @HttpCode(200) leave(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string) { return this.groups.leave(p, id); }
  @Post(':id/lock') @HttpCode(200) lock(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Body() b: VersionInput) { return this.groups.lock(p, id, b.expectedVersion); }
  @Post(':id/unlock') @HttpCode(200) unlock(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Body() b: VersionInput) { return this.groups.unlock(p, id, b.expectedVersion); }
  @Post(':id/cancel') @HttpCode(200) cancel(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Body() b: VersionInput) { return this.groups.cancel(p, id, b.expectedVersion); }
  @Post(':id/proposals') @HttpCode(200) propose(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Body() b: ProposeInput) { return this.groups.propose(p, id, b); }
  @Post(':id/proposals/:proposalId/counter') @HttpCode(200) counter(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Param('proposalId', ParseUUIDPipe) pid: string, @Body() b: CounterAnswerInput) { return this.groups.respondToCounter(p, id, pid, b.answer === 'accept', b.expectedVersion); }
  @Get(':id/alternatives') alternatives(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string) { return this.groups.alternatives(p, id); }
  @Post(':id/switch') @HttpCode(200) switchRestaurant(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Body() b: SwitchInput) { return this.groups.switchRestaurant(p, id, b); }
  @Post(':id/checkout') @HttpCode(200) checkout(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Body() b: GroupCheckoutInput) { return this.groups.checkout(p, id, b); }
}

@ApiTags('Group orders') @ApiBearerAuth()
@Controller('restaurant/group-proposals') @UseGuards(AuthGuard, RolesGuard) @Roles('RESTAURANT_OWNER')
class OwnerGroupController {
  constructor(@Inject(GroupService) private readonly groups: GroupService) {}
  @Get() list(@CurrentUser() p: AuthenticatedPrincipal, @Query() q: OwnerQuery) { return this.groups.ownerList(p, q.restaurantId); }
  @Post(':id/:action') @HttpCode(200) respond(@CurrentUser() p: AuthenticatedPrincipal, @Param('id', ParseUUIDPipe) id: string, @Param('action') action: string, @Body() b: OwnerResponseInput) {
    if (!['accept', 'reject', 'counter'].includes(action)) throw new NotFoundException('Unknown action');
    return this.groups.ownerRespond(p, id, action as 'accept' | 'reject' | 'counter', b);
  }
}

@Module({ imports: [AuthModule, PricingModule, OperationsModule], controllers: [GroupController, OwnerGroupController], providers: [GroupService, CartPricingService] })
export class GroupModule {}
