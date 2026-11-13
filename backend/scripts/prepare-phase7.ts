import 'dotenv/config';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {writeFileSync,existsSync,readFileSync} from 'node:fs';
import request from 'supertest';

async function main(){
  assert.equal(process.env.NODE_ENV,'development');
  const {createDatabase}=require('../dist/src/database/client');
  const db=createDatabase(process.env.DATABASE_URL);
  try{
    const api=request('http://127.0.0.1:5000');
    const login=await api.post('/api/v1/auth/login').send({email:'customer@demo.test',password:process.env.DEMO_CUSTOMER_PASSWORD}).expect(200);
    const token=login.body.data.session.token;
    const call=(method:string,path:string)=>api[method as 'get']('/api/v1/'+path).set('Authorization','Bearer '+token);
    const evidence='../build/phase7-order.json';
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
      const order=(await call('post','orders').send({cartId:cart.id,addressId:address.id,quoteId:q.quoteId,idempotencyKey:randomUUID(),paymentMethod:'DEMO_NO_PAYMENT'}).expect(200)).body.data;
      orderId=order.id;writeFileSync(evidence,JSON.stringify({orderId,orderNumber:order.orderNumber},null,2));
    }
    console.log(JSON.stringify({check:'phase7_demo_order_ready',orderId}));
    await call('post','auth/logout').send({});
  }finally{await db.$disconnect();}
}
main().catch(()=>{console.error('Phase 7 preparation stopped; preserve the cart and inspect the saved order reference before retrying.');process.exitCode=1;});

