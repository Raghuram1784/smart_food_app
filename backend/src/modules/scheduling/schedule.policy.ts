import {BadRequestException,ConflictException} from '@nestjs/common';
import {Prisma} from '../../generated/prisma/client';
export interface ScheduleInput {deliveryMode?:'NOW'|'SCHEDULED';scheduledDeliveryAt?:string;}
const MINUTE=60000,IST=330*MINUTE;
export function scheduleSettings(){
 const fast=process.env.NODE_ENV==='development'&&process.env.SCHEDULE_DEMO_FAST==='true';
 return {fast,step:fast?1:15,lead:fast?1:10,horizonDays:7};
}
export function schedulePlan(r:any,at:Date,now=new Date()){
 const cfg=scheduleSettings(),t=at.getTime(),local=new Date(t+IST),minute=local.getUTCHours()*60+local.getUTCMinutes();
 const prep=cfg.fast?1:r.schedulePrepMinutes,travel=cfg.fast?1:Math.max(10,r.estimatedDeliveryMaxMinutes-r.schedulePrepMinutes);
 const pickup=new Date(t-travel*MINUTE),start=new Date(pickup.getTime()-prep*MINUTE);
 const startLocal=new Date(start.getTime()+IST),pickupLocal=new Date(pickup.getTime()+IST);
 if(!Number.isFinite(t)||local.getUTCSeconds()||local.getUTCMilliseconds()||minute%cfg.step||start.getTime()<now.getTime()+cfg.lead*MINUTE||t>now.getTime()+cfg.horizonDays*86400000)throw new ConflictException('Choose a future available delivery slot');
 const day=(d:Date)=>d.toISOString().slice(0,10);
 if(r.operatingStatus!=='OPEN'||!r.deliveryAvailability||!r.scheduleWeekdays.includes(local.getUTCDay())||day(startLocal)!==day(local)||day(pickupLocal)!==day(local)||startLocal.getUTCHours()*60+startLocal.getUTCMinutes()<r.scheduleOpenMinute||minute+5>r.scheduleCloseMinute)throw new ConflictException('This slot is outside restaurant operating hours');
 return {deliveryMode:'SCHEDULED',scheduledDeliveryAt:at,deliveryWindowStart:new Date(t-5*MINUTE),deliveryWindowEnd:new Date(t+5*MINUTE),preparationStartAt:start,expectedPickupAt:pickup,// Fast demo (1-min prep/travel) releases invitations at preparation start so the rider has the
 dispatchReleaseAt:cfg.fast?start:new Date(Math.max(start.getTime(),pickup.getTime()-5*MINUTE))}; // same pickup slack as normal mode's 5 minutes.
}
export function scheduleRequest(input:ScheduleInput){
 const mode=input.deliveryMode??'NOW';
 if(!['NOW','SCHEDULED'].includes(mode)||mode==='NOW'&&input.scheduledDeliveryAt||mode==='SCHEDULED'&&!input.scheduledDeliveryAt)throw new BadRequestException('Provide a delivery time only for Schedule for Later');
 if(mode==='SCHEDULED'&&!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(input.scheduledDeliveryAt!))throw new BadRequestException('Delivery time must be an ISO UTC timestamp');
 // Omit defaults so old immediate-checkout idempotency hashes still match.
 return mode==='NOW'?{}:{deliveryMode:mode,scheduledDeliveryAt:input.scheduledDeliveryAt};
}
export async function reserveSchedule(tx:Prisma.TransactionClient,restaurantId:string,input:ScheduleInput){
 scheduleRequest(input);if((input.deliveryMode??'NOW')==='NOW')return {};
 // Serialize all bookings for the restaurant; Serializable checkout retries conflicts.
 await tx.$queryRaw`SELECT id FROM "Restaurant" WHERE id=${restaurantId} FOR UPDATE`;
 const r=await tx.restaurant.findUniqueOrThrow({where:{id:restaurantId}});
 const plan=schedulePlan(r,new Date(input.scheduledDeliveryAt!));
 const booked=await tx.order.count({where:{restaurantId,scheduledDeliveryAt:plan.scheduledDeliveryAt,status:{notIn:['CANCELED','REJECTED']}}});
 if(booked>=r.scheduleCapacity)throw new ConflictException('This delivery slot is fully booked. Choose another time.');
 return plan;
}
export function preparationAllowed(o:any,now=new Date()){return o.deliveryMode!=='SCHEDULED'||!!o.preparationStartAt&&new Date(o.preparationStartAt)<=now;}
export function dispatchAllowed(o:any,now=new Date()){return o.deliveryMode!=='SCHEDULED'||!!o.dispatchReleaseAt&&new Date(o.dispatchReleaseAt)<=now;}
export function scheduleIndicator(o:any,now=new Date()):string|null{
 if(o.deliveryMode!=='SCHEDULED')return null;
 if(['CANCELED','REJECTED'].includes(o.status))return o.status;
 const end=new Date(o.deliveryWindowEnd),start=new Date(o.deliveryWindowStart);
 if(o.status==='DELIVERED')return o.actualDeliveryAt&&new Date(o.actualDeliveryAt)>=start&&new Date(o.actualDeliveryAt)<=end?'DELIVERED_WITHIN_WINDOW':'DELIVERED_OUTSIDE_WINDOW';
 if(now>end)return 'DELAYED';
 if(now<new Date(o.preparationStartAt))return 'SCHEDULED';
 if((now>=new Date(o.preparationStartAt)&&['AWAITING_PAYMENT','PENDING_RESTAURANT','ACCEPTED'].includes(o.status))||(now>=new Date(o.expectedPickupAt)&&!['PICKED_UP','OUT_FOR_DELIVERY'].includes(o.status))||(now>=start&&now>=new Date(o.expectedPickupAt)&&o.status!=='OUT_FOR_DELIVERY'))return 'AT_RISK'; // window-start rule only once pickup is due (an accelerated plan is shorter than the ±5-min window)
 if(o.status==='PREPARING')return 'PREPARING';
 return now<new Date(o.preparationStartAt)?'SCHEDULED':'ON_TRACK';
}
