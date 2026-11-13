import 'dotenv/config';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {writeFileSync,existsSync,readFileSync} from 'node:fs';
import request from 'supertest';

async function main(){
  assert.equal(process.env.NODE_ENV,'development');
  const {createApp}=require('../dist/src/main');
  const {createDatabase}=require('../dist/src/database/client');
  const app=await createApp(),db=createDatabase(process.env.DATABASE_URL);
  try{
    await app.init();const api=request(app.getHttpServer());
    const login=await api.post('/api/v1/auth/login').send({email:'customer@demo.test',password:process.env.DEMO_CUSTOMER_PASSWORD}).expect(200);
    const token=login.body.data.session.token;
    const call=(method:string,path:string)=>api[method as 'get']('/api/v1/'+path).set('Authorization','Bearer '+token);
    const evidence='../build/razorpay-test-order.json';
    let orderId:string;
    if(existsSync(evidence)){orderId=JSON.parse(readFileSync(evidence,'utf8')).orderId;}
    else{
      let cart=(await call('get','cart').expect(200)).body.data;
      assert.equal(cart.items.length,0,'Existing customer cart must be preserved; stop if nonempty');
      const address=(await call('get','addresses').expect(200)).body.data.find((a:any)=>a.isDefault);
      assert.ok(address,'Existing default address required');
      const item=await db.menuItem.findFirstOrThrow({where:{restaurantId:'deccan-handi-gachi',availabilityStatus:'AVAILABLE'}});
      cart=(await call('post','cart/items').send({restaurantId:item.restaurantId,menuItemId:item.id,area:address.localityId,quantity:1,addOnIds:[],expectedVersion:cart.version}).expect(200)).body.data;
      const q=(await call('post','cart/quote').send({addressId:address.id,expectedVersion:cart.version}).expect(200)).body.data;
      const order=(await call('post','orders').send({cartId:cart.id,addressId:address.id,quoteId:q.quoteId,idempotencyKey:randomUUID(),paymentMethod:'RAZORPAY_TEST'}).expect(200)).body.data;
      orderId=order.id;writeFileSync(evidence,JSON.stringify({orderId,orderNumber:order.orderNumber},null,2));
    }
    const response=await call('post','payments/razorpay/create-order').send({orderId});
    console.log(JSON.stringify({check:'genuine_provider_order',httpStatus:response.status,amount:response.body.data?.amount,currency:response.body.data?.currency,testMode:response.body.data?.testMode}));
    assert.equal(response.status,200);
    const status=(await call('get',`payments/orders/${orderId}/status`).expect(200)).body.data;
    console.log(JSON.stringify({check:'persisted_payment',paymentStatus:status.paymentStatus,attemptStatus:status.attempt?.status}));
    await call('post','auth/logout').send({});
  }finally{await app.close();await db.$disconnect();}
}
main().catch(()=>{console.error('Real provider check stopped. Inspect non-secret assertions and saved order reference before retrying.');process.exitCode=1;});

