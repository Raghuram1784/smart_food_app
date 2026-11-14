import {Body,CanActivate,Controller,ExecutionContext,Get,HttpCode,HttpException,Inject,Injectable,Param,Post,UseGuards} from '@nestjs/common';
import {IsInt,IsString,Matches,Min} from 'class-validator';
import {AuthGuard,AuthRequest,CurrentUser,Roles,RolesGuard} from '../auth/auth.guards';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {UuidParam} from '../commerce/commerce.dto';
import {HandoverService} from './handover.service';

export class CompleteHandoverInput {
  @IsString() @Matches(/^\d{6}$/) pin!:string;
  @IsInt() @Min(1) expectedVersion!:number;
}
export class IssueHandoverInput {} // Reject unknown identity/amount/PIN properties through the global whitelist.
@Injectable()
export class HandoverRateGuard implements CanActivate {
  readonly buckets=new Map<string,{count:number;until:number}>();
  canActivate(context:ExecutionContext){
    const req=context.switchToHttp().getRequest<AuthRequest>(),now=Date.now();
    for(const [key,b] of this.buckets)if(b.until<=now)this.buckets.delete(key);
    const key=`${req.principal.userId}:${req.method}`,limit=req.method==='GET'?60:30;
    const b=this.buckets.get(key)??{count:0,until:now+60000};
    if(b.count>=limit||(!this.buckets.has(key)&&this.buckets.size>=5000))throw new HttpException('Too many handover requests. Retry later.',429);
    b.count++;this.buckets.set(key,b);return true;
  }
}
@Controller('orders') @UseGuards(AuthGuard,RolesGuard,HandoverRateGuard) @Roles('CUSTOMER')
export class CustomerHandoverController {
  constructor(@Inject(HandoverService) readonly service:HandoverService){}
  @Get(':id/handover') read(@CurrentUser() p:AuthenticatedPrincipal,@Param() ids:UuidParam){return this.service.read(p,ids.id);}
  @Post(':id/handover/issue') @HttpCode(200) issue(@CurrentUser() p:AuthenticatedPrincipal,@Param() ids:UuidParam,@Body() _:IssueHandoverInput){return this.service.issue(p,ids.id);}
}
