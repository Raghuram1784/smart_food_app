import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { randomUUID } from 'node:crypto';
import helmet from 'helmet';
import { json, raw, Request, Response, NextFunction } from 'express';
import { AppModule } from './app.module';
import { settings } from './config/settings';
import { ApiExceptionFilter } from './common/filters/api-exception.filter';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
export async function createApp(){
 const config=settings();const app=await NestFactory.create(AppModule,{logger:false,bodyParser:false});
 app.use(helmet());app.use(`/${config.prefix}/payments/razorpay/webhook`,raw({type:'application/json',limit:'128kb'}));app.use(json({limit:'32kb'}));
 app.enableCors({origin:config.origins,methods:['GET','POST','PATCH','DELETE'],credentials:false});
 app.use((req:Request,res:Response,next:NextFunction)=>{
  if(!req.path.startsWith(`/${config.prefix}/catalog`))res.setHeader('Cache-Control','no-store');
  const id=randomUUID();res.setHeader('x-request-id',id);const start=Date.now();
  res.on('finish',()=>console.log(JSON.stringify({level:'info',event:'http_request',requestId:id,method:req.method,status:res.statusCode,durationMs:Date.now()-start})));
  next();
 });
 app.setGlobalPrefix(config.prefix);app.useGlobalPipes(new ValidationPipe({transform:true,whitelist:true,forbidNonWhitelisted:true}));
 app.useGlobalFilters(new ApiExceptionFilter());app.useGlobalInterceptors(new ResponseInterceptor());app.enableShutdownHooks();
 if(!config.production){const document=SwaggerModule.createDocument(app,new DocumentBuilder().addBearerAuth({type:'http',scheme:'bearer',description:'Opaque database session; not JWT'}).setTitle('Food Delivery Catalog').setVersion('1').setDescription('Hyderabad catalog, authoritative pricing, demo authentication, persistent cart/orders and Razorpay TEST payments. Monetary amounts are integer paise. No live-money payments.').build());SwaggerModule.setup(`${config.prefix}/docs`,app,document);}
 return app;
}
if(require.main===module){createApp().then(app=>app.listen(settings().port,'0.0.0.0')).then(()=>console.log(JSON.stringify({event:'api_ready',port:settings().port}))).catch(()=>{console.error('Backend startup failed. Check required configuration, PostgreSQL connectivity and applied migrations.');process.exitCode=1;});}
