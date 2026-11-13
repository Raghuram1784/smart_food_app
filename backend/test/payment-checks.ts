import assert from 'node:assert/strict';
import {createHmac,randomUUID} from 'node:crypto';

// Isolated provider double: only injected into the test app, never production.
export async function paymentChecks(t:any,app:any,db:any,call:any,api:any,order:any,demo:any){
  const {PaymentProvider}=require('../dist/src/modules/payments/razorpay.provider');
  const provider=app.get(PaymentProvider), orders:any[]=[], payments:any[]=[];
  let creates=0,ambiguous=true;
  Object.assign(provider,{
    create:async(amount:number,receipt:string)=>{creates++;const o={id:'order_'+randomUUID().replaceAll('-',''),amount,receipt,currency:'INR'};orders.push(o);if(ambiguous){ambiguous=false;throw Error('Lost response');}return o;},
    find:async(receipt:string)=>orders.filter(o=>o.receipt===receipt),
    payments:async(id:string)=>payments.filter(p=>p.order_id===id),
    payment:async(id:string)=>payments.find(p=>p.id===id),
  });
  const create=()=>call('post','payments/razorpay/create-order').send({orderId:order.id});
  await api.post('/api/v1/payments/razorpay/create-order').send({orderId:order.id}).expect(401);
  await call('post','payments/razorpay/create-order',2).send({orderId:order.id}).expect(403);
  await call('post','payments/razorpay/create-order',1).send({orderId:order.id}).expect(404);
  await call('post','payments/razorpay/create-order').send({orderId:demo.id}).expect(409);
  await call('post','payments/razorpay/create-order').send({orderId:order.id,amount:1}).expect(400);
  await create().expect(503);
  const results=await Promise.all([create(),create()]);
  assert.ok(results.every(r=>r.status===200));assert.equal(creates,1);
  const config=results[0].body.data;
  assert.equal(config.providerOrderId,results[1].body.data.providerOrderId);
  assert.equal(config.amount,order.finalPayablePaise);
  assert.ok(!JSON.stringify(config).includes('isolated-secret'));
  const p={id:'pay_'+randomUUID().replaceAll('-',''),order_id:config.providerOrderId,amount:config.amount,currency:'INR',status:'failed',captured:false};payments.push(p);
  const signature=createHmac('sha256','isolated-secret').update(`${p.order_id}|${p.id}`).digest('hex');
  const input={attemptId:config.attemptId,razorpay_order_id:p.order_id,razorpay_payment_id:p.id,razorpay_signature:signature};
  const verify=(extra={})=>call('post','payments/razorpay/verify').send({...input,...extra});
  await verify({razorpay_signature:'0'.repeat(64)}).expect(400);
  await call('post','payments/razorpay/verify',1).send(input).expect(404);
  await verify({razorpay_order_id:'order_other'}).expect(400);
  for(const [field,value] of [['amount',1],['currency','USD'],['order_id','order_other']] as const){const previous=(p as any)[field];(p as any)[field]=value;await verify().expect(400);(p as any)[field]=previous;}
  assert.equal((await verify().expect(200)).body.data.paymentStatus,'PAYMENT_FAILED');
  await create().expect(200);assert.equal(creates,1);
  p.status='authorized';assert.equal((await verify().expect(200)).body.data.paymentStatus,'PAYMENT_AUTHORIZED');
  await create().expect(409);
  p.status='captured';await verify().expect(400);p.captured=true;
  await db.$executeRawUnsafe(`CREATE FUNCTION p6_fail_event() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW."eventType"='PAYMENT_CAPTURED' THEN RAISE EXCEPTION 'Injected test failure'; END IF; RETURN NEW; END $$`);
  await db.$executeRawUnsafe(`CREATE TRIGGER p6_fail_event BEFORE INSERT ON "OrderEvent" FOR EACH ROW EXECUTE FUNCTION p6_fail_event()`);
  try{await verify().expect(503);assert.equal((await db.order.findUnique({where:{id:order.id}})).paymentStatus,'PAYMENT_AUTHORIZED');}
  finally{await db.$executeRawUnsafe('DROP TRIGGER p6_fail_event ON "OrderEvent"');await db.$executeRawUnsafe('DROP FUNCTION p6_fail_event()');}
  const paid=await Promise.all([verify(),verify()]);assert.ok(paid.every(r=>r.status===200&&r.body.data.paymentStatus==='PAID'));
  assert.equal(await db.orderEvent.count({where:{orderId:order.id,eventType:'PAYMENT_CAPTURED'}}),1);
  await create().expect(409);
  const raw=JSON.stringify({event:'payment.failed',payload:{payment:{entity:{id:p.id,order_id:p.order_id}}}});
  const eventId='p6test_'+randomUUID();
  const hook=(sig:string)=>api.post('/api/v1/payments/razorpay/webhook').set('Content-Type','application/json').set('x-razorpay-event-id',eventId).set('x-razorpay-signature',sig).send(raw);
  delete process.env.RAZORPAY_WEBHOOK_SECRET;await hook('0'.repeat(64)).expect(403);
  process.env.RAZORPAY_WEBHOOK_SECRET='isolated-hook';
  await hook('0'.repeat(64)).expect(400);
  const hmac=createHmac('sha256','isolated-hook').update(raw).digest('hex');
  p.status='failed';p.captured=false;
  await hook(hmac).expect(200);assert.equal((await hook(hmac).expect(200)).body.data.duplicate,true);
  assert.equal((await db.order.findUnique({where:{id:order.id}})).paymentStatus,'PAID');
  assert.equal((await db.order.findUnique({where:{id:demo.id}})).paymentStatus,'UNPAID');
  await call('get',`payments/orders/${order.id}/status`,1).expect(404);
  delete process.env.RAZORPAY_WEBHOOK_SECRET;
}
