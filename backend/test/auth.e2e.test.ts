import 'dotenv/config';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import request from 'supertest';

test('database authentication and authorization boundaries',{timeout:120000},async t=>{
  const url=process.env.TEST_DATABASE_URL!;
  assert.equal(new URL(url).pathname,'/food_delivery_test');
  process.env.DATABASE_URL=url;process.env.NODE_ENV='test';process.env.DEMO_AUTH_ENABLED='true';
  execFileSync(process.execPath,['node_modules/prisma/build/index.js','migrate','deploy'],{env:{...process.env,DIRECT_URL:url},stdio:'pipe'});
  const {createDatabase}=require('../dist/src/database/client');
  const {createApp}=require('../dist/src/main');
  const {PasswordService}=require('../dist/src/modules/auth/password.service');
  const {hashToken,SessionService}=require('../dist/src/modules/auth/session.service');
  const {seedAuth}=require('../dist/prisma/seed_auth');
  const db=createDatabase(url),app=await createApp(),password=randomBytes(24).toString('base64url');
  const users:any[]=[],tokens:string[]=[];
  const prefix=randomBytes(6).toString('hex');
  try{
    const counts=await Promise.all([db.restaurant.count(),db.menuItem.count(),db.locality.count()]);
    const hash=await new PasswordService().hash(password);assert.ok(hash.startsWith('$argon2id$'));
    for(const role of ['CUSTOMER','RESTAURANT_OWNER','DELIVERY_PARTNER','ADMIN']){
      await db.role.upsert({where:{name:role},update:{},create:{name:role}});
      users.push(await db.user.create({data:{email:`${prefix}-${role.toLowerCase()}@test.invalid`,displayName:'Auth test',passwordHash:hash,roles:{create:{roleName:role}},...(role==='RESTAURANT_OWNER'?{memberships:{create:{restaurantId:'deccan-handi-gachi'}}}:{})}}));
    }
    await app.init();const api=request(app.getHttpServer());
    const login=async(index=0)=>(await api.post('/api/v1/auth/login').send({email:users[index].email.toUpperCase(),password}).expect(200)).body.data;
    const get=(path:string,token:string)=>api.get(`/api/v1/${path}`).set('Authorization',`Bearer ${token}`);
    await t.test('four roles authenticate; only token hashes persist; response is safe',async()=>{
      for(let i=0;i<4;i++){
        const data=await login(i);tokens.push(data.session.token);
        assert.match(data.session.token,/^[A-Za-z0-9_-]{43}$/);assert.equal(data.user.id,users[i].id);
        assert.equal(data.user.passwordHash,undefined);assert.equal(data.session.tokenHash,undefined);
        const row=await db.authSession.findUniqueOrThrow({where:{tokenHash:hashToken(data.session.token)}});
        assert.notEqual(row.tokenHash,data.session.token);assert.ok(row.expiresAt>new Date());
        await get('auth/me',data.session.token).expect(200);
      }
      assert.equal(new Set(tokens).size,4);
    });
    await t.test('wrong credentials, missing sessions and tampering fail safely',async()=>{
      const a=await api.post('/api/v1/auth/login').send({email:users[0].email,password:'wrong'}).expect(401);
      const b=await api.post('/api/v1/auth/login').send({email:'absent@test.invalid',password:'wrong'}).expect(401);
      assert.deepEqual(a.body.error.message,b.body.error.message);
      await api.get('/api/v1/auth/me').expect(401);
      await get('auth/me','x'.repeat(43)).expect(401);
      await api.post('/api/v1/auth/login').send({email:users[0].email,password,role:'ADMIN'}).expect(400);
      await api.post('/api/v1/auth/register').send({role:'ADMIN'}).expect(404);
      await api.patch('/api/v1/auth/me').set('Authorization',`Bearer ${tokens[0]}`).send({displayName:'Changed',roles:['ADMIN']}).expect(400);
      const updated=await api.patch('/api/v1/auth/me').set('Authorization',`Bearer ${tokens[0]}`).send({displayName:'Changed'}).expect(200);
      assert.equal(updated.body.data.user.displayName,'Changed');
    });
    await t.test('RBAC and active restaurant ownership are enforced on every request',async()=>{
      await get('account/admin',tokens[0]).expect(403);await get('account/admin',tokens[3]).expect(200);
      await get('account/delivery',tokens[2]).expect(200);await get('account/delivery',tokens[3]).expect(403);
      await get('account/restaurant/deccan-handi-gachi',tokens[1]).expect(200);
      await get('account/restaurant/another-restaurant',tokens[1]).expect(403);
      await db.restaurantMembership.updateMany({where:{userId:users[1].id},data:{status:'SUSPENDED'}});
      await get('account/restaurant/deccan-handi-gachi',tokens[1]).expect(403);
      await db.userRole.deleteMany({where:{userId:users[3].id}});
      await get('account/admin',tokens[3]).expect(403);
      await db.user.update({where:{id:users[2].id},data:{status:'DISABLED'}});
      await get('auth/me',tokens[2]).expect(401);
      await api.post('/api/v1/auth/login').send({email:users[2].email,password}).expect(401);
    });
    await t.test('expiry, logout and logout-all invalidate issued credentials',async()=>{
      const expired=await login();
      await db.authSession.update({where:{tokenHash:hashToken(expired.session.token)},data:{createdAt:new Date(Date.now()-20000),expiresAt:new Date(Date.now()-10000)}});
      await get('auth/me',expired.session.token).expect(401);
      await api.post('/api/v1/auth/logout').set('Authorization',`Bearer ${tokens[0]}`).expect(200);
      await get('auth/me',tokens[0]).expect(401);
      const a=await login(),b=await login();
      await api.post('/api/v1/auth/logout-all').set('Authorization',`Bearer ${a.session.token}`).expect(200);
      await get('auth/me',a.session.token).expect(401);await get('auth/me',b.session.token).expect(401);
    });
    await t.test('demo seed is idempotent and production refuses demo configuration',async()=>{
      await seedAuth(db);const before=await db.user.findMany({where:{isDemo:true},orderBy:{email:'asc'}});
      await seedAuth(db);const after=await db.user.findMany({where:{isDemo:true},orderBy:{email:'asc'}});
      assert.deepEqual(after,before);
      // Exactly the seeded demo set (the second customer supports group-order testing).
      assert.deepEqual(before.map((u:any)=>u.email),['admin@demo.test','customer@demo.test','friend@demo.test','restaurant@demo.test','rider@demo.test']);
      assert.equal(await db.restaurantMembership.count({where:{user:{email:'restaurant@demo.test'}}}),1);
      await assert.rejects(()=>seedAuth(db,{NODE_ENV:'production',DEMO_AUTH_ENABLED:'true'}));
      process.env.NODE_ENV='production';assert.throws(()=>new SessionService({client:db}));process.env.NODE_ENV='test';
      assert.deepEqual(await Promise.all([db.restaurant.count(),db.menuItem.count(),db.locality.count()]),counts);
      await api.get('/api/v1/catalog/search?q=dosa').expect(200);
    });
    await t.test('repeated invalid credentials are rate limited',async()=>{
      for(let i=0;i<10;i++)await api.post('/api/v1/auth/login').send({email:'limited@test.invalid',password:'bad'}).expect(401);
      await api.post('/api/v1/auth/login').send({email:'limited@test.invalid',password:'bad'}).expect(429);
    });
  }finally{
    process.env.NODE_ENV='test';const ids=users.map(u=>u.id);
    await db.authSession.deleteMany({where:{userId:{in:ids}}});await db.restaurantMembership.deleteMany({where:{userId:{in:ids}}});
    await db.userRole.deleteMany({where:{userId:{in:ids}}});await db.user.deleteMany({where:{id:{in:ids}}});
    await app.close();await db.$disconnect();
  }
});
