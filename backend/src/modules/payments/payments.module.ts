import {Body,Controller,Get,Headers,HttpCode,Inject,Module,Param,Post,Req,UseGuards} from '@nestjs/common';
import {Request} from 'express';
import {AuthModule} from '../auth/auth.module';
import {AuthGuard,CurrentUser,Roles,RolesGuard} from '../auth/auth.guards';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {CommerceStore} from '../commerce/commerce.store';
import {UuidParam} from '../commerce/commerce.dto';
import {PaymentsService} from './payments.service';
import {PaymentProvider,RazorpayProvider,paymentMethods} from './razorpay.provider';
import {PaymentOrderInput,PaymentVerifyInput} from './payments.dto';
@Controller('payments') @UseGuards(AuthGuard,RolesGuard) @Roles('CUSTOMER')
class PaymentsController {
  constructor(@Inject(PaymentsService) readonly service:PaymentsService){}
  @Get('methods') methods(){return paymentMethods();}
  @Post('razorpay/create-order') @HttpCode(200) create(@CurrentUser() p:AuthenticatedPrincipal,@Body() input:PaymentOrderInput){return this.service.create(p,input.orderId);}
  @Post('razorpay/verify') @HttpCode(200) verify(@CurrentUser() p:AuthenticatedPrincipal,@Body() input:PaymentVerifyInput){return this.service.verify(p,input);}
  @Get('orders/:id/status') status(@CurrentUser() p:AuthenticatedPrincipal,@Param() ids:UuidParam){return this.service.status(p,ids.id);}
}
@Controller('payments/razorpay')
class WebhookController {
  constructor(@Inject(PaymentsService) readonly service:PaymentsService){}
  @Post('webhook') @HttpCode(200) receive(@Req() req:Request,@Headers('x-razorpay-signature') signature:string,@Headers('x-razorpay-event-id') eventId:string){return this.service.webhook(req.body,signature??'',eventId??'');}
}
@Module({imports:[AuthModule],controllers:[PaymentsController,WebhookController],providers:[CommerceStore,PaymentsService,{provide:PaymentProvider,useClass:RazorpayProvider}]})
export class PaymentsModule{}
