import {Body,Controller,Get,HttpCode,Inject,Injectable,Module,OnModuleDestroy,OnModuleInit,Param,Post,Query,UseGuards,NotFoundException,ConflictException} from '@nestjs/common';
import {IsOptional,Matches} from 'class-validator';
import {DatabaseService} from '../../database/database.module';
import {AuthModule} from '../auth/auth.module';
import {AuthGuard,Roles,RolesGuard,CurrentUser} from '../auth/auth.guards';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {CommerceStore} from '../commerce/commerce.store';
import {RestaurantParam,UuidParam,VersionInput} from '../commerce/commerce.dto';
import {schedulePlan,scheduleSettings,scheduleIndicator,dispatchAllowed} from './schedule.policy';
import {eligibleRiderWhere} from '../operations/rider-presence.service';
import {createOffersForOrder,closeOffersForOrder} from '../operations/dispatch.service';
class SlotQuery { @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) date?:string; }
@Injectable()
export class SchedulingService implements OnModuleInit,OnModuleDestroy {
 timer?:NodeJS.Timeout;running=false;stopped=false;
 constructor(@Inject(DatabaseService) readonly database:DatabaseService,@Inject(CommerceStore) readonly store:CommerceStore){}
 onModuleInit(){this.timer=setInterval(()=>void this.tick(),5000);this.timer.unref();void this.tick();}
 async onModuleDestroy(){this.stopped=true;if(this.timer)clearInterval(this.timer);while(this.running)await new Promise(r=>setTimeout(r,20));}
 async slots(restaurantId:string,date?:string){
  const r=await this.database.client.restaurant.findUnique({where:{id:restaurantId}});if(!r)throw new NotFoundException('Restaurant not found');
  const now=new Date(),cfg=scheduleSettings(),today=new Date(now.getTime()+330*60000).toISOString().slice(0,10);
  const dates=Array.from({length:7},(_,i)=>new Date(Date.parse(today+'T00:00:00Z')+i*86400000).toISOString().slice(0,10));
  const selected=date??dates[0];if(!dates.includes(selected))throw new ConflictException('Choose a date within the next seven days');
  const begin=new Date(selected+'T00:00:00+05:30');
  const rows=await this.database.client.order.groupBy({by:['scheduledDeliveryAt'],where:{restaurantId,scheduledDeliveryAt:{gte:begin,lt:new Date(begin.getTime()+86400000)},status:{notIn:['CANCELED','REJECTED']}},_count:{_all:true}});
  const used=new Map(rows.map(x=>[x.scheduledDeliveryAt!.getTime(),x._count._all]));
  const slots:any[]=[];
  for(let minute=0;minute<1440;minute+=cfg.step){try{const plan=schedulePlan(r,new Date(begin.getTime()+minute*60000),now);const remaining=r.scheduleCapacity-(used.get(plan.scheduledDeliveryAt.getTime())??0);if(remaining>0)slots.push({...plan,remaining});}catch{/* Closed, too soon or outside hours. */}}
  return {restaurantId,timeZone:'Asia/Kolkata',dates,date:selected,slots,serverTime:now,demoFast:cfg.fast,policy:{openMinute:r.scheduleOpenMinute,closeMinute:r.scheduleCloseMinute,preparationMinutes:cfg.fast?1:r.schedulePrepMinutes,slotCapacity:r.scheduleCapacity},notice:'Target window, not a guarantee. Estimates use restaurant timing, not live GPS.'};
 }
 async upcoming(p:AuthenticatedPrincipal){
  const eligible=await this.database.client.user.findFirst({where:{id:p.userId,...eligibleRiderWhere(new Date())},select:{id:true}});
  if(!eligible)return {items:[]};
  const rows=await this.database.client.order.findMany({where:{deliveryMode:'SCHEDULED',status:{in:['ACCEPTED','PREPARING','READY_FOR_PICKUP']},dispatchReleaseAt:{gt:new Date()},assignment:{is:null}},select:{restaurantName:true,scheduledDeliveryAt:true,deliveryWindowStart:true,deliveryWindowEnd:true,expectedPickupAt:true},orderBy:{expectedPickupAt:'asc'},take:20});
  return {items:rows.map(r=>({...r,deliveryMode:'SCHEDULED'}))};
 }
 cancel(p:AuthenticatedPrincipal,id:string,expectedVersion:number){return this.store.run(p,async tx=>{
  await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid FOR UPDATE`;
  const o=await tx.order.findFirst({where:{id,customerId:p.userId}});if(!o)throw new NotFoundException('Order not found');
  if(o.deliveryMode!=='SCHEDULED')throw new ConflictException('Only scheduled orders can be canceled here');
  if(o.status==='CANCELED')return {id,status:o.status,version:o.version};
  if(o.version!==expectedVersion||!['AWAITING_PAYMENT','PENDING_RESTAURANT','ACCEPTED'].includes(o.status)||new Date()>=o.preparationStartAt!)throw new ConflictException('Cancellation closes when preparation is due. Contact the restaurant.');
  const changed=await tx.order.update({where:{id},data:{status:'CANCELED',version:{increment:1},refundReviewRequired:o.paymentStatus==='PAID'}});
  await closeOffersForOrder(tx,id);
  const event=await tx.orderEvent.create({data:{orderId:id,actorUserId:p.userId,eventType:'SCHEDULE_CANCELED',previousStatus:o.status,newStatus:'CANCELED',sequence:changed.version,metadata:{refundReviewRequired:changed.refundReviewRequired}}});
  await tx.outboxEvent.create({data:{eventId:event.id}});return {id,status:changed.status,version:changed.version,refundReviewRequired:changed.refundReviewRequired};
 });}
 async tick(now=new Date()){
  if(this.running||this.stopped)return;this.running=true;
  try{
   // No in-memory jobs: every sweep derives due work from committed PostgreSQL rows.
   const rows=await this.database.client.order.findMany({where:{deliveryMode:'SCHEDULED',status:{notIn:['DELIVERED','CANCELED','REJECTED']},preparationStartAt:{lte:now}},select:{id:true}});
   for(const row of rows){if(this.stopped)break;await this.database.client.$transaction(async tx=>{
    await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${row.id}::uuid FOR UPDATE`;
    let o=await tx.order.findUniqueOrThrow({where:{id:row.id}});if(['DELIVERED','CANCELED','REJECTED'].includes(o.status))return;
    const types:string[]=[];
    if(o.preparationStartAt!<=now)types.push('SCHEDULE_PREPARATION_DUE');
    const indicator=scheduleIndicator(o,now);if(indicator==='AT_RISK')types.push('SCHEDULE_AT_RISK');if(indicator==='DELAYED')types.push('SCHEDULE_DELAYED');
    if(o.status==='READY_FOR_PICKUP'&&dispatchAllowed(o,now))types.push('SCHEDULE_DISPATCH_DUE');
    for(const eventType of types){
     if(await tx.orderEvent.findUnique({where:{orderId_eventType:{orderId:o.id,eventType}}}))continue;
     if(eventType==='SCHEDULE_DISPATCH_DUE')await createOffersForOrder(tx,o.id,now);
     o=await tx.order.update({where:{id:o.id},data:{version:{increment:1}}});
     const e=await tx.orderEvent.create({data:{orderId:o.id,eventType,previousStatus:o.status,newStatus:o.status,sequence:o.version,metadata:{scheduled:true}}});
     await tx.outboxEvent.create({data:{eventId:e.id}});
    }
   });}
  }catch{/* Durable work stays pending after an outage; retry next sweep. */}finally{this.running=false;}
 }
}
@Controller() @UseGuards(AuthGuard,RolesGuard)
class SchedulingController {
 constructor(@Inject(SchedulingService) readonly service:SchedulingService){}
 @Get('operations/delivery/upcoming-scheduled') @Roles('DELIVERY_PARTNER') upcoming(@CurrentUser() p:AuthenticatedPrincipal){return this.service.upcoming(p);}
 @Get('restaurants/:restaurantId/delivery-slots') @Roles('CUSTOMER') slots(@Param() p:RestaurantParam,@Query() q:SlotQuery){return this.service.slots(p.restaurantId,q.date);}
 @Post('orders/:id/cancel-scheduled') @HttpCode(200) @Roles('CUSTOMER') cancel(@CurrentUser() p:AuthenticatedPrincipal,@Param() q:UuidParam,@Body() b:VersionInput){return this.service.cancel(p,q.id,b.expectedVersion);}
}
@Module({imports:[AuthModule],controllers:[SchedulingController],providers:[SchedulingService,CommerceStore]})
export class SchedulingModule{}
