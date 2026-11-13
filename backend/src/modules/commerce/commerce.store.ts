import {ConflictException,Inject,Injectable,UnauthorizedException} from '@nestjs/common';
import {DatabaseService} from '../../database/database.module';
import {Prisma} from '../../generated/prisma/client';
import {AuthenticatedPrincipal} from '../auth/auth.types';

export const cartInclude={restaurant:{select:{id:true,name:true,imageKey:true}},items:{orderBy:{createdAt:'asc' as const},include:{menuItem:{select:{id:true,name:true,imageKey:true,basePricePaise:true,availabilityStatus:true}},variant:true,addOns:{include:{addOn:true}}}}};
export type LoadedCart=Prisma.CartGetPayload<{include:typeof cartInclude}>;
export const orderInclude={items:{include:{addOns:true}},events:{orderBy:{createdAt:'asc' as const},select:{id:true,eventType:true,newStatus:true,previousStatus:true,sequence:true,createdAt:true}}};
@Injectable()
export class CommerceStore {
  constructor(@Inject(DatabaseService) readonly database:DatabaseService){}
  async run<T>(principal:AuthenticatedPrincipal,work:(tx:Prisma.TransactionClient)=>Promise<T>):Promise<T>{
    for(let attempt=0;attempt<4;attempt++){
      try{return await this.database.client.$transaction(async tx=>{
        // Serializes cart, address and checkout changes across all sessions of one customer.
        await tx.$queryRaw`SELECT id FROM "User" WHERE id=${principal.userId}::uuid FOR UPDATE`;
        const session=await tx.authSession.findFirst({where:{id:principal.sessionId,userId:principal.userId,revokedAt:null,expiresAt:{gt:new Date()},user:{status:'ACTIVE',roles:{some:{roleName:'CUSTOMER'}}}}});
        if(!session)throw new UnauthorizedException('Customer session is no longer active');
        return work(tx);
      },{isolationLevel:'Serializable',timeout:15000});}
      catch(e){if((e as {code?:string}).code!=='P2034')throw e;if(attempt===3)throw new ConflictException('Concurrent update; refresh and retry');}
    }
    throw new ConflictException('Please retry');
  }
  async cart(tx:Prisma.TransactionClient,customerId:string){
    return tx.cart.upsert({where:{customerId},create:{customerId},update:{},include:cartInclude});
  }
  version(cart:LoadedCart,expected:number){if(cart.version!==expected)throw new ConflictException('Cart changed. Refresh before continuing.');}
}
