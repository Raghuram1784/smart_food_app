import { Controller, Get, Header, HttpCode, Inject, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard, CurrentUser, Roles, RolesGuard } from '../auth/auth.guards';
import { AuthenticatedPrincipal } from '../auth/auth.types';
import { RiderPresenceService } from './rider-presence.service';

/** GPS-free Online/Offline toggle. No location is accepted or stored. */
@ApiTags('Rider Presence')
@ApiBearerAuth()
@Controller('rider/presence')
@UseGuards(AuthGuard, RolesGuard)
@Roles('DELIVERY_PARTNER')
export class RiderPresenceController {
  constructor(@Inject(RiderPresenceService) private readonly service: RiderPresenceService) {}

  @Post('online') @HttpCode(200) @Header('Cache-Control', 'no-store')
  goOnline(@CurrentUser() p: AuthenticatedPrincipal) { return this.service.online(p); }

  @Post('offline') @HttpCode(200) @Header('Cache-Control', 'no-store')
  goOffline(@CurrentUser() p: AuthenticatedPrincipal) { return this.service.offline(p); }

  @Get('me') @Header('Cache-Control', 'no-store')
  getMe(@CurrentUser() p: AuthenticatedPrincipal) { return this.service.me(p); }
}
