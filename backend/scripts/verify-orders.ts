import 'dotenv/config';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createDatabase} from '../src/database/client';
const db=createDatabase(process.env.DATABASE_URL!);
async function main(){
  const report=JSON.parse(readFileSync('../docs/phase5/android-result.json','utf8'));
  const order=await db.order.findUniqueOrThrow({where:{id:report.orderId},include:{items:{include:{addOns:true}},events:true}});
  assert.equal(order.status,'PENDING_RESTAURANT');assert.equal(order.paymentStatus,'UNPAID');assert.equal(order.paymentMethod,'DEMO_NO_PAYMENT');
  assert.equal(order.finalPayablePaise,report.finalPayablePaise);assert.equal(order.items.length,2);assert.equal(order.events.length,1);assert.equal(order.events[0].eventType,'ORDER_CREATED');assert.equal(order.events[0].publishedAt,null);
  assert.ok(order.items.some(i=>i.quantity===2&&i.variantSnapshot&&i.addOns.length>0));
  assert.equal(await db.cartItem.count({where:{cart:{customerId:order.customerId}}}),0);
  const counts={restaurants:await db.restaurant.count(),items:await db.menuItem.count(),localities:await db.locality.count(),variants:await db.menuItemVariant.count(),addOns:await db.addOn.count()};
  assert.deepEqual(counts,{restaurants:28,items:224,localities:10,variants:89,addOns:10});
  const safe={orderId:order.id,orderNumber:order.orderNumber,restaurantId:order.restaurantId,status:order.status,paymentStatus:order.paymentStatus,paymentMethod:order.paymentMethod,finalPayablePaise:order.finalPayablePaise,items:order.items.map(i=>({name:i.name,quantity:i.quantity,lineTotalPaise:i.lineTotalPaise,addOnCount:i.addOns.length})),events:order.events.map(e=>({eventType:e.eventType,newStatus:e.newStatus,publishedAt:e.publishedAt})),counts};
  writeFileSync('../docs/phase5/database-verification.json',JSON.stringify(safe,null,2));console.log(JSON.stringify(safe,null,2));
}
main().catch(()=>{console.error('Read-only order verification failed. Inspect evidence without modifying orders.');process.exitCode=1;}).finally(()=>db.$disconnect());
