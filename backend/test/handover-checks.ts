import assert from 'node:assert/strict';
export async function handoverChecks(t:any,app:any,db:any,call:any,api:any,fixture:any,users:any[]){
  const {HandoverRateGuard}=require('../dist/src/modules/operations/handover.controller');
  const {OperationsService}=require('../dist/src/modules/operations/operations.service');
  const guard=app.get(HandoverRateGuard);
  const withOrder=async(fn:any)=>{
    guard.buckets.clear();const o=await fixture({status:'OUT_FOR_DELIVERY'});
    await db.deliveryAssignment.create({data:{orderId:o.id,riderId:users[1].id,assignedById:users[3].id,status:'OUT_FOR_DELIVERY'}});
    try{await fn(o);}finally{await db.deliveryHandover.deleteMany({where:{orderId:o.id}});await db.deliveryAssignment.deleteMany({where:{orderId:o.id}});}
  };
  const issue=(o:any,i=0,body:any={})=>call('post',`orders/${o.id}/handover/issue`,i).send(body);
  const read=(o:any,i=0)=>call('get',`orders/${o.id}/handover`,i);
  const finish=(o:any,pin:any,i=1,extra:any={})=>call('post',`operations/delivery/orders/${o.id}/complete-handover`,i).send({pin,expectedVersion:o.version,...extra});
  const wrong=(pin:string)=>pin==='000000'?'000001':'000000';
  const record=(o:any)=>db.deliveryHandover.findUnique({where:{orderId:o.id}});
  await t.test('handover ownership, role privacy, DTO validation and legacy service bypass',()=>withOrder(async(o:any)=>{
    await api.get(`/api/v1/orders/${o.id}/handover`).expect(401);
    assert.equal((await read(o).expect(200)).body.data.state,'NOT_ISSUED');assert.equal(await record(o),null);
    await read(o,1).expect(404);for(const i of [2,3]){await read(o,i).expect(403);await issue(o,i).expect(403);}
    await issue(o,1).expect(404);await issue(o,0,{customerId:users[0].id}).expect(400);
    const pin=(await issue(o).expect(200)).body.data.pin;assert.match(pin,/^\d{6}$/);
    assert.equal((await read(o).expect(200)).body.data.pin===pin,true);
    for(const value of [123456,'12345','1234567','abcdef'])await finish(o,value).expect(400);
    await finish(o,pin,1,{riderId:users[1].id}).expect(400);
    for(const i of [0,2,3])await finish(o,pin,i).expect(403);
    await call('post',`operations/delivery/orders/${o.id}/deliver`,1).send({expectedVersion:1}).expect(409);
    await assert.rejects(app.get(OperationsService).mutate({},o.id,'deliver',1),{status:409});
    for(const path of [`orders/${o.id}`,`operations/delivery/orders/${o.id}`,`operations/dispatch/orders`]){
      const r=await call('get',path,path.includes('delivery')?1:path.includes('dispatch')?3:0).expect(200);
      for(const key of ['encryptedPin','verifier','HANDOVER_HMAC_KEY'])assert.equal(JSON.stringify(r.body).includes(key),false);
      assert.equal(JSON.stringify(r.body).includes(`"pin"`),false);
      if(path.includes('delivery'))assert.deepEqual(r.body.data.availableActions,['arrived','complete-handover']);
    }
  }));
  await t.test('handover concurrent incorrect guesses persist and lock after five',()=>withOrder(async(o:any)=>{
    const pin=(await issue(o).expect(200)).body.data.pin;
    await finish(o,wrong(pin),1,{expectedVersion:99}).expect(409);assert.equal((await record(o)).failedAttempts,0);
    const results=await Promise.all(Array.from({length:7},()=>finish(o,wrong(pin))));
    assert.deepEqual(results.map(r=>r.status).sort(),[400,400,400,400,429,429,429]);
    const h=await record(o);assert.equal(h.failedAttempts,5);assert.ok(h.lockedAt);
    assert.equal(await db.handoverAudit.count({where:{handoverId:h.id,action:'LOCKED'}}),1);
    await finish(o,pin).expect(429);await issue(o).expect(429);
    assert.equal((await read(o).expect(200)).body.data.pin,undefined);
    assert.equal((await db.order.findUnique({where:{id:o.id}})).status,'OUT_FOR_DELIVERY');
  }));
  await t.test('handover expiry, regeneration invalidation, cooldown and bounded issuance',()=>withOrder(async(o:any)=>{
    const old=(await issue(o).expect(200)).body.data.pin;await issue(o).expect(429);
    const crypto=require('../dist/src/modules/operations/handover.crypto'),keys=crypto.handoverConfig();
    const expired={...await record(o),issuedAt:new Date(Date.now()-700000),expiresAt:new Date(Date.now()-1000)};
    await db.deliveryHandover.update({where:{orderId:o.id},data:{issuedAt:expired.issuedAt,expiresAt:expired.expiresAt,nextIssueAt:new Date(0),verifier:crypto.pinVerifier(old,expired,keys.verifyKey),encryptedPin:crypto.sealPin(old,expired,keys.encryptionKey)}});
    await finish(o,old).expect(409);assert.equal((await read(o).expect(200)).body.data.state,'EXPIRED');
    const fresh=(await issue(o).expect(200)).body.data.pin;assert.equal(fresh===old,false);
    await finish(o,old).expect(400);assert.equal((await record(o)).failedAttempts,1);
    await db.deliveryHandover.update({where:{orderId:o.id},data:{nextIssueAt:new Date(0)}});
    await issue(o).expect(200);await db.deliveryHandover.update({where:{orderId:o.id},data:{nextIssueAt:new Date(0)}});
    await issue(o).expect(429);assert.equal((await record(o)).issueCount,3);
  }));
  await t.test('handover revoked, expired and inactive rider; changed assignment',()=>withOrder(async(o:any)=>{
    const pin=(await issue(o).expect(200)).body.data.pin;
    for(const data of [{revokedAt:new Date()},{expiresAt:new Date(Date.now()-1000)}]){
      await db.authSession.updateMany({where:{userId:users[1].id},data});await finish(o,pin).expect(401);
      await db.authSession.updateMany({where:{userId:users[1].id},data:{revokedAt:null,expiresAt:new Date(Date.now()+3600000)}});
    }
    await db.user.update({where:{id:users[1].id},data:{status:'DISABLED'}});
    try{await finish(o,pin).expect(401);}finally{await db.user.update({where:{id:users[1].id},data:{status:'ACTIVE'}});}
    await db.userRole.create({data:{userId:users[0].id,roleName:'DELIVERY_PARTNER'}});
    try{
      await db.deliveryAssignment.update({where:{orderId:o.id},data:{riderId:users[0].id}});
      await finish(o,pin).expect(403);await finish(o,pin,0).expect(409);
      assert.ok((await record(o)).invalidatedAt);assert.equal((await record(o)).encryptedPin,null);
      assert.equal((await read(o).expect(200)).body.data.state,'INVALIDATED');
    }finally{await db.userRole.deleteMany({where:{userId:users[0].id,roleName:'DELIVERY_PARTNER'}});}
  }));
  await t.test('handover all success writes roll back on order, assignment, event or outbox failure',()=>withOrder(async(o:any)=>{
    const pin=(await issue(o).expect(200)).body.data.pin;
    for(const [table,operation] of [['Order','UPDATE'],['DeliveryAssignment','UPDATE'],['OrderEvent','INSERT'],['OutboxEvent','INSERT']]){
      await db.$executeRawUnsafe(`CREATE FUNCTION p71_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected'; END $$`);
      await db.$executeRawUnsafe(`CREATE TRIGGER p71_fail BEFORE ${operation} ON "${table}" FOR EACH ROW EXECUTE FUNCTION p71_fail()`);
      try{
        await finish(o,pin).expect(503);const h=await record(o);assert.equal(h.consumedAt,null);assert.ok(h.encryptedPin);
        assert.equal((await db.order.findUnique({where:{id:o.id}})).version,1);
        assert.equal((await db.deliveryAssignment.findUnique({where:{orderId:o.id}})).status,'OUT_FOR_DELIVERY');
        assert.equal(await db.orderEvent.count({where:{orderId:o.id}}),0);
        assert.equal(await db.handoverAudit.count({where:{handoverId:h.id,action:'CONSUMED'}}),0);
      }finally{await db.$executeRawUnsafe(`DROP TRIGGER p71_fail ON "${table}"`);await db.$executeRawUnsafe('DROP FUNCTION p71_fail()');}
    }
    const before=await db.paymentAttempt.findMany({where:{orderId:o.id}});
    const results=await Promise.all([finish(o,pin),finish(o,pin)]);assert.deepEqual(results.map(r=>r.status),[200,200]);
    assert.deepEqual(results.map(r=>r.body.data.alreadyCompleted).sort(),[false,true]);
    const h=await record(o);assert.ok(h.consumedAt);assert.ok(h.verifiedAt);assert.equal(h.encryptedPin,null);
    assert.equal((await db.order.findUnique({where:{id:o.id}})).version,2);
    assert.equal(await db.orderEvent.count({where:{orderId:o.id,eventType:'ORDER_DELIVERED'}}),1);
    assert.equal(await db.outboxEvent.count({where:{event:{orderId:o.id}}}),1);
    assert.deepEqual(await db.paymentAttempt.findMany({where:{orderId:o.id}}),before);
    await finish(o,pin).expect(200);await finish(o,wrong(pin)).expect(409);await finish(o,pin,1,{expectedVersion:2}).expect(409);
    assert.equal((await read(o).expect(200)).body.data.state,'CONSUMED');await issue(o).expect(409);
  }));
  await t.test('handover unavailable states, missing secrets, historical delivery and request throttle',()=>withOrder(async(o:any)=>{
    for(const status of ['CANCELED','REJECTED','DELIVERED']){
      await db.order.update({where:{id:o.id},data:{status}});await issue(o).expect(409);await finish(o,'000000').expect(409);
      assert.equal((await read(o).expect(200)).body.data.state,'UNAVAILABLE');
    }
    await db.order.update({where:{id:o.id},data:{status:'OUT_FOR_DELIVERY'}});
    const key=process.env.HANDOVER_HMAC_KEY;delete process.env.HANDOVER_HMAC_KEY;
    try{await issue(o).expect(503);}finally{process.env.HANDOVER_HMAC_KEY=key;}
    guard.buckets.clear();for(let i=0;i<60;i++)await read(o).expect(200);await read(o).expect(429);guard.buckets.clear();
  }));
}
