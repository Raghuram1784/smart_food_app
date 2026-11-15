import {reserveSchedule,scheduleRequest,scheduleIndicator,preparationAllowed} from '../scheduling/schedule.policy';
import {queueEvent} from '../operations/operations.service';
import {ConflictException,ForbiddenException,Inject,Injectable,NotFoundException} from '@nestjs/common';
import {randomBytes} from 'node:crypto';
import {Prisma} from '../../generated/prisma/client';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {CommerceStore,orderInclude} from './commerce.store';
import {CartPricingService,digest} from './cart-pricing.service';
import {PlaceOrderInput,OrderPage} from './commerce.dto';
import {demoCheckoutAllowed,paymentConfig} from '../payments/razorpay.provider';
const json=(value:unknown)=>JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
@Injectable()
export class OrdersService {
  constructor(@Inject(CommerceStore) readonly store:CommerceStore,@Inject(CartPricingService) readonly pricing:CartPricingService){}
  place(p:AuthenticatedPrincipal,input:PlaceOrderInput){
    if(input.paymentMethod==='RAZORPAY_TEST'){paymentConfig();}
    else if(!demoCheckoutAllowed())throw new ForbiddenException('No approved payment method is configured');
    const requestHash=digest({cartId:input.cartId,addressId:input.addressId,quoteId:input.quoteId,paymentMethod:input.paymentMethod,...scheduleRequest(input)});
    return this.store.run(p,async tx=>{
      const prior=await tx.order.findUnique({where:{customerId_idempotencyKey:{customerId:p.userId,idempotencyKey:input.idempotencyKey}},include:orderInclude});
      if(prior){if(prior.requestHash!==requestHash)throw new ConflictException('Idempotency key already used with different checkout details');return this.publicOrder(prior);}
      const cart=await this.store.cart(tx,p.userId);
      if(cart.id!==input.cartId)throw new NotFoundException('Cart not found');
      const quote=await tx.cartQuote.findFirst({where:{id:input.quoteId,cartId:cart.id,addressId:input.addressId}});
      if(!quote||quote.cartVersion!==cart.version||quote.expiresAt<=new Date())throw new ConflictException('Quote expired or cart changed. Review a fresh quote before placing your order.');
      const current=await this.pricing.calculate(tx,cart,input.addressId,quote.promotion??undefined);
      if(current.fingerprint!==quote.fingerprint)throw new ConflictException('Price or delivery details changed. Review a fresh quote and confirm again.');
      const schedule=await reserveSchedule(tx,cart.restaurantId!,input);
      const order=await tx.order.create({data:{...schedule,orderNumber:'FD-'+randomBytes(10).toString('hex').toUpperCase(),customerId:p.userId,restaurantId:cart.restaurantId!,restaurantName:cart.restaurant!.name,
        cartId:cart.id,cartVersion:cart.version,idempotencyKey:input.idempotencyKey,requestHash,deliveryAddressSnapshot:json(current.address),paymentMethod:input.paymentMethod,status:input.paymentMethod==='RAZORPAY_TEST'?'AWAITING_PAYMENT':'PENDING_RESTAURANT',
        itemSubtotalPaise:current.basePaise,customizationTotalPaise:current.variantPaise+current.addOnPaise,packagingPaise:current.packagingPaise,deliveryPaise:current.deliveryPaise,platformPaise:current.platformPaise,discountPaise:current.discountPaise,taxPaise:current.taxPaise,finalPayablePaise:current.finalPayablePaise,
        pricingPolicyVersion:current.pricingPolicyVersion,pricingSnapshot:json(current),
        items:{create:current.lines.map(l=>({menuItemId:l.menuItemId,name:l.name,imageKey:l.imageKey,baseUnitPaise:l.baseUnitPaise,quantity:l.quantity,lineTotalPaise:l.lineTotalPaise,
          ...(l.variant?{variantSnapshot:json(l.variant)}:{}),addOns:{create:l.addOns.map(a=>({originalAddOnId:a.id,name:a.name,unitPricePaise:a.pricePaise}))}}))},
        events:{create:{actorUserId:p.userId,eventType:'ORDER_CREATED',sequence:1,newStatus:input.paymentMethod==='RAZORPAY_TEST'?'AWAITING_PAYMENT':'PENDING_RESTAURANT',metadata:{paymentCollected:false}}}},include:orderInclude});
      await queueEvent(tx,order.events.find(e=>e.eventType==='ORDER_CREATED')!.id);
      await tx.cartItem.deleteMany({where:{cartId:cart.id}});
      await tx.cart.update({where:{id:cart.id},data:{restaurantId:null,version:{increment:1}}});
      return this.publicOrder(order);
    });
  }
  publicOrder(order:Prisma.OrderGetPayload<{include:typeof orderInclude}> & {paymentAttempts?:any[]},owner=false){
    const {idempotencyKey,requestHash,customerId,pricingSnapshot,paymentAttempts,...raw}=order;
    const safe={...raw,scheduleIndicator:scheduleIndicator(order)};
    if(owner){
      const {deliveryAddressSnapshot,...withoutPii}=safe;
      const actions: string[] = [];
      const isEligible = order.paymentMethod === 'RAZORPAY_TEST'
        ? order.paymentStatus === 'PAID' && ((order as any).paymentAttempts ?? []).some((a: any) => a.status === 'CAPTURED' && a.environment === 'TEST' && a.amountPaise === order.finalPayablePaise && a.providerPaymentId)
        : ['development', 'test'].includes(process.env.NODE_ENV ?? '') && process.env.DEMO_FULFILLMENT_ENABLED === 'true' && order.paymentStatus === 'UNPAID';

      if (order.status === 'PENDING_RESTAURANT') {
        if (isEligible) actions.push('accept');
        actions.push('reject');
      } else if (order.status === 'ACCEPTED' && preparationAllowed(order)) {
        actions.push('start-preparing');
      } else if (order.status === 'PREPARING') {
        actions.push('ready');
      }
      return {...withoutPii, availableActions: actions, paymentEligible: isEligible};
    }
    return safe;
  }
  list(p:AuthenticatedPrincipal,page:OrderPage){return this.store.run(p,async tx=>{
    const where={customerId:p.userId};
    const items=await tx.order.findMany({where,include:orderInclude,orderBy:[{createdAt:'desc'},{id:'desc'}],skip:(page.page-1)*page.limit,take:page.limit});
    return {items:items.map(o=>this.publicOrder(o)),total:await tx.order.count({where}),...page};
  });}
  detail(p:AuthenticatedPrincipal,id:string){return this.store.run(p,async tx=>{
    const order=await tx.order.findFirst({where:{id,customerId:p.userId},include:orderInclude});if(!order)throw new NotFoundException('Order not found');return this.publicOrder(order);
  });}
  inbox(p:AuthenticatedPrincipal,restaurantId:string,page:OrderPage){return this.store.database.client.$transaction(async tx=>{
    const member=await tx.restaurantMembership.findFirst({where:{userId:p.userId,restaurantId,status:'ACTIVE',membershipRole:'OWNER'}});
    if(!member)throw new ForbiddenException('No active owner membership for this restaurant');
    const where={restaurantId,...(page.deliveryMode?{deliveryMode:page.deliveryMode,status:{notIn:['CANCELED','REJECTED','DELIVERED'] as any}}:{})};
    const items=await tx.order.findMany({where,include:{...orderInclude,paymentAttempts:true},orderBy:[{createdAt:'desc'},{id:'desc'}],skip:(page.page-1)*page.limit,take:page.limit});
    return {items:items.map(o=>this.publicOrder(o,true)),total:await tx.order.count({where}),pendingCount:await tx.order.count({where:{restaurantId,status:'PENDING_RESTAURANT'}}),...page};
  },{isolationLevel:'RepeatableRead'});}
}
