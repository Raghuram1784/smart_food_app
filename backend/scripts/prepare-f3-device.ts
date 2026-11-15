import 'dotenv/config';
import {randomBytes,randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {createDatabase} from '../src/database/client';
import {PasswordService} from '../src/modules/auth/password.service';
async function main(){
 if(process.env.NODE_ENV!=='development'||new URL(process.env.DATABASE_URL!).pathname!=='/food_delivery_dev')throw Error('Development only');
 const db=createDatabase(process.env.DATABASE_URL!);try{
 const password=randomBytes(24).toString('base64url'),hash=await new PasswordService().hash(password),defs:any={API_BASE_URL:'http://127.0.0.1:5000/api/v1/',F3_PASSWORD:password,F3_RESTAURANT:'deccan-handi-gachi'};
 for(const [name,role] of [['CUSTOMER','CUSTOMER'],['OWNER','RESTAURANT_OWNER'],['RIDER','DELIVERY_PARTNER']] as const){
 const email=`f3-device-${name.toLowerCase()}-${randomUUID()}@test.invalid`;
 await db.user.create({data:{email,displayName:'NeuroX demo '+name.toLowerCase(),passwordHash:hash,roles:{create:{roleName:role}},...(role==='RESTAURANT_OWNER'?{memberships:{create:{restaurantId:defs.F3_RESTAURANT}}}:{})}});defs['F3_'+name+'_EMAIL']=email;
 }
 const dish=await db.menuItem.findFirstOrThrow({where:{restaurantId:defs.F3_RESTAURANT,availabilityStatus:'AVAILABLE',variants:{none:{}}}});defs.F3_DISH=dish.id;
 writeFileSync('../build/f3-device-defines.json',JSON.stringify(defs),{mode:0o600});console.log('Synthetic device accounts prepared; credentials saved only in ignored build file.');
 }finally{await db.$disconnect();}
}
main().catch(()=>{console.error('Device setup failed');process.exitCode=1;});
