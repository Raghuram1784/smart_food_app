import {Inject,Injectable,OnModuleDestroy,OnModuleInit} from '@nestjs/common';
import {ConnectedSocket,MessageBody,SubscribeMessage,WebSocketGateway,WebSocketServer} from '@nestjs/websockets';
import {Server,Socket} from 'socket.io';
import {SessionVerifier} from '../auth/auth.types';
import {DatabaseService} from '../../database/database.module';
import {settings} from '../../config/settings';

@WebSocketGateway({cors:{origin:settings().origins},maxHttpBufferSize:8192})
export class OrderGateway implements OnModuleDestroy {
  @WebSocketServer() server!:Server;
  private timer?:NodeJS.Timeout;
  constructor(@Inject(SessionVerifier) readonly sessions:SessionVerifier,@Inject(DatabaseService) readonly database:DatabaseService){}
  afterInit(server:Server){
    server.use(async(socket,next)=>{try{
      if(socket.handshake.query.token)throw Error();
      const token=socket.handshake.auth?.token;if(typeof token!=='string')throw Error();
      socket.data.token=token;await this.authorize(socket);next();
    }catch{next(new Error('Session invalid or unauthorized'));}});
    this.timer=setInterval(()=>{void this.revalidate();},15000);this.timer.unref();
  }
  async authorize(socket:Socket){
    const p=await this.sessions.authenticate(socket.data.token);
    if(!p.roles.some(r=>['CUSTOMER','RESTAURANT_OWNER','DELIVERY_PARTNER','ADMIN'].includes(r)))throw Error('No operational role');
    socket.data.principal=p;return p;
  }
  async handleConnection(socket:Socket){try{await this.rooms(socket);}catch{socket.disconnect(true);}}
  async rooms(socket:Socket){
    const p=await this.authorize(socket);
    for(const room of socket.rooms)if(room!==socket.id)await socket.leave(room);
    if(p.roles.includes('CUSTOMER'))await socket.join('customer:'+p.userId);
    if(p.roles.includes('DELIVERY_PARTNER'))await socket.join('delivery:'+p.userId);
    if(p.roles.includes('ADMIN'))await socket.join('dispatch');
    if(p.roles.includes('RESTAURANT_OWNER')){
      const memberships=await this.database.client.restaurantMembership.findMany({where:{userId:p.userId,status:'ACTIVE',membershipRole:'OWNER'}});
      for(const m of memberships)await socket.join('restaurant:'+m.restaurantId);
    }
  }
  /** Content-free nudge to authenticated rooms (customer:<id>, restaurant:<id>); clients refetch over REST. */
  notify(rooms:string[],event:'group.updated'|'group.proposals',payload:{groupId:string;event:string}){
    if(!this.server||!rooms.length)return;
    this.server.to(rooms).emit(event,payload);
  }
  async revalidate(){if(!this.server)return;for(const socket of this.server.sockets.sockets.values()){try{await this.rooms(socket);}catch{socket.disconnect(true);}}}
  @SubscribeMessage('order.subscribe') async subscribe(@ConnectedSocket() socket:Socket,@MessageBody() body:unknown){
    try{
      const p=await this.authorize(socket),id=(body as any)?.orderId;
      if(typeof id!=='string'||!/^[0-9a-f-]{36}$/i.test(id))return {ok:false};
      const o=await this.database.client.order.findUnique({where:{id},include:{assignment:true}});if(!o)return {ok:false};
      const allowed=p.roles.includes('CUSTOMER')&&o.customerId===p.userId||p.roles.includes('DELIVERY_PARTNER')&&o.assignment?.riderId===p.userId||p.roles.includes('RESTAURANT_OWNER')&&!!await this.database.client.restaurantMembership.findFirst({where:{userId:p.userId,restaurantId:o.restaurantId,status:'ACTIVE',membershipRole:'OWNER'}});
      // No arbitrary room names, and admin has dispatch scope only.
      return {ok:!!allowed,version:allowed?o.version:undefined};
    }catch{socket.disconnect(true);return {ok:false};}
  }
  async publish(event:any){
    if(!this.server)throw Error('Gateway not ready');
    const o=await this.database.client.order.findUniqueOrThrow({where:{id:event.orderId},include:{assignment:true}});
    const payload={eventId:event.id,orderId:o.id,status:event.newStatus,previousStatus:event.previousStatus,version:event.sequence??o.version,updatedAt:event.createdAt.toISOString(),eventType:event.eventType};
    // Revalidate before every private emission, including revoked roles/memberships.
    for(const socket of this.server.sockets.sockets.values()){
      try{await this.rooms(socket);}catch{socket.disconnect(true);continue;}
      const rooms=socket.rooms;
      const permitted=rooms.has('customer:'+o.customerId)||rooms.has('restaurant:'+o.restaurantId)||(o.assignment&&rooms.has('delivery:'+o.assignment.riderId))||(rooms.has('dispatch')&&['READY_FOR_PICKUP','PICKED_UP','OUT_FOR_DELIVERY','DELIVERED'].includes(o.status));
      if(permitted)socket.emit('order.updated',payload);
    }
    // Rider invitations: nudge riders who hold (or just lost) an invitation for this order.
    // The payload carries no order details; the app re-reads its offers over the API.
    if(event.eventType==='ORDER_READY'||event.eventType==='RIDER_ASSIGNED'){
      const offers=await this.database.client.deliveryOffer.findMany({where:{orderId:o.id},select:{riderId:true}});
      const riders=new Set(offers.map(x=>'delivery:'+x.riderId));
      for(const socket of this.server.sockets.sockets.values()){
        if([...socket.rooms].some(r=>riders.has(r)))socket.emit('delivery.offers',{orderId:o.id,eventType:event.eventType});
      }
    }
  }
  onModuleDestroy(){if(this.timer)clearInterval(this.timer);}
}
@Injectable()
export class OutboxDispatcher implements OnModuleInit,OnModuleDestroy {
  timer?:NodeJS.Timeout;running=false;stopped=false;
  constructor(@Inject(DatabaseService) readonly database:DatabaseService,@Inject(OrderGateway) readonly gateway:OrderGateway){}
  onModuleInit(){this.timer=setInterval(()=>{void this.dispatch();},1000);this.timer.unref();}
  async dispatch(){
    if(this.running||this.stopped)return;this.running=true;
    try{
      const rows=await this.database.client.outboxEvent.findMany({where:{dispatchedAt:null,nextAttemptAt:{lte:new Date()}},include:{event:true},orderBy:[{createdAt:'asc'},{id:'asc'}],take:50});
      for(const row of rows){
        try{await this.gateway.publish(row.event);await this.database.client.outboxEvent.update({where:{id:row.id},data:{dispatchedAt:new Date(),attempts:{increment:1}}});}
        catch{await this.database.client.outboxEvent.update({where:{id:row.id},data:{attempts:{increment:1},nextAttemptAt:new Date(Date.now()+Math.min(60000,1000*2**Math.min(row.attempts,6)))}});}
      }
    }catch{/* Database outage: leave durable rows pending for next interval. */}finally{this.running=false;}
  }
  async onModuleDestroy(){this.stopped=true;if(this.timer)clearInterval(this.timer);while(this.running)await new Promise(r=>setTimeout(r,20));}
}
