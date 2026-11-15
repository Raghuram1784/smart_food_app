import 'dotenv/config';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import request from 'supertest';
test('scheduled delivery: real checkout, capacity, recovery, invitations and OTP',{timeout:180000},async t=>{
 const url=process.env.TEST_DATABASE_URL!;assert.equal(new URL(url).pathname,'/food_delivery_test');
 Object.assign(process.env,{DATABASE_URL:url,NODE_ENV:'test',DEMO_CHECKOUT_ENABLED:'true',DEMO_FULFILLMENT_ENABLED:'true',HANDOVER_HMAC_KEY:randomBytes(32).toString('hex'),HANDOVER_ENCRYPTION_KEY:randomBytes(32).toString('hex')});
 execFileSync(process.execPath,['node_modules/prisma/build/index.js','migrate','deploy'],{env:{...process.env,DIRECT_URL:url},stdio:'pipe'});
 const {createDatabase}=require('../dist/src/database/client'),{createApp}=require('../dist/src/main');
 const {SchedulingService}=require('../dist/src/modules/scheduling/scheduling.module');
 const {PasswordService}=require('../dist/src/modules/auth/password.service');
 const db=createDatabase(url),rid='deccan-handi-gachi',password=randomUUID(),users:any[]=[],tokens:string[]=[],addresses:any[]=[];
 let app=await createApp(),api:any,worker:any,slot:any,placed:any;
 const policy=await db.restaurant.findUniqueOrThrow({where:{id:rid}});
 const call=(method:string,path:string,i=0)=>(api as any)[method]('/api/v1/'+path).set('Authorization','Bearer '+tokens[i]);
 const stop=async()=>{worker=app.get(SchedulingService);clearInterval(worker.timer);while(worker.running)await new Promise(r=>setTimeout(r,10));};
 const prepare=async(i=0)=>{
  let c=(await call('get','cart',i).expect(200)).body.data;
  const dish=await db.menuItem.findFirstOrThrow({where:{restaurantId:rid,availabilityStatus:'AVAILABLE',variants:{none:{}}}});
  c=(await call('post','cart/items',i).send({restaurantId:rid,menuItemId:dish.id,quantity:1,addOnIds:[],expectedVersion:c.version}).expect(200)).body.data;
  const q=(await call('post','cart/quote',i).send({addressId:addresses[i].id,expectedVersion:c.version}).expect(200)).body.data;
  return {cartId:c.id,addressId:addresses[i].id,quoteId:q.quoteId,paymentMethod:'DEMO_NO_PAYMENT',idempotencyKey:randomUUID(),deliveryMode:'SCHEDULED',scheduledDeliveryAt:slot.scheduledDeliveryAt};
 };
 const change=(o:any,a:string,i=2)=>call('post',`operations/${i===2?'restaurant':'delivery'}/orders/${o.id}/${a}`,i).send({expectedVersion:o.version});
 const retime=async(o:any,target:Date)=>{
  const at=target.getTime();await db.order.update({where:{id:o.id},data:{scheduledDeliveryAt:target,deliveryWindowStart:new Date(at-300000),deliveryWindowEnd:new Date(at+300000),preparationStartAt:new Date(at-2400000),expectedPickupAt:new Date(at-600000),dispatchReleaseAt:new Date(at-900000)}});
 };
 try{
  await db.restaurant.update({where:{id:rid},data:{scheduleCapacity:1}});
  const hash=await new PasswordService().hash(password);
  for(const [i,role] of ['CUSTOMER','CUSTOMER','RESTAURANT_OWNER','DELIVERY_PARTNER','DELIVERY_PARTNER','RESTAURANT_OWNER'].entries())users.push(await db.user.create({data:{email:`f3-${randomUUID()}@test.invalid`,displayName:'Synthetic schedule',passwordHash:hash,roles:{create:{roleName:role}},...(role==='RESTAURANT_OWNER'?{memberships:{create:{restaurantId:i===2?rid:'tiffin'}}}:{})}}));
  for(let i=0;i<2;i++)addresses.push(await db.customerAddress.create({data:{customerId:users[i].id,label:'Home',recipientName:'Synthetic',contactNumber:'9000000000',addressLine1:'1 Synthetic Lane',postalCode:'500032',city:'Hyderabad',localityId:'madhapur'}}));
  await app.init();await stop();api=request(app.getHttpServer());
  for(const user of users)tokens.push((await api.post('/api/v1/auth/login').send({email:user.email,password}).expect(200)).body.data.session.token);
  const dates=(await call('get',`restaurants/${rid}/delivery-slots`).expect(200)).body.data.dates;
  slot=(await call('get',`restaurants/${rid}/delivery-slots?date=${dates[1]}`).expect(200)).body.data.slots[0];assert.ok(slot);
  await t.test('invalid slots, shape, date range and ownership; immediate mode stays available',async()=>{
   const input=await prepare();
   for(const bad of [{scheduledDeliveryAt:new Date(0).toISOString()},{scheduledDeliveryAt:'bad'},{deliveryMode:'NOW'},{deliveryMode:'SCHEDULED',scheduledDeliveryAt:undefined},{scheduledDeliveryAt:slot.scheduledDeliveryAt.replace(':00.000',':01.000')}])await call('post','orders').send({...input,...bad}).expect(r=>assert.ok([400,409].includes(r.status)));
   await call('get',`restaurants/${rid}/delivery-slots?date=2000-01-01`).expect(409);await call('get',`restaurants/${rid}/delivery-slots`,3).expect(403);
   const {scheduledDeliveryAt,deliveryMode,...immediate}=input;
   const now=(await call('post','orders').send(immediate).expect(200)).body.data;assert.equal(now.deliveryMode,'NOW');assert.equal(now.scheduledDeliveryAt,null);
  });
  await t.test('concurrent booking cannot overbook; identical retry returns one order; cancellation releases capacity',async()=>{
   const inputs=[await prepare(0),await prepare(1)];
   const result=await Promise.all(inputs.map((b,i)=>call('post','orders',i).send(b)));
   assert.deepEqual(result.map(r=>r.status).sort(),[200,409]);const win=result.findIndex(r=>r.status===200),lose=1-win;placed=result[win].body.data;
   assert.equal((await call('post','orders',win).send(inputs[win]).expect(200)).body.data.id,placed.id);
   await call('post','orders',win).send({...inputs[win],scheduledDeliveryAt:new Date(Date.parse(slot.scheduledDeliveryAt)+900000).toISOString()}).expect(409);
   await call('post',`orders/${placed.id}/cancel-scheduled`,lose).send({expectedVersion:placed.version}).expect(404);
   await call('post',`orders/${placed.id}/cancel-scheduled`,win).send({expectedVersion:placed.version}).expect(200);
   await call('post',`orders/${placed.id}/cancel-scheduled`,win).send({expectedVersion:placed.version}).expect(200);
   const other=(await call('post','orders',lose).send(inputs[lose]).expect(200)).body.data;
   await call('post',`orders/${other.id}/cancel-scheduled`,lose).send({expectedVersion:other.version}).expect(200);
  });
  await t.test('owner scope and early preparation/dispatch are enforced; rider previews omit identities',async()=>{
   placed=(await call('post','orders').send(await prepare()).expect(200)).body.data;
   await call('post',`operations/restaurant/orders/${placed.id}/accept`,5).send({expectedVersion:placed.version}).expect(403);
   placed=(await change(placed,'accept').expect(200)).body.data;
   await change(placed,'start-preparing').expect(409);assert.ok(!placed.availableActions.includes('start-preparing'));
   for(const i of [3,4])await call('post','rider/presence/online',i).send({}).expect(200);
   const upcoming=(await call('get','operations/delivery/upcoming-scheduled',3).expect(200)).body.data;
   assert.ok(upcoming.items.length>0);for(const secret of ['customerId','orderNumber','deliveryAddressSnapshot','contactNumber','pin'])assert.ok(!JSON.stringify(upcoming).includes(secret));
   await call('get','operations/delivery/upcoming-scheduled',0).expect(403);
   await db.order.update({where:{id:placed.id},data:{preparationStartAt:new Date(Date.now()-60000)}});
   placed=(await change(placed,'start-preparing').expect(200)).body.data;placed=(await change(placed,'ready').expect(200)).body.data;
   assert.equal(await db.deliveryOffer.count({where:{orderId:placed.id}}),0);
   assert.ok(!(await call('get','operations/delivery/offers',3).expect(200)).body.data.offers.some((x:any)=>x.orderId===placed.id));
  });
  await t.test('restart recovery releases due invitations once and persists deadline notices',async()=>{
   await retime(placed,new Date(Date.now()+60000));
   await app.close();app=await createApp();await app.init();await stop();api=request(app.getHttpServer());
   await Promise.all([worker.tick(),worker.tick()]);
   const events=await db.orderEvent.findMany({where:{orderId:placed.id}});
   assert.equal(events.filter((x:any)=>x.eventType==='SCHEDULE_PREPARATION_DUE').length,1);
   assert.equal(events.filter((x:any)=>x.eventType==='SCHEDULE_DISPATCH_DUE').length,1);
   assert.equal(events.filter((x:any)=>x.eventType==='SCHEDULE_AT_RISK').length,1);
   assert.equal(await db.deliveryOffer.count({where:{orderId:placed.id,riderId:{in:[users[3].id,users[4].id]}}}),2);
   assert.equal(await db.outboxEvent.count({where:{event:{orderId:placed.id,eventType:'SCHEDULE_AT_RISK'}}}),1);
  });
  await t.test('one rider accepts, real OTP handover records actual delivery inside target window',async()=>{
   const invitations=await Promise.all([3,4].map(async i=>(await call('get','operations/delivery/offers',i).expect(200)).body.data.offers.find((x:any)=>x.orderId===placed.id)));
   const outcomes=await Promise.all(invitations.map((inv,i)=>call('post',`operations/delivery/offers/${inv.id}/accept`,i+3).send({})));
   assert.deepEqual(outcomes.map(x=>x.status).sort(),[200,409]);const rider=3+outcomes.findIndex(x=>x.status===200);
   let o=(await call('get',`operations/delivery/orders/${placed.id}`,rider).expect(200)).body.data;
   o=(await change(o,'pickup',rider).expect(200)).body.data;o=(await change(o,'out-for-delivery',rider).expect(200)).body.data;
   const pin=(await call('get',`orders/${o.id}/handover`).expect(200)).body.data.pin;
   const payload={pin,expectedVersion:o.version};
   o=(await call('post',`operations/delivery/orders/${o.id}/complete-handover`,rider).send(payload).expect(200)).body.data;
   assert.equal(o.scheduleIndicator,'DELIVERED_WITHIN_WINDOW');assert.ok(o.actualDeliveryAt);assert.equal(o.paymentStatus,'UNPAID');
   const retry=(await call('post',`operations/delivery/orders/${o.id}/complete-handover`,rider).send(payload).expect(200)).body.data;assert.equal(retry.actualDeliveryAt,o.actualDeliveryAt);
  });
  await t.test('late delivery and delayed outbox notification; terminal cancellation stays terminal',async()=>{
   const input=await prepare();const o=(await call('post','orders').send(input).expect(200)).body.data;
   await retime(o,new Date(Date.now()-600000));await worker.tick();await worker.tick();
   assert.equal(await db.orderEvent.count({where:{orderId:o.id,eventType:'SCHEDULE_DELAYED'}}),1);
   assert.equal((await call('get',`orders/${o.id}`).expect(200)).body.data.scheduleIndicator,'DELAYED');
   await call('post',`orders/${o.id}/cancel-scheduled`).send({expectedVersion:o.version}).expect(409);
   let live=await db.order.findUniqueOrThrow({where:{id:o.id}});live=(await change(live,'accept').expect(200)).body.data;live=(await change(live,'start-preparing').expect(200)).body.data;live=(await change(live,'ready').expect(200)).body.data;
   const invitation=(await call('get','operations/delivery/offers',3).expect(200)).body.data.offers.find((x:any)=>x.orderId===o.id);
   await call('post',`operations/delivery/offers/${invitation.id}/accept`,3).send({}).expect(200);
   live=(await call('get',`operations/delivery/orders/${o.id}`,3).expect(200)).body.data;live=(await change(live,'pickup',3).expect(200)).body.data;live=(await change(live,'out-for-delivery',3).expect(200)).body.data;
   const pin=(await call('get',`orders/${o.id}/handover`).expect(200)).body.data.pin;
   live=(await call('post',`operations/delivery/orders/${o.id}/complete-handover`,3).send({pin,expectedVersion:live.version}).expect(200)).body.data;
   assert.equal(live.scheduleIndicator,'DELIVERED_OUTSIDE_WINDOW');
  });
  await t.test('scheduler outbox failure rolls back, independent workers cannot duplicate due events',async()=>{
   const o=(await call('post','orders').send(await prepare()).expect(200)).body.data;await retime(o,new Date(Date.now()+60000));
   await db.$executeRawUnsafe(`CREATE FUNCTION f3_fail_outbox() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected F3 failure'; END $$`);
   await db.$executeRawUnsafe(`CREATE TRIGGER f3_fail_outbox BEFORE INSERT ON "OutboxEvent" FOR EACH ROW EXECUTE FUNCTION f3_fail_outbox()`);
   try{await worker.tick();assert.equal(await db.orderEvent.count({where:{orderId:o.id,eventType:'SCHEDULE_PREPARATION_DUE'}}),0);assert.equal((await db.order.findUniqueOrThrow({where:{id:o.id}})).version,1);}
   finally{await db.$executeRawUnsafe('DROP TRIGGER f3_fail_outbox ON "OutboxEvent"');await db.$executeRawUnsafe('DROP FUNCTION f3_fail_outbox()');}
   const {DatabaseService}=require('../dist/src/database/database.module'),{CommerceStore}=require('../dist/src/modules/commerce/commerce.store');
   const second=new SchedulingService(app.get(DatabaseService),app.get(CommerceStore));await Promise.all([worker.tick(),second.tick()]);
   assert.equal(await db.orderEvent.count({where:{orderId:o.id,eventType:'SCHEDULE_PREPARATION_DUE'}}),1);
  });
  await t.test('capture arriving after scheduled cancellation stays canceled and requires refund review',async()=>{
   const input=await prepare();const o=(await call('post','orders').send({...input,paymentMethod:'RAZORPAY_TEST'}).expect(200)).body.data;
   const a=await db.paymentAttempt.create({data:{orderId:o.id,customerId:users[0].id,amountPaise:o.finalPayablePaise,keyId:'rzp_test_f3_isolated',receipt:'f3_'+randomUUID().replaceAll('-',''),providerOrderId:'order_f3isolated',status:'READY'}});
   await call('post',`orders/${o.id}/cancel-scheduled`).send({expectedVersion:o.version}).expect(200);
   const {PaymentsService}=require('../dist/src/modules/payments/payments.service');
   await app.get(PaymentsService).apply(a,{id:'pay_f3'+randomUUID().replaceAll('-',''),order_id:a.providerOrderId,amount:a.amountPaise,currency:a.currency,status:'captured',captured:true});
   const stored=await db.order.findUniqueOrThrow({where:{id:o.id}});assert.equal(stored.status,'CANCELED');assert.equal(stored.paymentStatus,'PAID');assert.equal(stored.refundReviewRequired,true);assert.equal(stored.finalPayablePaise,o.finalPayablePaise);
  });
 }finally{
  await app.close();const ids=users.map(x=>x.id),where={customerId:{in:ids}},orders=await db.order.findMany({where,select:{id:true}}),orderIds=orders.map((x:any)=>x.id);
  await db.deliveryHandover.deleteMany({where:{orderId:{in:orderIds}}});await db.deliveryOffer.deleteMany({where:{orderId:{in:orderIds}}});await db.deliveryAssignment.deleteMany({where:{orderId:{in:orderIds}}});
  await db.paymentAttempt.deleteMany({where:{orderId:{in:orderIds}}});await db.orderEvent.deleteMany({where:{orderId:{in:orderIds}}});await db.orderItemAddOn.deleteMany({where:{orderItem:{orderId:{in:orderIds}}}});await db.orderItem.deleteMany({where:{orderId:{in:orderIds}}});await db.order.deleteMany({where});
  await db.cartItem.deleteMany({where:{cart:{customerId:{in:ids}}}});await db.cart.deleteMany({where});await db.customerAddress.deleteMany({where});await db.deliveryOffer.deleteMany({where:{riderId:{in:ids}}});await db.riderPresence.deleteMany({where:{userId:{in:ids}}});await db.authSession.deleteMany({where:{userId:{in:ids}}});await db.restaurantMembership.deleteMany({where:{userId:{in:ids}}});await db.userRole.deleteMany({where:{userId:{in:ids}}});await db.user.deleteMany({where:{id:{in:ids}}});
  await db.restaurant.update({where:{id:rid},data:{scheduleCapacity:policy.scheduleCapacity}});await db.$disconnect();
 }
});
