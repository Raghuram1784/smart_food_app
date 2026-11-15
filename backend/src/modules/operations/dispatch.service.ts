import {dispatchAllowed} from '../scheduling/schedule.policy';
import { HttpException, Inject, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { DatabaseService } from '../../database/database.module';
import { AuthenticatedPrincipal } from '../auth/auth.types';
import { Prisma } from '../../generated/prisma/client';
import { ACTIVE_ASSIGNMENT_STATUSES } from './assignment-status';
import { issueHandoverInTx } from './handover.issue';
import { eligibleRiderWhere } from './rider-presence.service';

/** How long a single invitation stays acceptable before the rider must refresh. */
export const OFFER_TTL_MS = 5 * 60 * 1000;

/**
 * Invite every currently eligible rider to an order that just became READY_FOR_PICKUP.
 * No distance or GPS is used. Runs inside the caller's transaction (order row locked).
 */
export async function createOffersForOrder(tx: Prisma.TransactionClient, orderId: string, now = new Date()) {
  const order=await tx.order.findUnique({where:{id:orderId}});
  if(!order||order.status!=='READY_FOR_PICKUP'||!dispatchAllowed(order,now)||await tx.deliveryAssignment.findUnique({where:{orderId}}))return 0;
  const riders = await tx.user.findMany({ where: eligibleRiderWhere(now), select: { id: true } });
  for (const r of riders) await offer(tx, orderId, r.id, now);
  return riders.length;
}

/** Create or renew an invitation unless the rider already declined this order. */
async function offer(tx: Prisma.TransactionClient, orderId: string, riderId: string, now: Date) {
  const expiresAt = new Date(now.getTime() + OFFER_TTL_MS);
  // Scheduled release and rider polling can race. The database upsert prevents duplicate
  // invitations; the conditional renewal never reopens an accepted or declined offer.
  await tx.deliveryOffer.upsert({where:{orderId_riderId:{orderId,riderId}},create:{orderId,riderId,expiresAt,offeredAt:now},update:{}});
  await tx.deliveryOffer.updateMany({where:{orderId,riderId,OR:[{status:'CLOSED'},{status:'OFFERED',expiresAt:{lte:now}}]},data:{status:'OFFERED',offeredAt:now,expiresAt,respondedAt:null}});
}

/** Close every other open invitation for an order once it has a rider. */
export async function closeOffersForOrder(tx: Prisma.TransactionClient, orderId: string, exceptOfferId?: string) {
  await tx.deliveryOffer.updateMany({
    where: { orderId, status: 'OFFERED', ...(exceptOfferId ? { id: { not: exceptOfferId } } : {}) },
    data: { status: 'CLOSED', respondedAt: new Date() },
  });
}

const openOrderWhere = ():Prisma.OrderWhereInput => ({status:'READY_FOR_PICKUP',assignment:{is:null},OR:[{deliveryMode:'NOW'},{deliveryMode:'SCHEDULED',dispatchReleaseAt:{lte:new Date()}}]});

@Injectable()
export class DispatchService {
  constructor(@Inject(DatabaseService) private readonly database: DatabaseService) {}

  private async verifyRider(tx: Prisma.TransactionClient, p: AuthenticatedPrincipal) {
    const ok = await tx.authSession.findFirst({
      where: { id: p.sessionId, userId: p.userId, revokedAt: null, expiresAt: { gt: new Date() }, user: { status: 'ACTIVE', roles: { some: { roleName: 'DELIVERY_PARTNER' } } } },
    });
    if (!ok) throw new UnauthorizedException('Delivery partner session is invalid or revoked');
  }

  /**
   * Pending invitations for the caller, read from PostgreSQL. An eligible rider who came
   * online after an order became ready is invited here, so no Socket.IO event is needed.
   */
  offers(p: AuthenticatedPrincipal) {
    return this.database.client.$transaction(async (tx) => {
      await this.verifyRider(tx, p);
      const now = new Date();
      const eligible = await tx.user.findFirst({ where: { id: p.userId, ...eligibleRiderWhere(now) }, select: { id: true } });
      if (eligible) {
        // Newest first so recent orders are never starved by a backlog of stale ones.
        const open = await tx.order.findMany({ where: openOrderWhere(), select: { id: true }, orderBy: { updatedAt: 'desc' }, take: 50 });
        for (const o of open) await offer(tx, o.id, p.userId, now);
      }
      // Busy or offline riders see no invitations (they could not accept them anyway).
      if (!eligible) return { available: false, offers: [] };
      const rows = await tx.deliveryOffer.findMany({
        where: { riderId: p.userId, status: 'OFFERED', expiresAt: { gt: now }, order: openOrderWhere() },
        include: {
          order: {
            select: {
              deliveryMode:true,scheduledDeliveryAt:true,deliveryWindowStart:true,deliveryWindowEnd:true,expectedPickupAt:true, id: true, orderNumber: true, restaurantName: true, finalPayablePaise: true, version: true, createdAt: true, deliveryAddressSnapshot: true,
              restaurant: { select: { name: true, address: true } },
              items: { select: { name: true, quantity: true } },
            },
          },
        },
        orderBy: { offeredAt: 'asc' },
      });
      return {
        available: true,
        offers: rows.map((r) => ({
          id: r.id,
          orderId: r.orderId, deliveryMode:r.order.deliveryMode,scheduledDeliveryAt:r.order.scheduledDeliveryAt,deliveryWindowStart:r.order.deliveryWindowStart,deliveryWindowEnd:r.order.deliveryWindowEnd,expectedPickupAt:r.order.expectedPickupAt,
          expiresAt: r.expiresAt.toISOString(),
          offeredAt: r.offeredAt.toISOString(),
          orderNumber: r.order.orderNumber,
          restaurantName: r.order.restaurant?.name ?? r.order.restaurantName,
          pickupAddress: r.order.restaurant?.address ?? null,
          // Only the delivery area before acceptance; the full address is revealed to the assigned rider.
          dropArea: (r.order.deliveryAddressSnapshot as any)?.localityName ?? null,
          items: r.order.items.map((i) => ({ name: i.name, quantity: i.quantity })),
          itemCount: r.order.items.reduce((n, i) => n + i.quantity, 0),
          orderTotalPaise: r.order.finalPayablePaise,
        })),
      };
    });
  }

  /**
   * Accept an invitation. Concurrency-safe: locks the order row and the rider row, re-checks
   * every rule after the locks, and relies on unique indexes (one assignment per order, one
   * active assignment per rider, one accepted offer per order) as a final backstop. The first
   * valid accept wins; the delivery OTP is issued in the same transaction.
   */
  async accept(p: AuthenticatedPrincipal, offerId: string) {
    const result = await this.database.client.$transaction(async (tx) => {
      await this.verifyRider(tx, p);
      const peek = await tx.deliveryOffer.findUnique({ where: { id: offerId }, select: { orderId: true, riderId: true } });
      if (!peek || peek.riderId !== p.userId) throw new NotFoundException('Delivery invitation not found');
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${peek.orderId}::uuid FOR UPDATE`;
      await tx.$queryRaw`SELECT id FROM "User" WHERE id=${p.userId}::uuid FOR UPDATE`;
      const now = new Date();
      const inv = await tx.deliveryOffer.findUniqueOrThrow({ where: { id: offerId } });
      const order = await tx.order.findUniqueOrThrow({ where: { id: inv.orderId }, include: { assignment: true } });
      if (!dispatchAllowed(order,now))return {error:409,message:'Scheduled dispatch is not due yet'} as const;
      if (order.assignment || order.status !== 'READY_FOR_PICKUP') {
        return { error: 409, message: order.assignment?.riderId === p.userId ? 'You already accepted this delivery' : 'Another delivery partner already accepted this order' } as const;
      }
      if (inv.status !== 'OFFERED') return { error: 409, message: 'This invitation is no longer open' } as const;
      if (inv.expiresAt <= now) return { error: 410, message: 'This invitation expired. Refresh to see current requests.' } as const;
      const busy = await tx.deliveryAssignment.count({ where: { riderId: p.userId, status: { in: ACTIVE_ASSIGNMENT_STATUSES } } });
      if (busy) return { error: 409, message: 'Finish your current delivery before accepting another' } as const;
      const eligible = await tx.user.findFirst({ where: { id: p.userId, ...eligibleRiderWhere(now) }, select: { id: true } });
      if (!eligible) return { error: 409, message: 'Go Online to accept deliveries' } as const;

      const assignment = await tx.deliveryAssignment.create({ data: { orderId: order.id, riderId: p.userId, assignedById: p.userId } });
      await tx.deliveryOffer.update({ where: { id: inv.id }, data: { status: 'ACCEPTED', respondedAt: now } });
      await closeOffersForOrder(tx, order.id, inv.id);
      const version = order.version + 1;
      await tx.order.update({ where: { id: order.id }, data: { version } });
      const event = await tx.orderEvent.create({
        data: { orderId: order.id, actorUserId: p.userId, eventType: 'RIDER_ASSIGNED', previousStatus: order.status, newStatus: order.status, sequence: version, metadata: { via: 'invitation' } },
      });
      await tx.outboxEvent.create({ data: { eventId: event.id } });
      const issued = await issueHandoverInTx(tx, { id: order.id, status: order.status, assignment }, p.userId, 'AUTO_ISSUED');
      if (!issued.ok) throw new HttpException(issued.message, issued.status); // roll back the whole accept
      return { value: { orderId: order.id, assignmentId: assignment.id, orderVersion: version, otpIssued: true } };
    });
    if ('error' in result) throw new HttpException(result.message!, result.error!);
    return result.value;
  }

  decline(p: AuthenticatedPrincipal, offerId: string) {
    return this.database.client.$transaction(async (tx) => {
      await this.verifyRider(tx, p);
      const inv = await tx.deliveryOffer.findUnique({ where: { id: offerId } });
      if (!inv || inv.riderId !== p.userId) throw new NotFoundException('Delivery invitation not found');
      if (inv.status === 'OFFERED') {
        await tx.deliveryOffer.update({ where: { id: inv.id }, data: { status: 'DECLINED', respondedAt: new Date() } });
      }
      return { declined: true };
    });
  }
}
