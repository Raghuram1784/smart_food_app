import {HandoverService} from './handover.service';
import {CustomerHandoverController,CompleteHandoverInput,HandoverRateGuard} from './handover.controller';
import {Body,Controller,Get,HttpCode,Inject,Module,Param,Post,Query,UseGuards,ParseUUIDPipe,NotFoundException} from '@nestjs/common';
import {IsInt,IsOptional,IsString,IsUUID,Length,Min} from 'class-validator';
import {AuthModule} from '../auth/auth.module';
import {AuthGuard,CurrentUser,Roles,RolesGuard} from '../auth/auth.guards';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {OrderPage,UuidParam} from '../commerce/commerce.dto';
import {OperationsService} from './operations.service';
import {OrderGateway,OutboxDispatcher} from './realtime';
import {RiderPresenceController} from './rider-presence.controller';
import {RiderPresenceService} from './rider-presence.service';
import {DispatchService} from './dispatch.service';
class ActionInput {
  @IsInt() @Min(1) expectedVersion!:number;
  @IsOptional() @IsString() @Length(5,300) reason?:string;
}
class AssignmentInput extends ActionInput { @IsUUID() riderId!:string; }
@Controller('operations') @UseGuards(AuthGuard,RolesGuard)
class OperationsController {
  constructor(@Inject(OperationsService) readonly service:OperationsService,@Inject(HandoverService) readonly handover:HandoverService,@Inject(DispatchService) readonly dispatch:DispatchService){}
  @Get('delivery/offers') @Roles('DELIVERY_PARTNER') offers(@CurrentUser() p:AuthenticatedPrincipal){return this.dispatch.offers(p);}
  @Post('delivery/offers/:id/accept') @HttpCode(200) @Roles('DELIVERY_PARTNER') acceptOffer(@CurrentUser() p:AuthenticatedPrincipal,@Param() q:UuidParam){return this.dispatch.accept(p,q.id);}
  @Post('delivery/offers/:id/decline') @HttpCode(200) @Roles('DELIVERY_PARTNER') declineOffer(@CurrentUser() p:AuthenticatedPrincipal,@Param() q:UuidParam){return this.dispatch.decline(p,q.id);}
  @Post('delivery/orders/:id/arrived') @HttpCode(200) @Roles('DELIVERY_PARTNER') @UseGuards(HandoverRateGuard) arrived(@CurrentUser() p:AuthenticatedPrincipal,@Param() q:UuidParam){return this.handover.arrived(p,q.id);}
  @Get('restaurant/orders') @Roles('RESTAURANT_OWNER') listOwner(@CurrentUser() p:AuthenticatedPrincipal,@Query() q:OrderPage){return this.service.list(p,'RESTAURANT_OWNER',q.page);}
  @Get('restaurant/orders/:id') @Roles('RESTAURANT_OWNER') owner(@CurrentUser() p:AuthenticatedPrincipal,@Param() q:UuidParam){return this.service.detail(p,q.id,'RESTAURANT_OWNER');}
  @Post('restaurant/orders/:id/:action') @HttpCode(200) @Roles('RESTAURANT_OWNER') kitchen(@CurrentUser() p:AuthenticatedPrincipal,@Param('id',new ParseUUIDPipe()) id:string,@Param('action') action:string,@Body() b:ActionInput){if(!['accept','reject','start-preparing','ready'].includes(action))throw new NotFoundException();return this.service.mutate(p,id,action,b.expectedVersion,b.reason);}
  @Get('delivery/orders') @Roles('DELIVERY_PARTNER') listRider(@CurrentUser() p:AuthenticatedPrincipal,@Query() q:OrderPage){return this.service.list(p,'DELIVERY_PARTNER',q.page);}
  @Get('delivery/orders/:id') @Roles('DELIVERY_PARTNER') rider(@CurrentUser() p:AuthenticatedPrincipal,@Param() q:UuidParam){return this.service.detail(p,q.id,'DELIVERY_PARTNER');}
  @Post('delivery/orders/:id/complete-handover') @HttpCode(200) @Roles('DELIVERY_PARTNER') @UseGuards(HandoverRateGuard) complete(@CurrentUser() p:AuthenticatedPrincipal,@Param() q:UuidParam,@Body() b:CompleteHandoverInput){return this.handover.complete(p,q.id,b.pin,b.expectedVersion);}
  @Post('delivery/orders/:id/:action') @HttpCode(200) @Roles('DELIVERY_PARTNER') deliver(@CurrentUser() p:AuthenticatedPrincipal,@Param('id',new ParseUUIDPipe()) id:string,@Param('action') action:string,@Body() b:ActionInput){if(!['pickup','out-for-delivery','deliver'].includes(action))throw new NotFoundException();return this.service.mutate(p,id,action,b.expectedVersion);}
  @Get('dispatch/orders') @Roles('ADMIN') listDispatch(@CurrentUser() p:AuthenticatedPrincipal,@Query() q:OrderPage){return this.service.list(p,'ADMIN',q.page);}
  @Get('dispatch/riders') @Roles('ADMIN') riders(@CurrentUser() p:AuthenticatedPrincipal){return this.service.riders(p);}
  @Post('dispatch/orders/:id/assign') @HttpCode(200) @Roles('ADMIN') assign(@CurrentUser() p:AuthenticatedPrincipal,@Param() q:UuidParam,@Body() b:AssignmentInput){return this.service.mutate(p,q.id,'assign',b.expectedVersion,undefined,b.riderId);}
}
@Module({imports:[AuthModule],controllers:[CustomerHandoverController,OperationsController,RiderPresenceController],providers:[HandoverService,HandoverRateGuard,OperationsService,OrderGateway,OutboxDispatcher,RiderPresenceService,DispatchService],exports:[RiderPresenceService,OrderGateway]})
export class OperationsModule{}
