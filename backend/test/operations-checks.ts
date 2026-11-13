import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {io,Socket} from 'socket.io-client';
export async function operationsChecks(t:any,app:any,db:any,call:any,api:any,paid:any,users:any[],tokens:string[]){
  const {OutboxDispatcher,OrderGateway}=require('../dist/src/modules/operations/realtime');
  const dispatcher=app.get(OutboxDispatcher),gateway=app.get(OrderGateway);
  clearInterval(dispatcher.timer);while(dispatcher.running)await new Promise(r=>setTimeout(r,10));
  await db.userRole.create({data:{userId:users[1].id,roleName:'DELIVERY_PARTNER'}});
  await app.listen(0,'127.0.0.1');const url=await app.getUrl();
  const sockets:Socket[]=[],received:any[][]=[[],[],[],[]];
  const connect=(token:string)=>new Promise<Socket>((resolve,reject)=>{const s=io(url.replace("[::1]","127.0.0.1"),{auth:{token},transports:['websocket'],forceNew:true,reconnection:false,timeout:3000});sockets.push(s);s.once('connect',()=>resolve(s));s.once('connect_error',reject);setTimeout(()=>reject(Error('Socket handshake timeout')),4000).unref();});
  let n=2000;
  const base=await db.order.findUnique({where:{id:paid.id}});
  const fixture=async(extra:any={})=>{
    const {id,createdAt,updatedAt,...data}=base;
    return db.order.create({data:{...data,orderNumber:'P7-'+randomUUID().slice(0,20),idempotencyKey:randomUUID(),cartVersion:++n,version:1,paymentMethod:'DEMO_NO_PAYMENT',paymentStatus:'UNPAID',status:'PENDING_RESTAURANT',...extra}});
  };
  const change=(o:any,action:string,index=2,extra:any={})=>call('post',`operations/${['pickup','out-for-delivery','deliver'].includes(action)?'delivery':'restaurant'}/orders/${o.id}/${action}`,index).send({expectedVersion:o.version,...extra});
  try{
    await t.test('actual Socket.IO handshake, private subscriptions and current session checks',async()=>{
      await assert.rejects(connect('invalid'));
      for(let i=0;i<4;i++){const s=await connect(tokens[i]);s.on('order.updated',e=>received[i].push(e));}
      const customer=sockets.find(s=>s.connected&&s.auth&&((s.auth as any).token===tokens[0]))!;
      assert.equal((await customer.timeout(2000).emitWithAck('order.subscribe',{orderId:paid.id})).ok,true);
      const other=sockets.find(s=>s.connected&&((s.auth as any).token===tokens[1]))!;
      assert.equal((await other.timeout(2000).emitWithAck('order.subscribe',{orderId:paid.id})).ok,false);
      await db.authSession.updateMany({where:{userId:users[1].id},data:{createdAt:new Date(Date.now()-7200000),expiresAt:new Date(Date.now()-1000)}});
      await call('get','operations/delivery/orders',1).expect(401);await gateway.revalidate();
      await new Promise(r=>setTimeout(r,40));assert.equal(other.connected,false);
      await db.authSession.updateMany({where:{userId:users[1].id},data:{expiresAt:new Date(Date.now()+3600000)}});
      const rider=await connect(tokens[1]);rider.on('order.updated',e=>received[1].push(e));
    });
    await t.test('kitchen RBAC, unpaid eligibility and development flag',async()=>{
      const o=await fixture();
      await api.post(`/api/v1/operations/restaurant/orders/${o.id}/accept`).send({expectedVersion:1}).expect(401);
      await change(o,'accept',0).expect(403);await change(o,'accept',1).expect(403);await change(o,'accept',3).expect(403);
      process.env.DEMO_FULFILLMENT_ENABLED='false';await change(o,'accept').expect(409);
      process.env.DEMO_FULFILLMENT_ENABLED='true';
      const online=await fixture({paymentMethod:'RAZORPAY_TEST',paymentStatus:'UNPAID'});await change(online,'accept').expect(409);
      const dishonest=await fixture({paymentMethod:'RAZORPAY_TEST',paymentStatus:'PAID'});await change(dishonest,'accept').expect(409);
      const foreign=await fixture({restaurantId:(await db.restaurant.findFirst({where:{id:{not:paid.restaurantId}}})).id});await change(foreign,'accept').expect(403);
      process.env.NODE_ENV='production';await change(o,'accept').expect(409);process.env.NODE_ENV='test';
    });
    await t.test('event and outbox failures roll back the status/version',async()=>{
      const o=await fixture();
      for(const table of ['OrderEvent','OutboxEvent']){
        await db.$executeRawUnsafe(`CREATE FUNCTION p7_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected'; END $$`);
        await db.$executeRawUnsafe(`CREATE TRIGGER p7_fail BEFORE INSERT ON "${table}" FOR EACH ROW EXECUTE FUNCTION p7_fail()`);
        try{await change(o,'accept').expect(503);assert.equal((await db.order.findUnique({where:{id:o.id}})).status,'PENDING_RESTAURANT');assert.equal(await db.orderEvent.count({where:{orderId:o.id}}),0);}
        finally{await db.$executeRawUnsafe(`DROP TRIGGER p7_fail ON "${table}"`);await db.$executeRawUnsafe('DROP FUNCTION p7_fail()');}
      }
    });
    await t.test('concurrent conflicting requests have one winner; terminal states stay terminal',async()=>{
      const o=await fixture();const results=await Promise.all([change(o,'accept'),change(o,'reject',2,{reason:'Kitchen cannot fulfill'})]);
      assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);assert.equal(await db.orderEvent.count({where:{orderId:o.id}}),1);
      const rejected=await fixture();await change(rejected,'reject',2,{reason:'Kitchen cannot fulfill'}).expect(200);
      await change({...rejected,version:2},'accept').expect(409);
      const paidRejected=await fixture({paymentMethod:'RAZORPAY_TEST',paymentStatus:'PAID'});
      const result=await change(paidRejected,'reject',2,{reason:'Unavailable ingredients'}).expect(200);
      assert.equal(result.body.data.refundReviewRequired,true);assert.equal(result.body.data.paymentStatus,'PAID');
    });
    await t.test('captured payment kitchen-to-rider lifecycle, privacy, outbox retry and reconnect',async()=>{
      let o=await db.order.findUnique({where:{id:paid.id}});
      o=(await change(o,'accept').expect(200)).body.data;
      await change({...o,version:o.version-1},'accept').expect(409);
      await change(o,'ready').expect(409);
      const original=gateway.publish.bind(gateway);gateway.publish=async()=>{throw Error('Injected publish failure');};await dispatcher.dispatch();
      assert.ok(await db.outboxEvent.count({where:{dispatchedAt:null,attempts:{gt:0}}}));gateway.publish=original;
      await db.outboxEvent.updateMany({where:{dispatchedAt:null},data:{nextAttemptAt:new Date(0)}});
      const before=received[1].length;await dispatcher.dispatch();await new Promise(r=>setTimeout(r,50));
      assert.ok(received[0].some(e=>e.orderId===o.id&&e.status==='ACCEPTED'));
      assert.ok(received[2].some(e=>e.orderId===o.id&&e.status==='ACCEPTED'));
      assert.equal(received[1].length,before);assert.ok(!JSON.stringify(received).includes('contactNumber'));
      o=(await change(o,'start-preparing').expect(200)).body.data;o=(await change(o,'ready').expect(200)).body.data;
      await call('post',`operations/dispatch/orders/${o.id}/assign`,0).send({expectedVersion:o.version,riderId:users[1].id}).expect(403);
      await change(o,'pickup',1).expect(403);
      o=(await call('post',`operations/dispatch/orders/${o.id}/assign`,3).send({expectedVersion:o.version,riderId:users[1].id}).expect(200)).body.data;
      await call('post',`operations/dispatch/orders/${o.id}/assign`,3).send({expectedVersion:o.version,riderId:users[1].id}).expect(409);
      const deliveries=await call('get','operations/delivery/orders',1).expect(200);assert.ok(deliveries.body.data.items.some((v:any)=>v.id===o.id));
      await dispatcher.dispatch();await new Promise(r=>setTimeout(r,50));assert.ok(received[1].some(e=>e.eventType==='RIDER_ASSIGNED'));
      const customer=sockets.find(s=>s.connected&&((s.auth as any).token===tokens[0]))!;customer.disconnect();
      o=(await change(o,'pickup',1).expect(200)).body.data;o=(await change(o,'out-for-delivery',1).expect(200)).body.data;o=(await change(o,'deliver',1).expect(200)).body.data;
      await connect(tokens[0]);assert.equal((await call('get',`orders/${o.id}`).expect(200)).body.data.status,'DELIVERED');
      await change(o,'pickup',1).expect(409);assert.equal(o.paymentStatus,'PAID');
      assert.equal((await db.deliveryAssignment.findUnique({where:{orderId:o.id}})).status,'DELIVERED');
      const events=await db.orderEvent.findMany({where:{orderId:o.id,sequence:{not:null}},orderBy:{sequence:'asc'}});assert.equal(new Set(events.map((e:any)=>e.sequence)).size,events.length);
      await db.authSession.updateMany({where:{userId:users[2].id},data:{revokedAt:new Date()}});await gateway.revalidate();await new Promise(r=>setTimeout(r,30));
      assert.ok(!sockets.some(s=>s.connected&&((s.auth as any).token===tokens[2])));
      await change(await fixture(),'accept').expect(401);
      await db.authSession.updateMany({where:{userId:users[2].id},data:{revokedAt:null}});
    });
  }finally{for(const s of sockets)s.disconnect();delete process.env.DEMO_FULFILLMENT_ENABLED;process.env.NODE_ENV='test';}
}
