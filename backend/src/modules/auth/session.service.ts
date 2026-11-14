import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import { DatabaseService } from '../../database/database.module';
import { Prisma } from '../../generated/prisma/client';
import { AuthenticatedPrincipal, SessionVerifier } from './auth.types';
export const hashToken=(token:string)=>createHash('sha256').update(token).digest('hex');
export function demoAllowed() { return process.env.NODE_ENV!=='production' && process.env.DEMO_AUTH_ENABLED==='true'; }
export function sessionHours() {
  const hours=Number(process.env.AUTH_SESSION_HOURS??12);
  if(!Number.isInteger(hours)||hours<1||hours>168) throw new Error('AUTH_SESSION_HOURS must be 1–168');
  return hours;
}
@Injectable()
export class SessionService extends SessionVerifier {
  constructor(@Inject(DatabaseService) private readonly database:DatabaseService) {super();sessionHours();
    if(process.env.NODE_ENV==='production'&&process.env.DEMO_AUTH_ENABLED==='true') throw new Error('Demo authentication is forbidden in production');
  }
  async issue(tx:Prisma.TransactionClient,userId:string) {
    const token=randomBytes(32).toString('base64url');
    const expiresAt=new Date(Date.now()+sessionHours()*3600000);
    await tx.authSession.create({data:{userId,tokenHash:hashToken(token),expiresAt}});
    return {token,expiresAt:expiresAt.toISOString(),tokenType:'Bearer'};
  }
  async authenticate(token:string):Promise<AuthenticatedPrincipal> {
    if(!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new UnauthorizedException('Session is invalid or expired');
    const row=await this.database.client.authSession.findUnique({where:{tokenHash:hashToken(token)},include:{user:{include:{roles:true}}}});
    const now=new Date();
    if(!row||row.revokedAt||row.expiresAt<=now||row.user.status!=='ACTIVE'||(row.user.isDemo&&!demoAllowed())) throw new UnauthorizedException('Session is invalid or expired');
    if(now.getTime()-row.lastUsedAt.getTime()>60000) await this.database.client.authSession.updateMany({where:{id:row.id,revokedAt:null,expiresAt:{gt:now}},data:{lastUsedAt:now}});
    return {userId:row.userId,sessionId:row.id,roles:row.user.roles.map(r=>r.roleName),expiresAt:row.expiresAt};
  }
  async revoke(principal:AuthenticatedPrincipal,all=false) {
    await this.database.client.$transaction(async tx=>{
      // Same per-user row lock as login: logout-all has a well-defined ordering against issuance.
      await tx.$queryRaw`SELECT id FROM "User" WHERE id=${principal.userId}::uuid FOR UPDATE`;
      await tx.authSession.updateMany({where:{userId:principal.userId,...(!all?{id:principal.sessionId}:{}),revokedAt:null},data:{revokedAt:new Date()}});
      // A signed-out rider must never stay dispatchable on a stale presence row.
      await tx.riderPresence.updateMany({where:{userId:principal.userId,isOnline:true},data:{isOnline:false,lastOfflineAt:new Date()}});
    });
    return {revoked:true};
  }
}
