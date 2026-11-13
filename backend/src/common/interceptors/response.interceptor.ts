
import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';

import { map, timeout } from 'rxjs';

export const REQUEST_TIMEOUT_KEY = 'http.requestTimeoutMs';

@Injectable()
export class ResponseInterceptor implements NestInterceptor {
  intercept(
    context: ExecutionContext,
    next: CallHandler,
  ) {
    const configured = Reflect.getMetadata(
      REQUEST_TIMEOUT_KEY,
      context.getHandler(),
    );

    const timeoutMs =
      typeof configured === 'number' &&
      Number.isInteger(configured) &&
      configured >= 1000 &&
      configured <= 30000
        ? configured
        : 8000;

    return next.handle().pipe(
      timeout(timeoutMs),
      map(data => ({
        data,
        requestId: context
          .switchToHttp()
          .getResponse()
          .getHeader('x-request-id'),
      })),
    );
  }
}
