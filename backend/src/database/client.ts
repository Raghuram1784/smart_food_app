import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client';
export function createDatabase(connectionString:string){
  const adapter=new PrismaPg({connectionString,max:5,connectionTimeoutMillis:5000,idleTimeoutMillis:30000,statement_timeout:5000,query_timeout:6000});
  return new PrismaClient({adapter,transactionOptions:{maxWait:5000,timeout:10000}});
}
