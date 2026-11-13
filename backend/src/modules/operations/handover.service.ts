import {BadRequestException,ConflictException,HttpException,Inject,Injectable,NotFoundException,ServiceUnavailableException} from '@nestjs/common';
import {DatabaseService} from '../../database/database.module';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {DeliveryHandover,Prisma} from '../../generated/prisma/client';
import {OperationsService,operationInclude,queueEvent} from './operations.service';
import {generatePin,handoverConfig,matchesPin,openPin,pinVerifier,sealPin} from './handover.crypto';

@Injectable()
export class HandoverService {
  constructor(@Inject(DatabaseService) readonly database:DatabaseService,@Inject(OperationsService) readonly operations:OperationsService){}
  private async lockedOrder(tx:Prisma.TransactionClient,p:AuthenticatedPrincipal,id:string,role:'CUSTOMER'|'DELIVERY_PARTNER'){
    await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid FOR UPDATE`;
    let o=await tx.order.findUnique({where:{id},include:operationInclude});
    if(!o)throw new NotFoundException('Order not found');
    await this.operations.access(tx,p,o,role);
    if(o.assignment)await tx.$queryRaw`SELECT id FROM "DeliveryAssignment" WHERE id=${o.assignment.id}::uuid FOR UPDATE`;
    o=await tx.order.findUniqueOrThrow({where:{id},include:operationInclude});
    await this.operations.access(tx,p,o,role);
    await tx.$queryRaw`SELECT id FROM "DeliveryHandover" WHERE "orderId"=${id}::uuid FOR UPDATE`;
    return o;
  }
  private audit(tx:Prisma.TransactionClient,h:DeliveryHandover,p:AuthenticatedPrincipal,action:string){
    return tx.handoverAudit.create({data:{handoverId:h.id,challengeVersion:h.challengeVersion,actorUserId:p.userId,action}});
  }
  private sameAssignment(h:DeliveryHandover,o:any){return o.assignment?.id===h.assignmentId&&o.assignment?.riderId===h.boundRiderId;}
  private state(h:DeliveryHandover|null,o:any,now:Date){
    if(h?.consumedAt)return 'CONSUMED';
    if(o.status!=='OUT_FOR_DELIVERY'||o.assignment?.status!=='OUT_FOR_DELIVERY')return 'UNAVAILABLE';
    if(!h)return 'NOT_ISSUED';
    if(h.invalidatedAt||!this.sameAssignment(h,o))return 'INVALIDATED';
    if(h.lockedAt)return 'LOCKED';
    if(h.expiresAt<=now)return 'EXPIRED';
    return 'ACTIVE';
  }
  private async invalidateChanged(tx:Prisma.TransactionClient,h:DeliveryHandover|null,o:any,p:AuthenticatedPrincipal){
    if(h&&!h.consumedAt&&!h.invalidatedAt&&!this.sameAssignment(h,o)){
      h=await tx.deliveryHandover.update({where:{id:h.id},data:{invalidatedAt:new Date(),encryptedPin:null}});
      await this.audit(tx,h,p,'ASSIGNMENT_INVALIDATED');
    }
    return h;
  }
  private customerResponse(h:DeliveryHandover|null,o:any,now:Date){
    const config=handoverConfig(),state=this.state(h,o,now);
    let pin:string|undefined;
    if(state==='ACTIVE'&&h){
      if(h.keyVersion!==config.keyVersion||!h.encryptedPin)throw new ServiceUnavailableException('Secure handover requires reconciliation');
      pin=openPin(h.encryptedPin,h,config.encryptionKey);
      if(!matchesPin(pin,h,h.verifier,config.verifyKey))throw new ServiceUnavailableException('Secure handover requires reconciliation');
    }
    return {orderId:o.id,orderVersion:o.version,state,challengeVersion:h?.challengeVersion??null,
      issuedAt:h?.issuedAt??null,expiresAt:h?.expiresAt??null,nextIssueAt:h?.nextIssueAt??null,
      attemptsRemaining:h?Math.max(0,config.maxAttempts-h.failedAttempts):config.maxAttempts,
      issuesRemaining:Math.max(0,config.maxIssues-(h?.issueCount??0)),
      canIssue:o.status==='OUT_FOR_DELIVERY'&&o.assignment?.status==='OUT_FOR_DELIVERY'&&!h?.consumedAt&&(h?.issueCount??0)<config.maxIssues&&(!h||h.nextIssueAt<=now),
      ...(pin?{pin}:{}),consumedAt:h?.consumedAt??null};
  }
  async read(p:AuthenticatedPrincipal,id:string){return this.database.client.$transaction(async tx=>{
    const o=await this.lockedOrder(tx,p,id,'CUSTOMER');
    // GET never creates or rotates a challenge; assignment invalidation is enforced on verification too.
    const h=await tx.deliveryHandover.findUnique({where:{orderId:id}});
    return this.customerResponse(h,o,new Date());
  });}
  async issue(p:AuthenticatedPrincipal,id:string){
    const config=handoverConfig();
    const result=await this.database.client.$transaction(async tx=>{
      const o=await this.lockedOrder(tx,p,id,'CUSTOMER'),now=new Date();
      if(o.status!=='OUT_FOR_DELIVERY'||o.assignment?.status!=='OUT_FOR_DELIVERY')throw new ConflictException('Handover can be issued only while out for delivery');
      const assignment=o.assignment;
      const rider=await tx.user.findFirst({where:{id:assignment.riderId,status:'ACTIVE',roles:{some:{roleName:'DELIVERY_PARTNER'}}}});
      if(!rider)throw new ConflictException('Assigned delivery partner is not active');
      let old=await tx.deliveryHandover.findUnique({where:{orderId:id}});
      old=await this.invalidateChanged(tx,old,o,p);
      if(old?.consumedAt)return {error:409,message:'Handover already consumed'} as const;
      if(old&&(old.issueCount>=config.maxIssues||old.nextIssueAt>now))return {error:429,message:old.issueCount>=config.maxIssues?'Handover issuance limit reached; contact support':'Wait until nextIssueAt before issuing another PIN'} as const;
      let previous:string|undefined;
      if(old?.encryptedPin&&old.keyVersion===config.keyVersion)previous=openPin(old.encryptedPin,old,config.encryptionKey);
      let pin=generatePin();while(pin===previous)pin=generatePin();
      const b={orderId:id,assignmentId:assignment.id,boundRiderId:assignment.riderId,challengeVersion:(old?.challengeVersion??0)+1,issuedAt:now,expiresAt:new Date(now.getTime()+config.ttl*1000),keyVersion:config.keyVersion};
      if(old)await this.audit(tx,old,p,'REGENERATED_INVALIDATED');
      const data={...b,verifier:pinVerifier(pin,b,config.verifyKey),encryptedPin:sealPin(pin,b,config.encryptionKey),nextIssueAt:new Date(now.getTime()+config.cooldown*1000),issueCount:(old?.issueCount??0)+1,failedAttempts:0,lastFailedAt:null,lockedAt:null,lockedUntil:null,verifiedAt:null,consumedAt:null,invalidatedAt:null,completionExpectedVersion:null,completedOrderVersion:null};
      const h=old?await tx.deliveryHandover.update({where:{id:old.id},data}):await tx.deliveryHandover.create({data});
      await this.audit(tx,h,p,old?'REISSUED':'ISSUED');
      return {value:this.customerResponse(h,o,now)};
    });
    if('error' in result)throw new HttpException(result.message!,result.error!);
    return result.value;
  }
  async complete(p:AuthenticatedPrincipal,id:string,pin:string,expectedVersion:number){
    // Defense in depth for callers that bypass HTTP DTO validation.
    if(typeof pin!=='string'||!/^\d{6}$/.test(pin)||!Number.isInteger(expectedVersion)||expectedVersion<1)throw new BadRequestException('Provide a six-digit string PIN and current order version');
    const config=handoverConfig();
    const result=await this.database.client.$transaction(async tx=>{
      const o=await this.lockedOrder(tx,p,id,'DELIVERY_PARTNER'),now=new Date();
      let h=await tx.deliveryHandover.findUnique({where:{orderId:id}});
      h=await this.invalidateChanged(tx,h,o,p);
      if(h&&h.keyVersion!==config.keyVersion)throw new ServiceUnavailableException('Secure handover requires reconciliation');
      // A lost successful response can be retried only by the same current rider, same PIN and original expected version.
      if(o.status==='DELIVERED'&&h?.consumedAt&&this.sameAssignment(h,o)&&h.completionExpectedVersion===expectedVersion&&matchesPin(pin,h,h.verifier,config.verifyKey)){
        return {value:{...this.operations.present(o,'DELIVERY_PARTNER'),handoverVerified:true,alreadyCompleted:true}};
      }
      if(o.status!=='OUT_FOR_DELIVERY'||o.assignment?.status!=='OUT_FOR_DELIVERY'||o.version!==expectedVersion)return {error:409,message:'Order changed or delivery completion is not available'} as const;
      const state=this.state(h,o,now);
      if(!h||state!=='ACTIVE')return {error:state==='LOCKED'?429:409,message:state==='LOCKED'?'Handover is locked; customer must request a new PIN after cooldown':'An active customer handover PIN is required'} as const;
      if(!matchesPin(pin,h,h.verifier,config.verifyKey)){
        const attempts=h.failedAttempts+1,locked=attempts>=config.maxAttempts;
        const lockUntil=new Date(now.getTime()+config.lockSeconds*1000);
        const changed=await tx.deliveryHandover.update({where:{id:h.id},data:{failedAttempts:attempts,lastFailedAt:now,...(locked?{lockedAt:now,lockedUntil:lockUntil,nextIssueAt:lockUntil}:{})}});
        await this.audit(tx,changed,p,locked?'LOCKED':'INCORRECT_PIN');
        // Return an outcome, not a thrown exception: failed guesses must commit.
        return {error:locked?429:400,message:locked?'Handover locked after five incorrect attempts':'Handover PIN is incorrect'} as const;
      }
      const version=o.version+1;
      await tx.deliveryHandover.update({where:{id:h.id},data:{verifiedAt:now,consumedAt:now,encryptedPin:null,completionExpectedVersion:expectedVersion,completedOrderVersion:version}});
      await tx.order.update({where:{id},data:{status:'DELIVERED',version}});
      await tx.deliveryAssignment.update({where:{orderId:id},data:{status:'DELIVERED',deliveredAt:now}});
      await this.audit(tx,h,p,'CONSUMED');
      const event=await tx.orderEvent.create({data:{orderId:id,actorUserId:p.userId,eventType:'ORDER_DELIVERED',previousStatus:'OUT_FOR_DELIVERY',newStatus:'DELIVERED',sequence:version,metadata:{handoverVerified:true,challengeVersion:h.challengeVersion}}});
      await queueEvent(tx,event.id);
      return {value:{...this.operations.present(await tx.order.findUniqueOrThrow({where:{id},include:operationInclude}),'DELIVERY_PARTNER'),handoverVerified:true,alreadyCompleted:false}};
    });
    if('error' in result)throw new HttpException(result.message!,result.error!);
    return result.value;
  }
}
