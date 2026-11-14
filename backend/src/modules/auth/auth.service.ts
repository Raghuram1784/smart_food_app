import { ForbiddenException, Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { DatabaseService } from '../../database/database.module';
import { AuthenticatedPrincipal } from './auth.types';
import { PasswordService } from './password.service';
import { SessionService, demoAllowed } from './session.service';
import { LoginInput, ProfileInput } from './auth.dto';
export const publicUserSelect={id:true,email:true,displayName:true,isDemo:true,roles:{select:{roleName:true}},memberships:{where:{status:'ACTIVE' as const},select:{restaurantId:true,membershipRole:true,restaurant:{select:{name:true}}}}};
@Injectable()
export class AuthService {
  constructor(@Inject(DatabaseService) private readonly database:DatabaseService,@Inject(PasswordService) private readonly passwords:PasswordService,@Inject(SessionService) private readonly sessions:SessionService){}
  async login(input:LoginInput) {
    const user=await this.database.client.user.findUnique({where:{email:input.email}});
    const valid=await this.passwords.verify(user?.passwordHash,input.password);
    if(!user||!valid||user.status!=='ACTIVE'||(user.isDemo&&!demoAllowed())) throw new UnauthorizedException('Email or password is incorrect');
    return this.database.client.$transaction(async tx=>{
      const stillActive=await tx.user.updateMany({where:{id:user.id,status:'ACTIVE',passwordHash:user.passwordHash},data:{lastLoginAt:new Date()}});
      if(!stillActive.count) throw new UnauthorizedException('Email or password is incorrect');
      const session=await this.sessions.issue(tx,user.id);
      const profile=await tx.user.findUniqueOrThrow({where:{id:user.id},select:publicUserSelect});
      return {user:profile,session};
    });
  }
  async me(principal:AuthenticatedPrincipal) {
    const user=await this.database.client.user.findUniqueOrThrow({where:{id:principal.userId},select:publicUserSelect});
    return {user,session:{expiresAt:principal.expiresAt.toISOString(),tokenType:'Bearer'}};
  }
  async update(principal:AuthenticatedPrincipal,input:ProfileInput) {
    await this.database.client.user.update({where:{id:principal.userId},data:{displayName:input.displayName}});
    return this.me(principal);
  }
  async restaurant(principal:AuthenticatedPrincipal,id:string) {
    const membership=await this.database.client.restaurantMembership.findUnique({where:{userId_restaurantId:{userId:principal.userId,restaurantId:id}},select:{status:true,membershipRole:true,restaurant:{select:{id:true,name:true,operatingStatus:true,locality:{select:{name:true}}}}}});
    if(!membership||membership.status!=='ACTIVE'||membership.membershipRole!=='OWNER') throw new ForbiddenException('No active owner membership for this restaurant');
    return {membershipRole:membership.membershipRole,restaurant:membership.restaurant,capabilities:['VIEW_RESTAURANT_CONTEXT']};
  }
  async demoRestaurants() {
    if (!demoAllowed()) throw new ForbiddenException('Demo endpoints are disabled');
    const memberships = await this.database.client.restaurantMembership.findMany({
      where: {
        status: 'ACTIVE',
        membershipRole: 'OWNER',
        user: { isDemo: true },
      },
      select: {
        restaurantId: true,
        restaurant: {
          select: {
            name: true,
            locality: { select: { name: true } },
          },
        },
        user: {
          select: {
            email: true,
          },
        },
      },
      orderBy: {
        restaurant: { name: 'asc' },
      },
    });

    return memberships.map((m) => ({
      restaurantId: m.restaurantId,
      restaurantName: m.restaurant.name,
      localityName: m.restaurant.locality?.name ?? '',
      ownerEmail: m.user.email,
    }));
  }
}
