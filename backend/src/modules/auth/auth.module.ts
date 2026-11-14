import { Body, Controller, Get, Header, HttpCode, Inject, Module, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { PasswordService } from './password.service';
import { SessionService } from './session.service';
import { AuthGuard, CurrentUser, LoginRateGuard, Roles, RolesGuard } from './auth.guards';
import { AuthenticatedPrincipal, SessionVerifier } from './auth.types';
import { LoginInput, ProfileInput } from './auth.dto';
import { IdParams } from '../../common/dto/catalog-query.dto';
@ApiTags('Authentication') @Controller('auth')
class AuthController {
  constructor(@Inject(AuthService) private readonly auth:AuthService,@Inject(SessionService) private readonly sessions:SessionService){}
  @Post('login') @HttpCode(200) @Header('Cache-Control','no-store') @UseGuards(LoginRateGuard)
  login(@Body() input:LoginInput){return this.auth.login(input);}
  @Get('demo-restaurants') @Header('Cache-Control','no-store')
  demoRestaurants(){return this.auth.demoRestaurants();}
  @Get('me') @Header('Cache-Control','no-store') @ApiBearerAuth() @UseGuards(AuthGuard)
  me(@CurrentUser() principal:AuthenticatedPrincipal){return this.auth.me(principal);}
  @Patch('me') @Header('Cache-Control','no-store') @ApiBearerAuth() @UseGuards(AuthGuard)
  update(@CurrentUser() principal:AuthenticatedPrincipal,@Body() input:ProfileInput){return this.auth.update(principal,input);}
  @Post('logout') @HttpCode(200) @Header('Cache-Control','no-store') @ApiBearerAuth() @UseGuards(AuthGuard)
  logout(@CurrentUser() principal:AuthenticatedPrincipal){return this.sessions.revoke(principal);}
  @Post('logout-all') @HttpCode(200) @Header('Cache-Control','no-store') @ApiBearerAuth() @UseGuards(AuthGuard)
  logoutAll(@CurrentUser() principal:AuthenticatedPrincipal){return this.sessions.revoke(principal,true);}
}
@ApiTags('Protected account context') @ApiBearerAuth() @Controller('account') @UseGuards(AuthGuard,RolesGuard)
class AccountController {
  constructor(@Inject(AuthService) private readonly auth:AuthService){}
  @Get('restaurant/:id') @Roles('RESTAURANT_OWNER') @Header('Cache-Control','no-store')
  restaurant(@CurrentUser() principal:AuthenticatedPrincipal,@Param() p:IdParams){return this.auth.restaurant(principal,p.id);}
  @Get('delivery') @Roles('DELIVERY_PARTNER') @Header('Cache-Control','no-store')
  delivery(@CurrentUser() principal:AuthenticatedPrincipal){return {userId:principal.userId,capabilities:['VIEW_OWN_PROFILE'],notice:'Delivery assignments are not implemented yet.'};}
  @Get('admin') @Roles('ADMIN') @Header('Cache-Control','no-store')
  admin(@CurrentUser() principal:AuthenticatedPrincipal){return {userId:principal.userId,capabilities:['VIEW_ADMIN_CONTEXT'],notice:'Role and membership administration will be added in a later phase.'};}
}
@Module({controllers:[AuthController,AccountController],providers:[AuthService,PasswordService,SessionService,{provide:SessionVerifier,useExisting:SessionService},AuthGuard,RolesGuard,LoginRateGuard],exports:[AuthGuard,RolesGuard,SessionVerifier]})
export class AuthModule {}
