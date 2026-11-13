import 'dotenv/config';
import {createDatabase} from '../src/database/client';
import {PasswordService} from '../src/modules/auth/password.service';
import {demoAccounts} from '../prisma/seed_auth';

async function main(){
  if(process.env.NODE_ENV!=='development'||process.env.DEMO_AUTH_ENABLED!=='true')throw new Error('Development demo reset only');
  const url=process.env.DATABASE_URL!;
  if(new URL(url).pathname!=='/food_delivery_dev')throw new Error('Expected local development database');
  const db=createDatabase(url),passwords=new PasswordService();
  try{
    const records:{email:string;passwordHash:string}[]=[];
    for(const account of demoAccounts){
      const password=process.env[account.env];
      if(!password||password.length<8||password.length>128)throw new Error('Configure demo passwords privately');
      records.push({email:account.email,passwordHash:await passwords.hash(password)});
    }
    await db.$transaction(async tx=>{
      for(const record of records){
        const user=await tx.user.findUniqueOrThrow({where:{email:record.email}});
        if(!user.isDemo)throw new Error('Refusing to change a non-demo account');
        await tx.user.update({where:{id:user.id},data:{passwordHash:record.passwordHash}});
        await tx.authSession.updateMany({where:{userId:user.id,revokedAt:null},data:{revokedAt:new Date()}});
      }
    });
    for(const account of demoAccounts){
      const user=await db.user.findUniqueOrThrow({where:{email:account.email}});
      if(!await passwords.verify(user.passwordHash,process.env[account.env]!))throw new Error('Password verification failed');
    }
    console.log('Updated and verified four demo password hashes; existing sessions revoked.');
  }finally{await db.$disconnect();}
}
main().catch(()=>{console.error('Demo password reset failed. Check local configuration.');process.exitCode=1;});
