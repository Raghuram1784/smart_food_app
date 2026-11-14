import { Prisma, DeliveryHandover } from '../../generated/prisma/client';
import { generatePin, handoverConfig, openPin, pinVerifier, sealPin } from './handover.crypto';

/** Order states in which the delivery OTP is live for the customer to read. */
export const HANDOVER_LIVE_STATUSES = ['READY_FOR_PICKUP', 'PICKED_UP', 'OUT_FOR_DELIVERY'] as const;

export type IssueOutcome =
  | { ok: true; handover: DeliveryHandover }
  | { ok: false; status: 409 | 429; message: string };

/**
 * Issue (or re-issue) the secure six-digit delivery OTP for the order's current
 * assignment, inside the caller's transaction. Reuses the F7 crypto unchanged:
 * HMAC verifier + AES-GCM sealed PIN bound to order/assignment/rider/version/expiry,
 * with issuance limits and cooldown. The plaintext PIN is never returned here.
 * Caller must already hold the order row lock.
 */
export async function issueHandoverInTx(
  tx: Prisma.TransactionClient,
  o: { id: string; status: string; assignment: { id: string; riderId: string; status: string } | null },
  actorUserId: string,
  auditAction: 'AUTO_ISSUED' | 'ARRIVAL_REISSUED' | 'ASSIGNMENT_ISSUED',
): Promise<IssueOutcome> {
  const config = handoverConfig();
  const now = new Date();
  const assignment = o.assignment;
  if (!assignment) return { ok: false, status: 409, message: 'Order has no delivery assignment' };
  const rider = await tx.user.findFirst({
    where: { id: assignment.riderId, status: 'ACTIVE', roles: { some: { roleName: 'DELIVERY_PARTNER' } } },
  });
  if (!rider) return { ok: false, status: 409, message: 'Assigned delivery partner is not active' };

  let old = await tx.deliveryHandover.findUnique({ where: { orderId: o.id } });
  if (old?.consumedAt) return { ok: false, status: 409, message: 'Handover already consumed' };
  const rebound = old && (old.assignmentId !== assignment.id || old.boundRiderId !== assignment.riderId);
  if (old && !rebound) {
    if (old.issueCount >= config.maxIssues) {
      return { ok: false, status: 429, message: 'Delivery OTP issuance limit reached; contact support' };
    }
    if (old.nextIssueAt > now) {
      return { ok: false, status: 429, message: 'A new delivery OTP can be issued shortly; wait for the cooldown' };
    }
  }

  let previous: string | undefined;
  if (old?.encryptedPin && old.keyVersion === config.keyVersion) {
    previous = openPin(old.encryptedPin, old, config.encryptionKey);
  }
  let pin = generatePin();
  while (pin === previous) pin = generatePin();
  const binding = {
    orderId: o.id,
    assignmentId: assignment.id,
    boundRiderId: assignment.riderId,
    challengeVersion: (old?.challengeVersion ?? 0) + 1,
    issuedAt: now,
    expiresAt: new Date(now.getTime() + config.ttl * 1000),
    keyVersion: config.keyVersion,
  };
  if (old) {
    await tx.handoverAudit.create({
      data: { handoverId: old.id, challengeVersion: old.challengeVersion, actorUserId, action: rebound ? 'ASSIGNMENT_INVALIDATED' : 'REGENERATED_INVALIDATED' },
    });
  }
  const data = {
    ...binding,
    verifier: pinVerifier(pin, binding, config.verifyKey),
    encryptedPin: sealPin(pin, binding, config.encryptionKey),
    nextIssueAt: new Date(now.getTime() + config.cooldown * 1000),
    // A new assignment starts a fresh issuance budget; otherwise count toward the limit.
    issueCount: rebound ? 1 : (old?.issueCount ?? 0) + 1,
    failedAttempts: 0,
    lastFailedAt: null,
    lockedAt: null,
    lockedUntil: null,
    verifiedAt: null,
    consumedAt: null,
    invalidatedAt: null,
    completionExpectedVersion: null,
    completedOrderVersion: null,
  };
  const handover = old
    ? await tx.deliveryHandover.update({ where: { id: old.id }, data })
    : await tx.deliveryHandover.create({ data });
  await tx.handoverAudit.create({
    data: { handoverId: handover.id, challengeVersion: handover.challengeVersion, actorUserId, action: auditAction },
  });
  // Durable, PIN-free notification: the customer app re-reads the OTP from the
  // authorized customer endpoint. eventType is unique per order, so include the version.
  const event = await tx.orderEvent.create({
    data: {
      orderId: o.id,
      actorUserId,
      eventType: `HANDOVER_ISSUED_${handover.challengeVersion}`,
      previousStatus: o.status as any,
      newStatus: o.status as any,
      metadata: { challengeVersion: handover.challengeVersion, expiresAt: handover.expiresAt.toISOString() },
    },
  });
  await tx.outboxEvent.create({ data: { eventId: event.id } });
  return { ok: true, handover };
}
