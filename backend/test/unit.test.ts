import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';
// Compiled code is intentional: Nest DTO validation requires emitted decorator metadata.
const { settings } = require('../dist/src/config/settings');
const { CatalogQuery } = require('../dist/src/common/dto/catalog-query.dto');
const { SmartQuery } = require('../dist/src/modules/catalog/smart-query.dto');
const { QuoteInput, CompareInput } = require('../dist/src/modules/pricing/pricing.dto');
const { HealthController } = require('../dist/src/modules/health/health.module');
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';

test('configuration rejects missing credentials, invalid ports, wildcard CORS and plaintext production', () => {
  assert.throws(() => settings({}), /DATABASE_URL/);
  const valid = { DATABASE_URL: 'postgresql://app:placeholder@localhost/test' };
  assert.equal(settings(valid).port, 5000);
  assert.throws(() => settings({ ...valid, PORT: '0' }), /PORT/);
  assert.throws(() => settings({ ...valid, CORS_ORIGINS: '*' }), /explicit/);
  assert.throws(() => settings({ ...valid, NODE_ENV: 'production' }), /TLS/);
});
test('query normalization and validation reject unbounded or malformed values', async () => {
  const good = plainToInstance(CatalogQuery, { q: '  tomato   basil ', page: '2', area: 'madhapur' });
  assert.equal((good as any).q, 'tomato basil');
  assert.equal((good as any).area, 'madhapur');
  assert.equal((await validate(good as object)).length, 0);
  for (const query of [{ page: 0 }, { limit: 51 }, { limit: 'NaN' }, { category: '../' }, { area: '../' }, { maxPricePaise: -1 }, { q: ['dosa'] }]) {
    assert.ok((await validate(plainToInstance(CatalogQuery, query) as object)).length > 0);
  }
  // Issue A regression: CatalogQuery allows omitted area while strict Phase 3 contracts require active locality format.
  assert.equal((await validate(plainToInstance(CatalogQuery, { q: 'dosa' }) as object)).length, 0);
  const validSmart = plainToInstance(SmartQuery, { area: 'madhapur', vegetarian: 'true', maxPayablePaise: '15000', minRating: '4.5', maxMinutes: '30', sort: 'price' });
  assert.equal((validSmart as any).vegetarian, true);
  assert.equal((await validate(validSmart as object)).length, 0);
  for (const badSmart of [{}, { area: '' }, { area: 'INVALID' }, { area: '../madhapur' }, { area: 'gachibowli', vegetarian: 'maybe' }, { area: 'madhapur', maxPayablePaise: -1 }, { area: 'madhapur', sort: 'random' }, { area: 'madhapur', minRating: 6 }]) {
    assert.ok((await validate(plainToInstance(SmartQuery, badSmart) as object)).length > 0);
  }
  assert.equal((await validate(plainToInstance(QuoteInput, { restaurantId: 'tiffin', menuItemId: 'dosa', area: 'madhapur' }) as object)).length, 0);
  for (const badQuote of [{ restaurantId: 'tiffin', menuItemId: 'dosa' }, { restaurantId: 'tiffin', menuItemId: 'dosa', area: 'INVALID' }, { menuItemId: 'dosa', area: 'madhapur' }]) {
    assert.ok((await validate(plainToInstance(QuoteInput, badQuote) as object)).length > 0);
  }
  assert.equal((await validate(plainToInstance(CompareInput, { area: 'madhapur', itemIds: ['dosa', 'idli'] }) as object)).length, 0);
  for (const badCompare of [{ itemIds: ['dosa', 'idli'] }, { area: 'INVALID', itemIds: ['dosa', 'idli'] }, { area: 'madhapur', itemIds: ['dosa'] }, { area: 'madhapur', itemIds: ['dosa', 'dosa'] }]) {
    assert.ok((await validate(plainToInstance(CompareInput, badCompare) as object)).length > 0);
  }
});
test('health reports a safe 503 when database access fails', async () => {
  const controller = new HealthController({ client: { $queryRaw: async () => { throw new Error('private database detail'); } } });
  await assert.rejects(controller.health(), (e: any) => e.getStatus() === 503 && e.message === 'Database unavailable');
});


test('handover cryptography preserves zeros, binds context and rejects tampering',()=>{
  const c=require('../dist/src/modules/operations/handover.crypto');
  const {randomBytes}=require('node:crypto');const key=randomBytes(32),enc=randomBytes(32);
  const b={orderId:'order',assignmentId:'assignment',boundRiderId:'rider',challengeVersion:1,issuedAt:new Date(),expiresAt:new Date(Date.now()+600000),keyVersion:'v1'};
  assert.equal(c.formatPin(0),'000000');assert.equal(c.formatPin(1),'000001');assert.equal(c.formatPin(999999),'999999');
  for(let i=0;i<100;i++)assert.match(c.generatePin(),/^\d{6}$/);
  const v=c.pinVerifier('000001',b,key),sealed=c.sealPin('000001',b,enc);
  assert.equal(c.matchesPin('000001',b,v,key),true);assert.equal(c.matchesPin('000002',b,v,key),false);
  assert.equal(c.openPin(sealed,b,enc),'000001');assert.notEqual(c.sealPin('000001',b,enc),sealed);
  for(const patch of [{orderId:'another'},{assignmentId:'another'},{boundRiderId:'another'},{challengeVersion:2},{expiresAt:new Date(0)}]){
    assert.equal(c.matchesPin('000001',{...b,...patch},v,key),false);assert.throws(()=>c.openPin(sealed,{...b,...patch},enc));
  }
  assert.throws(()=>c.openPin(sealed,b,key));assert.throws(()=>c.openPin('corrupt',b,enc));
  const bytes=Buffer.from(sealed,'base64');bytes[15]^=1;assert.throws(()=>c.openPin(bytes.toString('base64'),b,enc));
});

test('payment gating: test mode needs dev/test or an explicit production opt-in; live keys and production demo checkout are refused', () => {
  const { paymentConfig, paymentMethods } = require('../dist/src/modules/payments/razorpay.provider');
  const saved = { ...process.env };
  const set = (env: Record<string, string | undefined>) => { for (const k of ['NODE_ENV', 'PAYMENTS_TEST_MODE_ENABLED', 'RAZORPAY_KEY_ID', 'RAZORPAY_KEY_SECRET', 'DEMO_CHECKOUT_ENABLED']) delete process.env[k]; Object.assign(process.env, env); };
  try {
    const keys = { RAZORPAY_KEY_ID: 'rzp_test_abc123', RAZORPAY_KEY_SECRET: 'placeholder' };
    set({ NODE_ENV: 'development', ...keys, DEMO_CHECKOUT_ENABLED: 'true' });
    assert.deepEqual(paymentMethods().methods, ['RAZORPAY_TEST', 'DEMO_NO_PAYMENT']);
    set({ NODE_ENV: 'production', ...keys, DEMO_CHECKOUT_ENABLED: 'true' });
    assert.throws(() => paymentConfig(), /not configured/);
    assert.deepEqual(paymentMethods().methods, []);
    set({ NODE_ENV: 'production', ...keys, PAYMENTS_TEST_MODE_ENABLED: 'true', DEMO_CHECKOUT_ENABLED: 'true' });
    assert.equal(paymentConfig().keyId, 'rzp_test_abc123');
    assert.deepEqual(paymentMethods().methods, ['RAZORPAY_TEST']);
    set({ NODE_ENV: 'production', RAZORPAY_KEY_ID: 'rzp_live_abc123', RAZORPAY_KEY_SECRET: 'placeholder', PAYMENTS_TEST_MODE_ENABLED: 'true' });
    assert.throws(() => paymentConfig(), /not configured/);
    set({ NODE_ENV: 'staging', ...keys, PAYMENTS_TEST_MODE_ENABLED: 'true' });
    assert.throws(() => paymentConfig(), /not configured/);
    set({ NODE_ENV: 'production', RAZORPAY_KEY_ID: 'rzp_test_abc123', PAYMENTS_TEST_MODE_ENABLED: 'true' });
    assert.throws(() => paymentConfig(), /not configured/);
  } finally { for (const k of Object.keys(process.env)) if (!(k in saved)) delete process.env[k]; Object.assign(process.env, saved); }
});

test('rider earnings: 10% default commission in integer paise; configurable; never negative', () => {
  const { deliverySplit, riderCommissionBps } = require('../dist/src/modules/insights/insights.module');
  assert.deepEqual(deliverySplit(100000, 1000), { grossPaise: 100000, commissionPaise: 10000, netPaise: 90000 });
  assert.deepEqual(deliverySplit(3500, 1000), { grossPaise: 3500, commissionPaise: 350, netPaise: 3150 });
  assert.deepEqual(deliverySplit(0, 1000), { grossPaise: 0, commissionPaise: 0, netPaise: 0 });
  const saved = process.env.RIDER_COMMISSION_BPS;
  try {
    delete process.env.RIDER_COMMISSION_BPS; assert.equal(riderCommissionBps(), 1000);
    process.env.RIDER_COMMISSION_BPS = '1500'; assert.equal(riderCommissionBps(), 1500);
    process.env.RIDER_COMMISSION_BPS = '-5'; assert.equal(riderCommissionBps(), 1000);
  } finally { if (saved === undefined) delete process.env.RIDER_COMMISSION_BPS; else process.env.RIDER_COMMISSION_BPS = saved; }
});
