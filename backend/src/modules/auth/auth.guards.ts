import { CanActivate, createParamDecorator, ExecutionContext, ForbiddenException, HttpException, Inject, Injectable, SetMetadata, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { createHash } from 'node:crypto';
import { RoleName } from '../../generated/prisma/client';
import { AuthenticatedPrincipal, SessionVerifier } from './auth.types';
export type AuthRequest=Request & {principal:AuthenticatedPrincipal};
export const CurrentUser=createParamDecorator((_:unknown,context:ExecutionContext)=>context.switchToHttp().getRequest<AuthRequest>().principal);
export const Roles=(...roles:RoleName[])=>SetMetadata('auth.roles',roles);
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(@Inject(SessionVerifier) private readonly sessions:SessionVerifier){}
  async canActivate(context:ExecutionContext) {
    const request=context.switchToHttp().getRequest<AuthRequest>();
    const header=request.headers.authorization;
    if(!header||!/^Bearer [A-Za-z0-9_-]{43}$/.test(header)) throw new UnauthorizedException('Sign in to continue');
    request.principal=await this.sessions.authenticate(header.slice(7));return true;
  }
}
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(@Inject(Reflector) private readonly reflector:Reflector){}
  canActivate(context:ExecutionContext) {
    const required=this.reflector.getAllAndOverride<RoleName[]>('auth.roles',[context.getHandler(),context.getClass()])??[];
    const principal=context.switchToHttp().getRequest<AuthRequest>().principal;
    if(!principal||!required.some(role=>principal.roles.includes(role))) throw new ForbiddenException('This account does not have permission');
    return true;
  }
}
@Injectable()
export class LoginRateGuard implements CanActivate {
  // Single-process limiter. No forwarded header is trusted. Bound memory and fail closed on saturation.
  private readonly buckets=new Map<string,{count:number;until:number}>();
  canActivate(context:ExecutionContext) {
    const req=context.switchToHttp().getRequest<Request>(),now=Date.now();
    for(const [key,bucket] of this.buckets) if(bucket.until<=now) this.buckets.delete(key);
    const email=typeof req.body?.email==='string'?req.body.email.trim().toLowerCase().slice(0,254):'';
    const emailKey=createHash('sha256').update(email).digest('hex');
    const keys:[string,number][]=[[`ip:${req.socket.remoteAddress}`,30],[`email:${emailKey}`,10]];
    for(const [key,limit] of keys) {
      const entry=this.buckets.get(key);
      if((entry&&entry.count>=limit)||(!entry&&this.buckets.size>=5000)) throw new HttpException('Too many sign-in attempts. Try again later.',429);
    }
    for(const [key] of keys){const entry=this.buckets.get(key)??{count:0,until:now+600000};entry.count++;this.buckets.set(key,entry);}
    return true;
  }
}
