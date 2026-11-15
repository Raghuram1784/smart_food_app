import { CallHandler, ExecutionContext, Injectable, NestInterceptor, SetMetadata } from '@nestjs/common';
import { map, timeout } from 'rxjs';

/** Per-route override of the default 8 s request timeout (used by the AI finder, which may call Gemini). */
export const REQUEST_TIMEOUT_KEY = 'request.timeoutMs';
export const RequestTimeout = (ms: number) => SetMetadata(REQUEST_TIMEOUT_KEY, ms);

@Injectable()
export class ResponseInterceptor implements NestInterceptor {
  intercept(context:ExecutionContext,next:CallHandler){
    const ms=Number(Reflect.getMetadata(REQUEST_TIMEOUT_KEY,context.getHandler())??8000);
    return next.handle().pipe(timeout(ms),map(data=>({data,requestId:context.switchToHttp().getResponse().getHeader('x-request-id')})));
  }
}
