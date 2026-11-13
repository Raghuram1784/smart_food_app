import 'dotenv/config';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import request from 'supertest';
import {paymentChecks} from './payment-checks';
import {operationsChecks} from './operations-checks';

test('real cart, exact order pricing and atomic idempotent checkout',{timeout:120000},async t=>{
  const url=process.env.TEST_DATABASE_URL!;assert.equal(new URL(url).pathname,'/food_delivery_test');
  process.env.HANDOVER_HMAC_KEY=randomBytes(32).toString('hex');process.env.HANDOVER_ENCRYPTION_KEY=randomBytes(32).toString('hex');
  process.env.DATABASE_URL=url;process.env.NODE_ENV='test';process.env.DEMO_CHECKOUT_ENABLED='true';
  execFileSync(process.execPath,['node_modules/prisma/build/index.js','migrate','deploy'],{env:{...process.env,DIRECT_URL:url},stdio:'pipe'});
  const {createDatabase}=require('../dist/src/database/client'),{createApp}=require('../dist/src/main');
  const {PasswordService}=require('../dist/src/modules/auth/password.service');
  const db=createDatabase(url),app=await createApp(),password=randomUUID();
  const users:any[]=[],tokens:string[]=[],ids=['p5-test-a','p5-test-b','p5-test-other'];
  let variant:any,addon:any,address:any,cart:any,order:any;
  const rid='deccan-handi-gachi';
  const other=await db.restaurant.findFirstOrThrow({where:{id:{not:rid},operatingStatus:'OPEN',zones:{some:{zoneId:'madhapur',isEligible:true}}}});
  try{
    const hash=await new PasswordService().hash(password);
    for(const role of ['CUSTOMER','CUSTOMER','RESTAURANT_OWNER','ADMIN']){
      users.push(await db.user.create({data:{email:`p5-${randomUUID()}@test.invalid`,displayName:'Synthetic Test',passwordHash:hash,roles:{create:{roleName:role}},...(role==='RESTAURANT_OWNER'?{memberships:{create:{restaurantId:rid}}}:{})}}));
    }
    for(let i=0;i<3;i++){
      const restaurantId=i===2?other.id:rid;
      const section=await db.menuSection.findFirstOrThrow({where:{restaurantId}});
      await db.menuItem.create({data:{id:ids[i],restaurantId,sectionId:section.id,categoryId:'dosa',name:`Synthetic meal ${i}`,description:'Isolated Phase 5 fixture',imageKey:'dosa',basePricePaise:i===1?15000:12000,isVegetarian:true}});
    }
    variant=await db.menuItemVariant.create({data:{menuItemId:ids[0],name:'Large',priceAdjustmentPaise:2000}});
    addon=await db.addOn.create({data:{name:'Synthetic side',pricePaise:500}});
    await db.menuItemAddOn.create({data:{menuItemId:ids[0],addOnId:addon.id}});
    await app.init();const api=request(app.getHttpServer());
    for(const user of users){tokens.push((await api.post('/api/v1/auth/login').send({email:user.email,password}).expect(200)).body.data.session.token);}
    const call=(method:string,path:string,index=0)=>api[method as 'get'](`/api/v1/${path}`).set('Authorization',`Bearer ${tokens[index]}`);
    const getCart=async()=>cart=(await call('get','cart').expect(200)).body.data;
    const add=async(menuItemId=ids[0],extra:object={})=>{const result=await call('post','cart/items').send({restaurantId:rid,menuItemId,area:'madhapur',quantity:1,addOnIds:[],expectedVersion:cart.version,...extra});if(result.status===200)cart=result.body.data;return result;};
    const quote=async()=> (await call('post','cart/quote').send({addressId:address.id,expectedVersion:cart.version}).expect(200)).body.data;
    const payload=(q:any)=>({cartId:cart.id,addressId:address.id,quoteId:q.quoteId,idempotencyKey:randomUUID(),paymentMethod:'DEMO_NO_PAYMENT'});
    await t.test('customer RBAC, address validation and ownership',async()=>{
      await api.get('/api/v1/cart').expect(401);await call('get','cart',2).expect(403);await call('get','orders',3).expect(403);
      const input={label:'Synthetic home',recipientName:'Test Customer',contactNumber:'9999999999',addressLine1:'100 Synthetic Test Lane',localityId:'madhapur',postalCode:'500081',isDefault:true};
      await call('post','addresses').send({...input,localityId:'missing'}).expect(422);
      address=(await call('post','addresses').send(input).expect(201)).body.data;
      const duplicates=await Promise.all([call('post','addresses').send(input),call('post','addresses').send(input)]);
      assert.ok(duplicates.every(r=>r.status===201 && r.body.data.id===address.id));
      assert.equal(await db.customerAddress.count({where:{customerId:users[0].id}}),1);
      await call('patch',`addresses/${address.id}`,1).send(input).expect(404);
      await call('delete',`addresses/${address.id}`,1).expect(404);
      assert.equal((await call('get','addresses',1).expect(200)).body.data.length,0);
      await getCart();
    });
    await t.test('validated options, quantity and single restaurant policy',async()=>{
      for(const extra of [{quantity:0},{quantity:21},{basePricePaise:1},{customerId:users[1].id}])assert.equal((await add(ids[0],extra)).status,400);
      assert.equal((await add('missing')).status,404);
      assert.equal((await add(ids[1],{variantId:variant.id})).status,422);
      assert.equal((await add(ids[1],{addOnIds:[addon.id]})).status,422);
      await db.menuItem.update({where:{id:ids[0]},data:{availabilityStatus:'SOLD_OUT'}});assert.equal((await add()).status,422);
      await db.menuItem.update({where:{id:ids[0]},data:{availabilityStatus:'AVAILABLE'}});
      assert.equal((await add(ids[0],{variantId:variant.id,addOnIds:[addon.id]})).status,200);
      assert.equal((await add(ids[0],{variantId:variant.id,addOnIds:[addon.id]})).status,200);assert.equal(cart.items.length,1);assert.equal(cart.items[0].quantity,2);
      assert.equal(cart.items[0].unitPricePaise,14500);assert.equal(cart.items[0].lineTotalPaise,29000);assert.equal(cart.merchandiseSubtotalPaise,29000);
      assert.equal((await add(ids[2],{restaurantId:other.id})).status,409);
      assert.equal((await call('get','cart',1).expect(200)).body.data.items.length,0);
      await call('patch',`cart/items/${cart.items[0].id}`,1).send({expectedVersion:1,quantity:2}).expect(404);
      const v=cart.version;
      const simultaneous=await Promise.all([1,3].map(quantity=>call('patch',`cart/items/${cart.items[0].id}`).send({expectedVersion:v,quantity})));
      assert.deepEqual(simultaneous.map(r=>r.status).sort(),[200,409]);await getCart();
      cart=(await call('patch',`cart/items/${cart.items[0].id}`).send({expectedVersion:cart.version,quantity:2}).expect(200)).body.data;
      assert.equal((await add(ids[1])).status,200);
    });
    await t.test('aggregated merchandise with fees once, exact taxes and discounts',async()=>{
      let q=await quote();assert.equal(q.basePaise,39000);assert.equal(q.variantPaise,4000);assert.equal(q.addOnPaise,1000);assert.equal(q.finalPayablePaise,47500);
      assert.equal(q.deliveryPaise,2000);assert.equal(q.packagingPaise,1000);assert.equal(q.platformPaise,500);
      await db.pricingRule.create({data:{code:'P5_TEST_TAX',restaurantId:rid,component:'TAX',rateBasisPoints:625,isActive:true,effectiveFrom:new Date('2020-01-01')}});
      await db.pricingRule.create({data:{code:'P5_TEST_DISCOUNT',restaurantId:rid,component:'DISCOUNT',fixedPaise:1000,isActive:true,effectiveFrom:new Date('2020-01-01')}});
      q=await quote();assert.equal(q.taxPaise,2688);assert.equal(q.discountPaise,1000);assert.equal(q.finalPayablePaise,49188);
      await db.pricingRule.deleteMany({where:{code:{in:['P5_TEST_TAX','P5_TEST_DISCOUNT']}}});
      const rules=await db.pricingRule.findMany({where:{component:'DELIVERY',isActive:true}});
      try{await db.pricingRule.updateMany({where:{id:{in:rules.map((r:any)=>r.id)}},data:{isActive:false}});await call('post','cart/quote').send({addressId:address.id,expectedVersion:cart.version}).expect(422);}
      finally{await db.pricingRule.updateMany({where:{id:{in:rules.map((r:any)=>r.id)}},data:{isActive:true}});}
    });
    await t.test('stale price, expired quote, changed address and unavailable restaurant fail without consuming cart',async()=>{
      const q=await quote(),input=payload(q);
      await db.menuItem.update({where:{id:ids[1]},data:{basePricePaise:15001}});await call('post','orders').send(input).expect(409);
      await db.menuItem.update({where:{id:ids[1]},data:{basePricePaise:15000}});
      await db.cartQuote.update({where:{id:q.quoteId},data:{expiresAt:new Date(0)}});await call('post','orders').send(input).expect(409);
      const changed=payload(await quote());await db.customerAddress.update({where:{id:address.id},data:{addressLine1:'101 Synthetic Test Lane'}});await call('post','orders').send(changed).expect(409);
      const unavailable=payload(await quote());
      await db.restaurant.update({where:{id:rid},data:{operatingStatus:'PAUSED'}});
      try{await call('post','orders').send(unavailable).expect(422);}finally{await db.restaurant.update({where:{id:rid},data:{operatingStatus:'OPEN'}});}
      assert.equal(await db.order.count({where:{customerId:users[0].id}}),0);await getCart();assert.equal(cart.items.length,2);
    });
    await t.test('failed event write rolls back order, snapshots and cart consumption',async()=>{
      await db.$executeRawUnsafe(`CREATE FUNCTION p5_fail_event() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected test failure'; END $$`);
      await db.$executeRawUnsafe(`CREATE TRIGGER p5_fail_event BEFORE INSERT ON "OrderEvent" FOR EACH ROW EXECUTE FUNCTION p5_fail_event()`);
      try{await call('post','orders').send(payload(await quote())).expect(503);assert.equal(await db.order.count({where:{customerId:users[0].id}}),0);assert.equal(await db.orderItem.count({where:{menuItemId:{in:ids}}}),0);await getCart();assert.equal(cart.items.length,2);}
      finally{await db.$executeRawUnsafe('DROP TRIGGER p5_fail_event ON "OrderEvent"');await db.$executeRawUnsafe('DROP FUNCTION p5_fail_event()');}
    });
    await t.test('simultaneous retry creates one durable unpaid pending order and committed event',async()=>{
      const input=payload(await quote());
      const responses=await Promise.all([call('post','orders').send(input),call('post','orders').send(input)]);
      assert.deepEqual(responses.map(r=>r.status),[200,200]);order=responses[0].body.data;assert.equal(responses[1].body.data.id,order.id);
      assert.equal(order.status,'PENDING_RESTAURANT');assert.equal(order.paymentStatus,'UNPAID');assert.equal(order.paymentMethod,'DEMO_NO_PAYMENT');assert.equal(order.finalPayablePaise,47500);
      assert.equal(order.items.length,2);assert.equal(order.items[0].addOns.length+order.items[1].addOns.length,1);assert.equal(order.events.length,1);
      assert.equal(await db.order.count({where:{customerId:users[0].id}}),1);
      await call('post','orders').send({...input,addressId:randomUUID()}).expect(409);
      await call('post','orders').send({...input,idempotencyKey:randomUUID()}).expect(409);
      await getCart();assert.equal(cart.items.length,0);
      await db.customerAddress.update({where:{id:address.id},data:{addressLine1:'999 Changed Address'}});
      await db.menuItem.update({where:{id:ids[0]},data:{name:'Changed menu name',basePricePaise:1}});
      const stored=(await call('get',`orders/${order.id}`).expect(200)).body.data;
      assert.equal(stored.finalPayablePaise,47500);assert.equal(stored.deliveryAddressSnapshot.addressLine1,'101 Synthetic Test Lane');assert.ok(stored.items.some((i:any)=>i.name==='Synthetic meal 0'));
      assert.equal((await call('get','orders?page=1&limit=1').expect(200)).body.data.total,1);
      await call('get',`orders/${order.id}`,1).expect(404);await call('patch',`orders/${order.id}`).send({status:'DELIVERED'}).expect(404);
      const inbox=(await call('get',`restaurants/${rid}/orders`,2).expect(200)).body.data;
      assert.ok(inbox.items.some((o:any)=>o.id===order.id));assert.equal(inbox.items[0].deliveryAddressSnapshot,undefined);assert.ok(inbox.pendingCount>=1);
      await call('get',`restaurants/${other.id}/orders`,2).expect(403);await call('get',`restaurants/${rid}/orders`).expect(403);
    });
    await t.test('Razorpay payment safety and reconciliation',async pt=>{
      process.env.RAZORPAY_KEY_ID='rzp_test_isolated';process.env.RAZORPAY_KEY_SECRET='isolated-secret';
      await getCart();assert.equal((await add(ids[1])).status,200);
      const online=(await call('post','orders').send({...payload(await quote()),paymentMethod:'RAZORPAY_TEST'}).expect(200)).body.data;
      assert.equal(online.status,'AWAITING_PAYMENT');
      await paymentChecks(t,app,db,call,api,online,order);
      await operationsChecks(pt,app,db,call,api,online,users,tokens);
      await getCart();
    });
    await t.test('explicit switching, remove/clear, address delete and disabled demo checkout',async()=>{
      assert.equal((await add(ids[1])).status,200);assert.equal((await add(ids[2],{restaurantId:other.id,replaceRestaurant:true})).status,200);assert.equal(cart.items.length,1);assert.equal(cart.restaurantId,other.id);
      cart=(await call('delete',`cart/items/${cart.items[0].id}`).send({expectedVersion:cart.version}).expect(200)).body.data;assert.equal(cart.items.length,0);
      assert.equal((await add(ids[1])).status,200);cart=(await call('delete','cart').send({expectedVersion:cart.version}).expect(200)).body.data;assert.equal(cart.restaurantId,null);
      await call('delete',`addresses/${address.id}`).expect(200);
      process.env.DEMO_CHECKOUT_ENABLED='false';await call('post','orders').send({cartId:cart.id,addressId:address.id,quoteId:randomUUID(),idempotencyKey:randomUUID(),paymentMethod:'DEMO_NO_PAYMENT'}).expect(403);
    });
  }finally{
    process.env.DEMO_CHECKOUT_ENABLED='true';const userIds=users.map(u=>u.id);
    const orders=await db.order.findMany({where:{customerId:{in:userIds}},select:{id:true}}),orderIds=orders.map((o:any)=>o.id);
    await db.paymentWebhookEvent.deleteMany({where:{providerEventId:{startsWith:'p6test_'}}});
    await db.deliveryHandover.deleteMany({where:{orderId:{in:orderIds}}});
    await db.deliveryAssignment.deleteMany({where:{orderId:{in:orderIds}}});
    await db.paymentAttempt.deleteMany({where:{orderId:{in:orderIds}}});
    await db.orderEvent.deleteMany({where:{orderId:{in:orderIds}}});await db.orderItemAddOn.deleteMany({where:{orderItem:{orderId:{in:orderIds}}}});await db.orderItem.deleteMany({where:{orderId:{in:orderIds}}});await db.order.deleteMany({where:{id:{in:orderIds}}});
    await db.cart.deleteMany({where:{customerId:{in:userIds}}});await db.customerAddress.deleteMany({where:{customerId:{in:userIds}}});
    await db.authSession.deleteMany({where:{userId:{in:userIds}}});await db.restaurantMembership.deleteMany({where:{userId:{in:userIds}}});await db.userRole.deleteMany({where:{userId:{in:userIds}}});await db.user.deleteMany({where:{id:{in:userIds}}});
    await db.pricingRule.deleteMany({where:{code:{in:['P5_TEST_TAX','P5_TEST_DISCOUNT']}}});
    await db.menuItemAddOn.deleteMany({where:{menuItemId:{in:ids}}});await db.menuItemVariant.deleteMany({where:{menuItemId:{in:ids}}});await db.menuItem.deleteMany({where:{id:{in:ids}}});if(addon)await db.addOn.delete({where:{id:addon.id}});
    await app.close();await db.$disconnect();
  }
});
