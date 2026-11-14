import {ConflictException,ForbiddenException,Inject,Injectable,NotFoundException,UnauthorizedException} from '@nestjs/common';
import {DatabaseService} from '../../database/database.module';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {Prisma,OrderStatus} from '../../generated/prisma/client';
import {orderInclude} from '../commerce/commerce.store';
import {ACTIVE_ASSIGNMENT_STATUSES} from './assignment-status';
import {closeOffersForOrder,createOffersForOrder} from './dispatch.service';
import {issueHandoverInTx} from './handover.issue';

export const operationInclude={...orderInclude,paymentAttempts:true,assignment:{include:{rider:{select:{displayName:true}}}},restaurant:{select:{address:true,name:true}}};
export const transitions:Record<string,{from:OrderStatus;to:OrderStatus;event:string;role:'RESTAURANT_OWNER'|'DELIVERY_PARTNER'}>={
  accept:{from:'PENDING_RESTAURANT',to:'ACCEPTED',event:'ORDER_ACCEPTED',role:'RESTAURANT_OWNER'},
  reject:{from:'PENDING_RESTAURANT',to:'REJECTED',event:'ORDER_REJECTED',role:'RESTAURANT_OWNER'},
  'start-preparing':{from:'ACCEPTED',to:'PREPARING',event:'PREPARATION_STARTED',role:'RESTAURANT_OWNER'},
  ready:{from:'PREPARING',to:'READY_FOR_PICKUP',event:'ORDER_READY',role:'RESTAURANT_OWNER'},
  pickup:{from:'READY_FOR_PICKUP',to:'PICKED_UP',event:'ORDER_PICKED_UP',role:'DELIVERY_PARTNER'},
  'out-for-delivery':{from:'PICKED_UP',to:'OUT_FOR_DELIVERY',event:'OUT_FOR_DELIVERY',role:'DELIVERY_PARTNER'},
};
export function eligible(order:any){
  return order.paymentMethod==='RAZORPAY_TEST'
    ? order.paymentStatus==='PAID'&&order.paymentAttempts.some((a:any)=>a.status==='CAPTURED'&&a.environment==='TEST'&&a.amountPaise===order.finalPayablePaise&&a.providerPaymentId)
    : ['development','test'].includes(process.env.NODE_ENV??'')&&process.env.DEMO_FULFILLMENT_ENABLED==='true'&&order.paymentStatus==='UNPAID';
}
// Shared by checkout/payment/operations: enqueue inside their existing transaction.
export async function queueEvent(tx:Prisma.TransactionClient,eventId:string){
  await tx.outboxEvent.create({data:{eventId}});
}
@Injectable()
export class OperationsService {
  constructor(@Inject(DatabaseService) readonly database:DatabaseService){}
  async current(tx:Prisma.TransactionClient,p:AuthenticatedPrincipal,role:string){
    const session=await tx.authSession.findFirst({where:{id:p.sessionId,userId:p.userId,revokedAt:null,expiresAt:{gt:new Date()},user:{status:'ACTIVE',roles:{some:{roleName:role as any}}}}});
    if(!session)throw new UnauthorizedException('Session or role is no longer active');
  }
  async access(tx:Prisma.TransactionClient,p:AuthenticatedPrincipal,o:any,role:string){
    if(!p.roles.includes(role as any))throw new ForbiddenException('Role not permitted');
    await this.current(tx,p,role);
    if(role==='RESTAURANT_OWNER'&&!await tx.restaurantMembership.findFirst({where:{userId:p.userId,restaurantId:o.restaurantId,status:'ACTIVE',membershipRole:'OWNER'}}))throw new ForbiddenException('No active ownership for this restaurant');
    if(role==='DELIVERY_PARTNER'&&o.assignment?.riderId!==p.userId)throw new ForbiddenException('Delivery is not assigned to you');
    if(role==='CUSTOMER'&&o.customerId!==p.userId)throw new NotFoundException('Order not found');
  }
  present(o:any,role:string){
    const {paymentAttempts,requestHash,idempotencyKey,pricingSnapshot,customerId,...safe}=o;
    if(role!=='CUSTOMER'&&role!=='DELIVERY_PARTNER')delete safe.deliveryAddressSnapshot;
    const actions=Object.entries(transitions).filter(([action,t])=>t.role===role&&t.from===o.status&&(action!=='accept'||eligible(o))).map(([a])=>a);
    if(role==='DELIVERY_PARTNER'&&o.status==='OUT_FOR_DELIVERY')actions.push('arrived','complete-handover');
    return {...safe,availableActions:actions,paymentEligible:eligible(o)};
  }
  async detail(p:AuthenticatedPrincipal,id:string,role:string){return this.database.client.$transaction(async tx=>{
    const o=await tx.order.findUnique({where:{id},include:operationInclude});if(!o)throw new NotFoundException('Order not found');await this.access(tx,p,o,role);return this.present(o,role);
  });}
  async list(p:AuthenticatedPrincipal,role:string,page=1){return this.database.client.$transaction(async tx=>{
    await this.current(tx,p,role);
    const where:Prisma.OrderWhereInput=role==='ADMIN'?{status:{in:['READY_FOR_PICKUP','PICKED_UP','OUT_FOR_DELIVERY','DELIVERED']}}:role==='DELIVERY_PARTNER'?{assignment:{riderId:p.userId}}:{restaurant:{memberships:{some:{userId:p.userId,status:'ACTIVE',membershipRole:'OWNER'}}}};
    const items=await tx.order.findMany({where,include:operationInclude,orderBy:[{updatedAt:'desc'},{id:'desc'}],skip:(page-1)*20,take:20});
    return {items:items.map(o=>this.present(o,role)),total:await tx.order.count({where}),page};
  });}
  async riders(p:AuthenticatedPrincipal){return this.database.client.$transaction(async tx=>{
    await this.current(tx,p,'ADMIN');return tx.user.findMany({where:{status:'ACTIVE',roles:{some:{roleName:'DELIVERY_PARTNER'}},riderAssignments:{none:{status:{in:ACTIVE_ASSIGNMENT_STATUSES}}}},select:{id:true,displayName:true},orderBy:{displayName:'asc'},take:100});
  });}
  async mutate(p:AuthenticatedPrincipal,id:string,action:string,expectedVersion:number,reason?:string,riderId?:string){
    if(action==='deliver'||action==='complete-handover')throw new ConflictException('Customer handover PIN verification is required');
    const rule=transitions[action];if(!rule&&action!=='assign')throw new NotFoundException('Unknown operation');
    return this.database.client.$transaction(async tx=>{
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid FOR UPDATE`;
      const o=await tx.order.findUnique({where:{id},include:operationInclude});if(!o)throw new NotFoundException('Order not found');
      const role=action==='assign'?'ADMIN':rule.role;await this.access(tx,p,o,role);
      if(o.version!==expectedVersion)throw new ConflictException('Order changed. Refresh before retrying.');
      if(o.status!==(action==='assign'?'READY_FOR_PICKUP':rule.from))throw new ConflictException('This action is not available at the current order status');
      if(action==='accept'&&!eligible(o))throw new ConflictException('Verified captured payment or explicitly enabled development fulfillment is required');
      if(action==='reject'&&(!reason||reason.trim().length<5))throw new ConflictException('Provide a rejection reason of at least 5 characters');
      if(action==='assign'){
        if(!riderId)throw new ConflictException('Choose an active rider');
        await tx.$queryRaw`SELECT id FROM "User" WHERE id=${riderId}::uuid FOR UPDATE`;
        const rider=await tx.user.findFirst({where:{id:riderId,status:'ACTIVE',roles:{some:{roleName:'DELIVERY_PARTNER'}}}});
        if(!rider||o.assignment||await tx.deliveryAssignment.count({where:{riderId,status:{in:ACTIVE_ASSIGNMENT_STATUSES}}}))throw new ConflictException('Rider unavailable or order already assigned');
        const assignment=await tx.deliveryAssignment.create({data:{orderId:id,riderId,assignedById:p.userId}});
        // Admin fallback: close open invitations and issue the customer OTP, exactly as an accepted invitation would.
        await closeOffersForOrder(tx,id);
        const issued=await issueHandoverInTx(tx,{id,status:o.status,assignment},p.userId,'ASSIGNMENT_ISSUED');
        if(!issued.ok)throw new ConflictException(issued.message);
      }
      const next=action==='assign'?o.status:rule.to,version=o.version+1;
      await tx.order.update({where:{id},data:{status:next,version,...(action==='reject'?{rejectionReason:reason!.trim(),refundReviewRequired:o.paymentStatus==='PAID'}:{})}});
      if(role==='DELIVERY_PARTNER')await tx.deliveryAssignment.update({where:{orderId:id},data:{status:next,...(action==='pickup'?{pickedUpAt:new Date()}:{})}});
      const event=await tx.orderEvent.create({data:{orderId:id,actorUserId:p.userId,eventType:action==='assign'?'RIDER_ASSIGNED':rule.event,previousStatus:o.status,newStatus:next,sequence:version,metadata:action==='reject'?{reason:reason!.trim(),refundReviewRequired:o.paymentStatus==='PAID'}:{}}});
      await queueEvent(tx,event.id);
      // Ready for pickup: invite every eligible online rider (no GPS, no admin step).
      if(action==='ready')await createOffersForOrder(tx,id);
      return this.present(await tx.order.findUniqueOrThrow({where:{id},include:operationInclude}),role);
    });
  }
}
