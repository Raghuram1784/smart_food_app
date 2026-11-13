import 'dotenv/config';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';

test('isolated smart discovery and exact pricing', {timeout:120000}, async t => {
  const url=process.env.TEST_DATABASE_URL;
  assert.ok(url); assert.equal(new URL(url).pathname,'/food_delivery_test');
  process.env.DATABASE_URL=url; process.env.NODE_ENV='test';
  const {createDatabase}=require('../dist/src/database/client');
  const {createApp}=require('../dist/src/main');
  const {seedPricing}=require('../dist/prisma/seed_pricing');
  const {calculate,halfUp}=require('../dist/src/modules/pricing/pricing.calculator');
  const db=createDatabase(url), app=await createApp();
  const rid='phase3-test-kitchen',id='phase3-test-meal',sid='phase3-test-section';
  const ruleCode='PHASE3_TEST_DISCOUNT';
  let variantId:string,addOnId:string;
  try {
    await seedPricing(db);
    await db.restaurant.create({data:{id:rid,name:'Phase3 Test Kitchen',slug:rid,description:'Isolated test fixture',rating:4.5,
      estimatedDeliveryMinutes:20,estimatedDeliveryMaxMinutes:30,imageKey:'dosa',cuisineDescription:'South Indian',deliveryAvailability:true,localityId:'madhapur'}});
    await db.restaurantDeliveryZone.create({data:{restaurantId:rid,zoneId:'madhapur',isEligible:true,estimatedMinutes:25}});
    await db.menuSection.create({data:{id:sid,restaurantId:rid,name:'Test Meals'}});
    await db.menuItem.create({data:{id,restaurantId:rid,categoryId:'dosa',sectionId:sid,name:'Phase3 Masala Dosa',description:'Test breakfast',basePricePaise:12000,imageKey:'dosa',isVegetarian:true}});
    variantId=(await db.menuItemVariant.create({data:{menuItemId:id,name:'Large',priceAdjustmentPaise:2000}})).id;
    addOnId=(await db.addOn.create({data:{name:'Phase3 Test Chutney',pricePaise:500}})).id;
    await db.menuItemAddOn.create({data:{menuItemId:id,addOnId}});
    await app.init(); const api=request(app.getHttpServer());
    const input={restaurantId:rid,menuItemId:id,area:'madhapur',quantity:1,addOnIds:[]};
    const quote=async(overrides:object={})=>(await api.post('/api/v1/pricing/quote').send({...input,...overrides}).expect(200)).body.data;
    const search=async(extra:string='')=>(await api.get(`/api/v1/catalog/smart-search?area=madhapur&restaurantId=${rid}${extra}`).expect(200)).body.data;
    await t.test('options, quantity and fees are exact and applied only once',async()=>{
      let q=await quote({variantId,addOnIds:[addOnId],quantity:2});
      assert.equal(q.basePaise,24000);assert.equal(q.variantPaise,4000);assert.equal(q.addOnPaise,1000);
      assert.equal(q.packagingPaise,1000);assert.equal(q.deliveryPaise,2000);assert.equal(q.platformPaise,500);assert.equal(q.finalPayablePaise,32500);
      assert.equal(q.selectedVariant.id,variantId);assert.equal(q.selectedAddOns[0].id,addOnId);
      assert.equal(q.illustrative,true);assert.ok(Date.parse(q.expiresAt)>Date.parse(q.quotedAt));
      assert.ok(Date.parse(q.expiresAt)-Date.parse(q.quotedAt)<=120000);
      const again=await quote({variantId,addOnIds:[addOnId],quantity:2});
      assert.equal(q.quoteFingerprint,again.quoteFingerprint);assert.equal(q.pricingRuleVersion,again.pricingRuleVersion);
    });
    await t.test('invalid identifiers/options/prices/quantity never bypass validation',async()=>{
      for(const bad of [{quantity:0},{quantity:-1},{quantity:1.5},{quantity:21},{basePricePaise:1},{addOnIds:[addOnId,addOnId]},{variantId:'bad'}]){
        await api.post('/api/v1/pricing/quote').send({...input,...bad}).expect(400);
      }
      await api.post('/api/v1/pricing/quote').send({...input,variantId:'11111111-1111-4111-8111-111111111111'}).expect(422);
      await api.post('/api/v1/pricing/quote').send({...input,addOnIds:['11111111-1111-4111-8111-111111111111']}).expect(422);
      // Issue B: real variant/add-on IDs belonging to a different item must be rejected.
      const otherVariant=await db.menuItemVariant.findFirst({where:{menuItemId:{not:id},isAvailable:true}});
      assert.ok(otherVariant);
      await api.post('/api/v1/pricing/quote').send({...input,variantId:otherVariant.id}).expect(422);
      const otherAddon=await db.addOn.findFirst({where:{isAvailable:true,items:{none:{menuItemId:id}}}});
      assert.ok(otherAddon);
      await api.post('/api/v1/pricing/quote').send({...input,addOnIds:[otherAddon.id]}).expect(422);
      // Issue A: missing/inactive localities rejected cleanly on strict routes while legacy read routes stay optional.
      await api.post('/api/v1/pricing/quote').send({restaurantId:rid,menuItemId:id,quantity:1,addOnIds:[]}).expect(400);
      await api.post('/api/v1/pricing/compare').send({itemIds:[id,'dosa']}).expect(400);
      await api.post('/api/v1/pricing/quote').send({...input,area:'indiranagar'}).expect(422);
      await api.get('/api/v1/catalog/search?q=dosa').expect(200);
      await api.post('/api/v1/pricing/quote').send({...input,restaurantId:'tiffin'}).expect(422);
      await api.post('/api/v1/pricing/quote').send({...input,menuItemId:'missing'}).expect(404);
      await api.post('/api/v1/pricing/quote').send({...input,area:'secunderabad'}).expect(422);
      await api.post('/api/v1/pricing/quote').send({...input,promotion:'UNKNOWN'}).expect(422);
    });
    await t.test('discount eligibility, caps, tax HALF_UP and expiry are deterministic',async()=>{
      await db.pricingRule.create({data:{code:ruleCode,restaurantId:rid,component:'DISCOUNT',fixedPaise:1000,isActive:true,effectiveFrom:new Date('2026-01-01'),promotionCode:'TEST10'}});
      const q=await quote({promotion:'TEST10'});assert.equal(q.discountPaise,1000);assert.equal(q.finalPayablePaise,16500);
      assert.equal((await quote()).discountPaise,0);
      const base={basePricePaise:12000,variantPaise:0,addOnPaise:0,quantity:1,restaurantId:rid,area:'madhapur',promotion:'TEST10',rules:await db.pricingRule.findMany(),now:new Date()};
      assert.equal(calculate(base).finalPayablePaise,14500);
      assert.equal(halfUp(11000,625),688);
      const tax={...base.rules[0],id:'tax-test',code:'TAX_TEST',restaurantId:rid,zoneId:null,component:'TAX',fixedPaise:null,rateBasisPoints:625,promotionCode:null,maximumChargePaise:null};
      assert.equal(calculate({...base,rules:[...base.rules,tax]}).finalPayablePaise,15188);
      assert.equal(calculate({...base,rules:[...base.rules,{...tax,maximumChargePaise:100}]}).taxPaise,100);
      assert.throws(()=>calculate({...base,now:new Date('2025-01-01')}));
      await db.pricingRule.update({where:{code:ruleCode},data:{effectiveUntil:new Date('2026-01-02')}});
      await api.post('/api/v1/pricing/quote').send({...input,promotion:'TEST10'}).expect(422);
    });
    await t.test('budget boundaries use actual payable, never base price',async()=>{
      // Cheapest required variant adds 2000; fees add 3500.
      for(const [base,total,count] of [[9500,15000,1],[9499,14999,1],[9501,15001,0]]){
        await db.menuItem.update({where:{id},data:{basePricePaise:base,version:{increment:1}}});
        assert.equal((await quote()).finalPayablePaise,total);
        assert.equal((await search('&maxPayablePaise=15000')).total,count);
      }
      assert.equal((await search('&maxPayablePaise=0')).total,0);
      for(const q of ['maxPayablePaise=-1','maxPayablePaise=x','vegetarian=maybe','maxMinutes=0','sort=random','minRating=6']){
        await api.get(`/api/v1/catalog/smart-search?area=madhapur&${q}`).expect(400);
      }
      await api.get('/api/v1/catalog/smart-search').expect(400);
    });
    await t.test('combined filters, status changes, unavailable variants and seasonal records',async()=>{
      assert.equal((await search('&q=%20MASALA%20%20dosa%20&category=dosa&vegetarian=true&minRating=4&maxMinutes=30')).total,1);
      assert.equal((await search('&vegetarian=false')).total,0);
      assert.equal((await search('&maxMinutes=20')).total,0);
      assert.equal((await search('&category=pizza')).total,0);
      await db.restaurant.update({where:{id:rid},data:{operatingStatus:'PAUSED'}});
      assert.equal((await search()).total,0);await api.post('/api/v1/pricing/quote').send(input).expect(422);
      await db.restaurant.update({where:{id:rid},data:{operatingStatus:'OPEN'}});
      await db.menuItem.update({where:{id},data:{availabilityStatus:'SOLD_OUT'}});
      assert.equal((await search()).total,0);await api.post('/api/v1/pricing/quote').send(input).expect(422);
      await db.menuItem.update({where:{id},data:{availabilityStatus:'AVAILABLE'}});
      await db.menuItemVariant.update({where:{id:variantId},data:{isAvailable:false}});
      assert.equal((await search()).total,0);await api.post('/api/v1/pricing/quote').send(input).expect(422);
      await db.menuItemVariant.update({where:{id:variantId},data:{isAvailable:true}});
      await db.addOn.update({where:{id:addOnId},data:{isAvailable:false}});
      await api.post('/api/v1/pricing/quote').send({...input,addOnIds:[addOnId]}).expect(422);
      await db.addOn.update({where:{id:addOnId},data:{isAvailable:true}});
      const seasonal=await db.menuItem.findFirst({where:{availabilityStatus:'UNAVAILABLE',name:{contains:'Haleem'}}});
      assert.ok(seasonal);
      await api.post('/api/v1/pricing/quote').send({...input,menuItemId:seasonal.id,restaurantId:seasonal.restaurantId}).expect(422);
      const seasonalSearch=(await api.get('/api/v1/catalog/smart-search?area=madhapur&q=haleem').expect(200)).body.data;
      assert.equal(seasonalSearch.total,0);
      // Real ₹149 Masala Dosa (₹184 with fees) must NOT qualify under ₹150 strict budget.
      const strictDosa=(await api.get('/api/v1/catalog/smart-search?area=madhapur&q=masala%20dosa&maxPayablePaise=15000').expect(200)).body.data;
      assert.equal(strictDosa.total,0);
      const payableDosa=(await api.get('/api/v1/catalog/smart-search?area=madhapur&q=masala%20dosa&maxPayablePaise=18400').expect(200)).body.data;
      assert.ok(payableDosa.items.some((x:any)=>x.quote.item.id==='dosa'&&x.quote.finalPayablePaise===18400));
    });
    await t.test('missing required fee rule fails closed instead of defaulting to zero',async()=>{
      await db.pricingRule.update({where:{code:'DEMO_PLATFORM_V1'},data:{isActive:false}});
      try {
        await api.post('/api/v1/pricing/quote').send(input).expect(422);
        await api.get(`/api/v1/catalog/smart-search?area=madhapur&restaurantId=${rid}`).expect(422);
      } finally {
        await db.pricingRule.update({where:{code:'DEMO_PLATFORM_V1'},data:{isActive:true}});
      }
    });
    await t.test('concurrent DB price updates preserve quote consistency and isolate unrelated rule expiry',async()=>{
      await db.pricingRule.create({data:{code:'PHASE3_UNRELATED_EXPIRY',restaurantId:'tiffin',component:'DISCOUNT',fixedPaise:100,isActive:true,effectiveFrom:new Date('2026-01-01'),effectiveUntil:new Date(Date.now()+5000)}});
      try {
        const quoted=await quote();
        assert.ok(Date.parse(quoted.expiresAt)-Date.parse(quoted.quotedAt)>=60000);
        const results=await Promise.all([
          quote(),
          db.menuItem.update({where:{id},data:{basePricePaise:{increment:100},version:{increment:1}}}),
          quote(),
          search(),
        ]);
        for(const r of [results[0],results[2],results[3].items[0].quote]){
          assert.equal(r.finalPayablePaise,r.subtotalPaise-r.discountPaise+r.packagingPaise+r.deliveryPaise+r.platformPaise+r.taxPaise);
        }
      } finally {
        await db.pricingRule.deleteMany({where:{code:'PHASE3_UNRELATED_EXPIRY'}});
      }
    });
    await t.test('fresh quotes reflect price and fee changes; comparison uses the identical engine',async()=>{
      const before=await quote();
      await db.menuItem.update({where:{id},data:{basePricePaise:{increment:1},version:{increment:1}}});
      const after=await quote();assert.equal(after.finalPayablePaise,before.finalPayablePaise+1);assert.notEqual(after.quoteFingerprint,before.quoteFingerprint);
      await db.pricingRule.create({data:{code:'PHASE3_TEST_DELIVERY',restaurantId:rid,component:'DELIVERY',fixedPaise:2500,isActive:true,effectiveFrom:new Date('2026-01-01')}});
      const feeChanged=await quote();assert.equal(feeChanged.finalPayablePaise,after.finalPayablePaise+500);assert.notEqual(feeChanged.pricingRuleVersion,after.pricingRuleVersion);
      const comparison=(await api.post('/api/v1/pricing/compare').send({area:'madhapur',itemIds:[id,'dosa']}).expect(200)).body.data;
      assert.equal(comparison.items[0].finalPayablePaise,feeChanged.finalPayablePaise);
      await api.post('/api/v1/pricing/compare').send({area:'madhapur',itemIds:[id,id]}).expect(400);
    });
    await t.test('ranking, pagination and suggestions remain reproducible over real records',async()=>{
      for(const sort of ['value','price','time','rating','relevance']){
        const path=`/api/v1/catalog/smart-search?area=madhapur&sort=${sort}&limit=5`;
        const a=(await api.get(path).expect(200)).body.data,b=(await api.get(path).expect(200)).body.data;
        assert.deepEqual(a.items.map((x:any)=>x.quote.item.id),b.items.map((x:any)=>x.quote.item.id));
        assert.ok(a.items.every((x:any)=>x.quote.orderable && x.explanations.length>0));
        if(sort==='price') assert.deepEqual(a.items.map((x:any)=>x.quote.finalPayablePaise),[...a.items.map((x:any)=>x.quote.finalPayablePaise)].sort((x,y)=>x-y));
        const second=(await api.get(path+'&page=2').expect(200)).body.data;
        assert.equal(a.total,second.total);assert.ok(!second.items.some((x:any)=>a.items.some((y:any)=>x.quote.item.id===y.quote.item.id)));
      }
    });
  } finally {
    await app.close();
    // Fixed test-only IDs, child-first cleanup; guard above makes development inaccessible.
    await db.pricingRule.deleteMany({where:{code:{in:[ruleCode,'PHASE3_TEST_DELIVERY']}}});
    await db.menuItemAddOn.deleteMany({where:{menuItemId:id}});
    await db.menuItemVariant.deleteMany({where:{menuItemId:id}});
    await db.menuItem.deleteMany({where:{id}});
    await db.menuSection.deleteMany({where:{id:sid}});
    await db.restaurantDeliveryZone.deleteMany({where:{restaurantId:rid}});
    await db.restaurant.deleteMany({where:{id:rid}});
    await db.addOn.deleteMany({where:{name:'Phase3 Test Chutney'}});
    await db.$disconnect();
  }
});
