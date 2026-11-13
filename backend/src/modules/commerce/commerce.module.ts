import {Body,Controller,Delete,Get,HttpCode,Inject,Module,Param,Patch,Post,Query,UseGuards} from '@nestjs/common';
import {AuthModule} from '../auth/auth.module';
import {AuthGuard,CurrentUser,Roles,RolesGuard} from '../auth/auth.guards';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {PricingModule} from '../pricing/pricing.module';
import {CartService} from './cart.service';
import {OrdersService} from './orders.service';
import {CommerceStore} from './commerce.store';
import {CartPricingService} from './cart-pricing.service';
import {AddCartInput,AddressInput,OrderPage,PlaceOrderInput,QuantityInput,QuoteCartInput,RestaurantParam,UuidParam,VersionInput} from './commerce.dto';
@Controller('cart') @UseGuards(AuthGuard,RolesGuard) @Roles('CUSTOMER')
class CartController {
  constructor(@Inject(CartService) readonly service:CartService){}
  @Get() get(@CurrentUser() p:AuthenticatedPrincipal){return this.service.get(p);}
  @Post('items') @HttpCode(200) add(@CurrentUser() p:AuthenticatedPrincipal,@Body() input:AddCartInput){return this.service.add(p,input);}
  @Patch('items/:id') change(@CurrentUser() p:AuthenticatedPrincipal,@Param() ids:UuidParam,@Body() input:QuantityInput){return this.service.change(p,ids.id,input);}
  @Delete('items/:id') remove(@CurrentUser() p:AuthenticatedPrincipal,@Param() ids:UuidParam,@Body() input:VersionInput){return this.service.change(p,ids.id,input);}
  @Delete() clear(@CurrentUser() p:AuthenticatedPrincipal,@Body() input:VersionInput){return this.service.change(p,undefined,input);}
  @Post('quote') @HttpCode(200) quote(@CurrentUser() p:AuthenticatedPrincipal,@Body() input:QuoteCartInput){return this.service.quote(p,input);}
}
@Controller('addresses') @UseGuards(AuthGuard,RolesGuard) @Roles('CUSTOMER')
class AddressesController {
  constructor(@Inject(CartService) readonly service:CartService){}
  @Get() list(@CurrentUser() p:AuthenticatedPrincipal){return this.service.addresses(p);}
  @Post() create(@CurrentUser() p:AuthenticatedPrincipal,@Body() input:AddressInput){return this.service.saveAddress(p,input);}
  @Patch(':id') update(@CurrentUser() p:AuthenticatedPrincipal,@Param() ids:UuidParam,@Body() input:AddressInput){return this.service.saveAddress(p,input,ids.id);}
  @Delete(':id') remove(@CurrentUser() p:AuthenticatedPrincipal,@Param() ids:UuidParam){return this.service.deleteAddress(p,ids.id);}
}
@Controller('orders') @UseGuards(AuthGuard,RolesGuard) @Roles('CUSTOMER')
class OrdersController {
  constructor(@Inject(OrdersService) readonly service:OrdersService){}
  @Post() @HttpCode(200) place(@CurrentUser() p:AuthenticatedPrincipal,@Body() input:PlaceOrderInput){return this.service.place(p,input);}
  @Get() list(@CurrentUser() p:AuthenticatedPrincipal,@Query() page:OrderPage){return this.service.list(p,page);}
  @Get(':id') detail(@CurrentUser() p:AuthenticatedPrincipal,@Param() ids:UuidParam){return this.service.detail(p,ids.id);}
}
@Controller('restaurants/:restaurantId/orders') @UseGuards(AuthGuard,RolesGuard) @Roles('RESTAURANT_OWNER')
class InboxController {
  constructor(@Inject(OrdersService) readonly service:OrdersService){}
  @Get() list(@CurrentUser() p:AuthenticatedPrincipal,@Param() ids:RestaurantParam,@Query() page:OrderPage){return this.service.inbox(p,ids.restaurantId,page);}
}
@Module({imports:[AuthModule,PricingModule],controllers:[CartController,AddressesController,OrdersController,InboxController],providers:[CommerceStore,CartService,CartPricingService,OrdersService]})
export class CommerceModule{}
