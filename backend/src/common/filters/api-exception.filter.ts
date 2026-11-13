import { ArgumentsHost, Catch, ExceptionFilter, HttpException } from '@nestjs/common';
import { Request, Response } from 'express';
@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  catch(error:unknown,host:ArgumentsHost){
    const http=host.switchToHttp(),response=http.getResponse<Response>(),request=http.getRequest<Request>();
    let status=503,message:unknown='Service temporarily unavailable';
    if(error instanceof HttpException){status=error.getStatus();const body=error.getResponse();message=typeof body==='string'?body:(body as {message?:unknown}).message??error.message;}
    response.status(status).json({error:{code:status===401?'UNAUTHENTICATED':status===403?'FORBIDDEN':status===429?'RATE_LIMITED':status===404?'NOT_FOUND':status===400?'INVALID_REQUEST':status===503?'SERVICE_UNAVAILABLE':'REQUEST_FAILED',message},requestId:response.getHeader('x-request-id')});
  }
}
