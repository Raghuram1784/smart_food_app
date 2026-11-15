import {queueEvent} from '../operations/operations.service';
import {BadRequestException,ConflictException,ForbiddenException,Inject,Injectable,NotFoundException,ServiceUnavailableException} from '@nestjs/common';
import {createHash,createHmac,randomUUID,timingSafeEqual} from 'node:crypto';
import {DatabaseService} from '../../database/database.module';
import {PaymentAttempt,Prisma} from '../../generated/prisma/client';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {CommerceStore} from '../commerce/commerce.store';
import {PaymentProvider,paymentConfig,ProviderOrder,ProviderPayment} from './razorpay.provider';
import {PaymentVerifyInput} from './payments.dto';
export function validSignature(body:string|Buffer,signature:string,secret:string){if(!/^[a-fA-F0-9]{64}$/.test(signature))return false;return timingSafeEqual(createHmac('sha256',secret).update(body).digest(),Buffer.from(signature,'hex'));}
@Injectable()
export class PaymentsService {
  constructor(@Inject(DatabaseService) readonly database:DatabaseService,@Inject(CommerceStore) readonly store:CommerceStore,@Inject(PaymentProvider) readonly provider:PaymentProvider){}
  async owned(p:AuthenticatedPrincipal,orderId:string){
    const order=await this.database.client.order.findFirst({where:{id:orderId,customerId:p.userId}});if(!order)throw new NotFoundException('Order not found');return order;
  }
  async create(p:AuthenticatedPrincipal,orderId:string){
    const config=paymentConfig();
    const claim=await this.store.run(p,async tx=>{
      const order=await tx.order.findFirst({where:{id:orderId,customerId:p.userId}});
      if(!order)throw new NotFoundException('Order not found');
      if(order.paymentMethod!=='RAZORPAY_TEST')throw new ConflictException('This is a no-payment demo order. Create a new order with Razorpay Test Payment.');
      if(order.paymentStatus==='PAID'||order.paymentStatus==='REFUNDED')throw new ConflictException('This order cannot be charged again');
      if(order.status!=='AWAITING_PAYMENT'||order.currency!=='INR'||order.finalPayablePaise<100)throw new ConflictException('Order is not eligible for payment');
      const existing=await tx.paymentAttempt.findUnique({where:{orderId}});
      if(existing){if(existing.keyId!==config.keyId)throw new ConflictException('Payment was initiated under another test key; reconcile before continuing');return {attempt:existing,created:false};}
      const id=randomUUID();
      const attempt=await tx.paymentAttempt.create({data:{id,orderId,customerId:p.userId,amountPaise:order.finalPayablePaise,receipt:'p6_'+id.replaceAll('-',''),keyId:config.keyId}});
      await tx.order.update({where:{id:orderId},data:{paymentStatus:'PAYMENT_PENDING'}});
      return {attempt,created:true};
    });
    if(claim.created){
      try{await this.attach(claim.attempt,await this.provider.create(claim.attempt.amountPaise,claim.attempt.receipt));}
      catch{
        await this.database.client.paymentAttempt.updateMany({where:{id:claim.attempt.id,providerOrderId:null},data:{status:'CREATE_UNKNOWN',failureCode:'CREATE_OUTCOME_UNKNOWN'}});
        throw new ServiceUnavailableException('Payment setup needs reconciliation. Check status; do not create another order.');
      }
    }else if(!claim.attempt.providerOrderId){await this.recover(claim.attempt);}
    const attempt=await this.database.client.paymentAttempt.findUniqueOrThrow({where:{id:claim.attempt.id}});
    if(!attempt.providerOrderId)throw new ConflictException('Payment setup is pending. Check status and retry later.');
    await this.reconcile(attempt,false);
    const refreshed=await this.database.client.paymentAttempt.findUniqueOrThrow({where:{id:attempt.id}});
    if(refreshed.status==='CAPTURED')throw new ConflictException('Test payment is already confirmed');
    if(refreshed.status==='AUTHORIZED')throw new ConflictException('Payment is authorized; awaiting capture. Check status instead of paying again.');
    return {attemptId:refreshed.id,orderId,keyId:config.keyId,providerOrderId:refreshed.providerOrderId,amount:refreshed.amountPaise,currency:'INR',testMode:true};
  }
  async attach(a:PaymentAttempt,o:ProviderOrder){
    if(!/^order_[A-Za-z0-9]+$/.test(o.id)||o.receipt!==a.receipt||o.amount!==a.amountPaise||o.currency!==a.currency)throw new BadRequestException('Provider order does not match the stored amount');
    await this.database.client.paymentAttempt.updateMany({where:{id:a.id,providerOrderId:null},data:{providerOrderId:o.id,status:'READY',failureCode:null}});
  }
  async recover(a:PaymentAttempt){
    const matches=await this.provider.find(a.receipt);
    if(matches.length>1)throw new ConflictException('Multiple provider references require manual reconciliation');
    if(matches.length===1)await this.attach(a,matches[0]);
    // Absence is not proof a timed-out create failed. Never automatically POST a replacement.
  }
  async verify(p:AuthenticatedPrincipal,input:PaymentVerifyInput){
    const a=await this.database.client.paymentAttempt.findFirst({where:{id:input.attemptId,customerId:p.userId}});if(!a)throw new NotFoundException('Payment attempt not found');
    const config=paymentConfig();
    if(a.keyId!==config.keyId||!a.providerOrderId||a.providerOrderId!==input.razorpay_order_id||!validSignature(`${a.providerOrderId}|${input.razorpay_payment_id}`,input.razorpay_signature,config.secret))throw new BadRequestException('Invalid payment signature');
    const payment=await this.provider.payment(input.razorpay_payment_id);
    if(payment.id!==input.razorpay_payment_id)throw new BadRequestException('Payment identifier mismatch');
    await this.apply(a,payment);
    return this.status(p,a.orderId,false);
  }
  async apply(a:PaymentAttempt,payment:ProviderPayment){
    if(!/^pay_[A-Za-z0-9]+$/.test(payment.id)||payment.order_id!==a.providerOrderId||payment.amount!==a.amountPaise||payment.currency!==a.currency)throw new BadRequestException('Provider payment does not match this order');
    const captured=payment.status==='captured'&&payment.captured===true;
    if(payment.status==='captured'&&!captured)throw new BadRequestException('Capture confirmation is inconsistent');
    await this.database.client.$transaction(async tx=>{
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${a.orderId}::uuid FOR UPDATE`;
      const current=await tx.paymentAttempt.findUniqueOrThrow({where:{id:a.id}});
      if(current.status==='CAPTURED')return;
      const order=await tx.order.findUniqueOrThrow({where:{id:a.orderId}});
      if(order.paymentMethod!=='RAZORPAY_TEST'||order.finalPayablePaise!==a.amountPaise||order.currency!==a.currency)throw new ConflictException('Merchant payment details changed');
      const authorized=payment.status==='authorized';
      // Delayed failure cannot downgrade an authorization or capture.
      if(current.status==='AUTHORIZED'&&!captured&&!authorized)return;
      const state=captured?'CAPTURED':authorized?'AUTHORIZED':payment.status==='failed'?'FAILED':'READY';
      await tx.paymentAttempt.update({where:{id:a.id},data:{providerPaymentId:payment.id,status:state,lastVerificationAt:new Date(),failureCode:state==='FAILED'?'PROVIDER_PAYMENT_FAILED':null}});
      await tx.order.update({where:{id:a.orderId},data:{...(captured?{version:{increment:1},...(['CANCELED','REJECTED'].includes(order.status)?{refundReviewRequired:true}:{})}:{}),paymentStatus:captured?'PAID':authorized?'PAYMENT_AUTHORIZED':state==='FAILED'?'PAYMENT_FAILED':'PAYMENT_PENDING',...(captured&&order.status==='AWAITING_PAYMENT'?{status:'PENDING_RESTAURANT'}:{})}});
      if(captured){const event=await tx.orderEvent.upsert({where:{orderId_eventType:{orderId:a.orderId,eventType:'PAYMENT_CAPTURED'}},update:{},create:{orderId:a.orderId,eventType:'PAYMENT_CAPTURED',sequence:order.version+1,previousStatus:order.status,newStatus:order.status==='AWAITING_PAYMENT'?'PENDING_RESTAURANT':order.status,metadata:{provider:'RAZORPAY',environment:'TEST',attemptId:a.id}}});await queueEvent(tx,event.id);}
    });
  }
  async reconcile(a:PaymentAttempt,throttle=true){
    if(a.status==='CAPTURED')return;
    const config=paymentConfig();if(config.keyId!==a.keyId)throw new ConflictException('Test key changed; payment reconciliation required');
    if(throttle){const changed=await this.database.client.paymentAttempt.updateMany({where:{id:a.id,OR:[{lastVerificationAt:null},{lastVerificationAt:{lt:new Date(Date.now()-10000)}}]},data:{lastVerificationAt:new Date()}});if(!changed.count)return;}
    if(!a.providerOrderId){await this.recover(a);a=await this.database.client.paymentAttempt.findUniqueOrThrow({where:{id:a.id}});}
    if(!a.providerOrderId)return;
    const payments=await this.provider.payments(a.providerOrderId);
    const selected=payments.find(v=>v.status==='captured')??payments.find(v=>v.status==='authorized')??payments.at(-1);
    if(selected)await this.apply(a,selected);
  }
  async status(p:AuthenticatedPrincipal,orderId:string,refresh=true){
    await this.owned(p,orderId);
    let a=await this.database.client.paymentAttempt.findUnique({where:{orderId}}),verificationPending=false;
    if(a&&refresh){try{await this.reconcile(a);}catch{verificationPending=true;}}
    a=await this.database.client.paymentAttempt.findUnique({where:{orderId}});
    const order=await this.owned(p,orderId);
    return {orderId,paymentMethod:order.paymentMethod,paymentStatus:order.paymentStatus,orderStatus:order.status,amount:order.finalPayablePaise,currency:order.currency,testMode:order.paymentMethod==='RAZORPAY_TEST',verificationPending:verificationPending||!!a&&!a.providerOrderId,attempt:a?{id:a.id,status:a.status,lastVerificationAt:a.lastVerificationAt}:null};
  }
  async webhook(raw:Buffer,signature:string,eventId:string){
    const secret=process.env.RAZORPAY_WEBHOOK_SECRET;
    if(!secret||process.env.NODE_ENV==='production')throw new ForbiddenException('Test webhook receiver is not configured');
    if(!Buffer.isBuffer(raw)||!validSignature(raw,signature,secret))throw new BadRequestException('Invalid webhook signature');
    if(!/^[A-Za-z0-9_-]{1,100}$/.test(eventId))throw new BadRequestException('Missing or invalid event identifier');
    let body:any;try{body=JSON.parse(raw.toString('utf8'));}catch{throw new BadRequestException('Invalid webhook body');}
    if(!['payment.authorized','payment.captured','payment.failed','order.paid'].includes(body.event))return {ignored:true};
    const payment=body.payload?.payment?.entity,order=body.payload?.order?.entity;
    const orderId=payment?.order_id??order?.id,paymentId=payment?.id;
    if(typeof orderId!=='string'||!/^order_[A-Za-z0-9]+$/.test(orderId)||paymentId&&!/^pay_[A-Za-z0-9]+$/.test(paymentId))throw new BadRequestException('Malformed provider identifiers');
    const payloadHash=createHash('sha256').update(raw).digest('hex');
    const event=await this.database.client.paymentWebhookEvent.upsert({where:{providerEventId:eventId},update:{},create:{providerEventId:eventId,eventType:body.event,payloadHash,providerOrderId:orderId,providerPaymentId:paymentId}});
    if(event.payloadHash!==payloadHash)throw new ConflictException('Webhook event identifier reused');
    if(event.processedAt)return {received:true,duplicate:true};
    const a=await this.database.client.paymentAttempt.findUnique({where:{providerOrderId:orderId}});
    if(!a)throw new ServiceUnavailableException('Provider order is not reconciled yet');
    if(a.keyId!==paymentConfig().keyId)throw new ConflictException('Webhook belongs to another test key');
    // Signed events trigger a fresh provider read; payload claims alone never establish capture.
    if(paymentId)await this.apply(a,await this.provider.payment(paymentId));else await this.reconcile(a,false);
    await this.database.client.paymentWebhookEvent.update({where:{id:event.id},data:{status:'PROCESSED',processedAt:new Date()}});
    return {received:true};
  }
}
