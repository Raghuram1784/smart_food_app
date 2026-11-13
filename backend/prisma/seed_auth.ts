import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import { PasswordService } from '../src/modules/auth/password.service';
import { demoAllowed } from '../src/modules/auth/session.service';
import { RoleName } from '../src/generated/prisma/client';
export const demoAccounts: {email:string;role:RoleName;displayName:string;env:string}[]=[
  {email:'customer@demo.test',role:'CUSTOMER',displayName:'Demo Customer',env:'DEMO_CUSTOMER_PASSWORD'},
  {email:'restaurant@demo.test',role:'RESTAURANT_OWNER',displayName:'Demo Restaurant Owner',env:'DEMO_RESTAURANT_PASSWORD'},
  {email:'rider@demo.test',role:'DELIVERY_PARTNER',displayName:'Demo Delivery Partner',env:'DEMO_RIDER_PASSWORD'},
  {email:'admin@demo.test',role:'ADMIN',displayName:'Demo Administrator',env:'DEMO_ADMIN_PASSWORD'},
];
export async function seedAuth(db:ReturnType<typeof createDatabase>,env:NodeJS.ProcessEnv=process.env) {
  if(!['development','test'].includes(env.NODE_ENV??'')||env.DEMO_AUTH_ENABLED!=='true') throw new Error('Explicit non-production demo authentication is required');
  const passwords=new PasswordService();
  const records: (typeof demoAccounts[number] & {passwordHash:string})[]=[];
  for(const account of demoAccounts){
    const password=env[account.env];
    if(!password||password.length<8||password.length>128) throw new Error(`Configure an 8–128 character ${account.env} privately`);
    records.push({...account,passwordHash:await passwords.hash(password)});
  }
  await db.$transaction(async tx=>{
    await tx.restaurant.findUniqueOrThrow({where:{id:'deccan-handi-gachi'}});
    for(const record of records){
      await tx.role.upsert({where:{name:record.role},update:{},create:{name:record.role}});
      const existing=await tx.user.findUnique({where:{email:record.email}});
      if(existing){if(!existing.isDemo) throw new Error('Refusing to alter an existing non-demo account');continue;}
      await tx.user.create({data:{email:record.email,displayName:record.displayName,passwordHash:record.passwordHash,isDemo:true,
        roles:{create:{roleName:record.role}},...(record.role==='RESTAURANT_OWNER'?{memberships:{create:{restaurantId:'deccan-handi-gachi',membershipRole:'OWNER'}}}:{})}});
    }
  });
}
if(require.main===module){
  if(!demoAllowed()) throw new Error('Demo seeding disabled');
  const db=createDatabase(process.env.DATABASE_URL!);
  seedAuth(db).then(()=>console.log('Demo accounts verified; existing credentials were not reset.'))
    .catch(()=>{console.error('Demo seed failed. Check private configuration and required restaurant.');process.exitCode=1;}).finally(()=>db.$disconnect());
}
