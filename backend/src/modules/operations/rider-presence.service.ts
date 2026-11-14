import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { DatabaseService } from '../../database/database.module';
import { AuthenticatedPrincipal } from '../auth/auth.types';
import { Prisma } from '../../generated/prisma/client';
import { ACTIVE_ASSIGNMENT_STATUSES } from './assignment-status';

/**
 * Rider availability without GPS.
 *
 * A rider is eligible for delivery invitations when: the account is ACTIVE with the
 * DELIVERY_PARTNER role, it has at least one live (unrevoked, unexpired) session, the
 * rider switched Online, and the rider has no active delivery. Location is never
 * required or collected. Legacy latitude/longitude columns are left untouched.
 */
@Injectable()
export class RiderPresenceService {
  constructor(@Inject(DatabaseService) private readonly database: DatabaseService) {}

  online(p: AuthenticatedPrincipal) {
    return this.database.client.$transaction(async (tx) => {
      await this.verifyRiderSession(tx, p);
      await tx.riderPresence.upsert({
        where: { userId: p.userId },
        update: { isOnline: true, lastOnlineAt: new Date() },
        create: { userId: p.userId, isOnline: true, lastOnlineAt: new Date() },
      });
      return this.state(tx, p.userId);
    });
  }

  offline(p: AuthenticatedPrincipal) {
    return this.database.client.$transaction(async (tx) => {
      await this.verifyRiderSession(tx, p);
      await tx.riderPresence.upsert({
        where: { userId: p.userId },
        update: { isOnline: false, lastOfflineAt: new Date() },
        create: { userId: p.userId, isOnline: false, lastOfflineAt: new Date() },
      });
      // Going offline immediately withdraws this rider's open invitations.
      await tx.deliveryOffer.updateMany({
        where: { riderId: p.userId, status: 'OFFERED' },
        data: { status: 'CLOSED', respondedAt: new Date() },
      });
      return this.state(tx, p.userId);
    });
  }

  me(p: AuthenticatedPrincipal) {
    return this.database.client.$transaction(async (tx) => {
      await this.verifyRiderSession(tx, p);
      return this.state(tx, p.userId);
    });
  }

  private async verifyRiderSession(tx: Prisma.TransactionClient, p: AuthenticatedPrincipal) {
    const session = await tx.authSession.findFirst({
      where: {
        id: p.sessionId,
        userId: p.userId,
        revokedAt: null,
        expiresAt: { gt: new Date() },
        user: { status: 'ACTIVE', roles: { some: { roleName: 'DELIVERY_PARTNER' } } },
      },
    });
    if (!session) throw new UnauthorizedException('Delivery partner session is invalid or revoked');
  }

  async state(tx: Prisma.TransactionClient, userId: string) {
    const presence = await tx.riderPresence.findUnique({ where: { userId } });
    const activeAssignment = await tx.deliveryAssignment.findFirst({
      where: { riderId: userId, status: { in: ACTIVE_ASSIGNMENT_STATUSES } },
      select: { id: true, orderId: true, status: true, assignedAt: true },
    });
    const isOnline = presence?.isOnline ?? false;
    return {
      userId,
      isOnline,
      isAvailable: isOnline && !activeAssignment,
      lastOnlineAt: presence?.lastOnlineAt?.toISOString() ?? null,
      lastOfflineAt: presence?.lastOfflineAt?.toISOString() ?? null,
      activeAssignment: activeAssignment
        ? { ...activeAssignment, assignedAt: activeAssignment.assignedAt.toISOString() }
        : null,
    };
  }
}

/** Where-clause for riders who may receive new delivery invitations. */
export function eligibleRiderWhere(now = new Date()): Prisma.UserWhereInput {
  return {
    status: 'ACTIVE',
    roles: { some: { roleName: 'DELIVERY_PARTNER' } },
    riderPresence: { is: { isOnline: true } },
    sessions: { some: { revokedAt: null, expiresAt: { gt: now } } },
    riderAssignments: { none: { status: { in: ACTIVE_ASSIGNMENT_STATUSES } } },
  };
}
