import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { map, timeout } from 'rxjs';
@Injectable()
export class ResponseInterceptor implements NestInterceptor {
  intercept(context:ExecutionContext,next:CallHandler){return next.handle().pipe(timeout(8000),map(data=>({data,requestId:context.switchToHttp().getResponse().getHeader('x-request-id')})));}
}
