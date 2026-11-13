import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import { settings } from '../src/config/settings';

export async function seedPricing(db: ReturnType<typeof createDatabase>) {
  // Configuration only. Never updates restaurants, menus, options or existing fee rules.
  for (const [component, fixedPaise] of [['PACKAGING',1000],['DELIVERY',2000],['PLATFORM',500]] as const) {
    const code = `DEMO_${component}_V1`;
    await db.pricingRule.upsert({where:{code},update:{},create:{code,component,fixedPaise,
      isActive:true,effectiveFrom:new Date('2026-01-01T00:00:00Z'),priority:0}});
  }
}
if(require.main===module) {
  const config=settings();
  if(config.production) throw new Error('Demo pricing seed is forbidden in production');
  const db=createDatabase(config.databaseUrl);
  seedPricing(db).then(async()=>console.log(JSON.stringify({demoRules:await db.pricingRule.count({where:{code:{startsWith:'DEMO_'}}})})))
    .catch(()=>{console.error('Demo pricing seed failed');process.exitCode=1;}).finally(()=>db.$disconnect());
}
