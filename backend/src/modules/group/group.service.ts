/**
 * F2 group ordering and restaurant price negotiation.
 *
 * Source of truth is PostgreSQL. Every mutation runs in a Serializable transaction that locks the
 * GroupOrder row and checks the caller's expected version/cart revision (optimistic concurrency).
 * Prices always come from the existing CartPricingService (same engine as personal checkout). A
 * negotiated reduction is stored explicitly (Order.negotiatedDiscountPaise, inside discountPaise);
 * menu prices, fees and tax are never altered. Sockets only nudge clients to refetch.
 */
import { ConflictException, ForbiddenException, GoneException, HttpException, Inject, Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { createHash, randomBytes, randomInt } from 'node:crypto';
import { DatabaseService } from '../../database/database.module';
import { Prisma } from '../../generated/prisma/client';
import type { AuthenticatedPrincipal } from '../auth/auth.types';
import { CartPricingService, digest } from '../commerce/cart-pricing.service';
import { orderInclude } from '../commerce/commerce.store';
import { evaluateServiceability, serviceabilitySelect } from '../commerce/serviceability';
import { queueEvent } from '../operations/operations.service';
import { OrderGateway } from '../operations/realtime';
import { PricingService } from '../pricing/pricing.service';
import { itemInclude } from '../catalog/catalog.mapper';
import { familySimilarity } from '../food-finder/food-taxonomy';
import { calculate } from '../pricing/pricing.calculator';

type Tx = Prisma.TransactionClient;
const sha = (s: string) => createHash('sha256').update(s).digest('hex');
const json = (v: unknown) => JSON.parse(JSON.stringify(v)) as Prisma.InputJsonValue;

export const GROUP_RULES = {
  maxMembers: 12,
  maxOpenGroupsPerOrganizer: 3,
  defaultLifetimeMinutes: 120,
  restaurantResponseMinutes: 15,
  acceptedOfferMinutes: 30,
  counterResponseMinutes: 15,
  maxProposalsPerGroup: 5,
  maxProposalsPerRestaurant: 3,
  joinAttemptsPerMinute: 10,
};
const LIVE_PROPOSAL = ['PENDING', 'COUNTERED', 'ACCEPTED'] as const;
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no 0/O/1/I/L

export const groupInclude = {
  restaurant: { select: { id: true, name: true, imageKey: true, operatingStatus: true, deliveryAvailability: true, groupNegotiationEnabled: true, maxGroupDiscountBps: true, locality: { select: { name: true } } } },
  members: { orderBy: { joinedAt: 'asc' as const } },
  items: { orderBy: { createdAt: 'asc' as const }, include: { menuItem: { select: { id: true, name: true, imageKey: true, isVegetarian: true, availabilityStatus: true } } } },
  proposals: { orderBy: { createdAt: 'desc' as const } },
} satisfies Prisma.GroupOrderInclude;
type LoadedGroup = Prisma.GroupOrderGetPayload<{ include: typeof groupInclude }>;

export function normalizeJoinCode(code: string) { return code.toUpperCase().replace(/[^A-Z0-9]/g, ''); }

@Injectable()
export class GroupService {
  private readonly joinAttempts = new Map<string, number[]>();
  constructor(
    @Inject(DatabaseService) private readonly database: DatabaseService,
    @Inject(CartPricingService) private readonly cartPricing: CartPricingService,
    @Inject(PricingService) private readonly pricing: PricingService,
    @Inject(OrderGateway) private readonly gateway: OrderGateway,
  ) {}

  // ---------------------------------------------------------------- infrastructure
  private async run<T>(p: AuthenticatedPrincipal, role: 'CUSTOMER' | 'RESTAURANT_OWNER', work: (tx: Tx) => Promise<T>): Promise<T> {
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        return await this.database.client.$transaction(async (tx) => {
          const session = await tx.authSession.findFirst({ where: { id: p.sessionId, userId: p.userId, revokedAt: null, expiresAt: { gt: new Date() }, user: { status: 'ACTIVE', roles: { some: { roleName: role } } } } });
          if (!session) throw new ForbiddenException('Session is no longer active');
          return work(tx);
        }, { isolationLevel: 'Serializable', timeout: 20000 });
      } catch (e) {
        // P2034 = Prisma write conflict; 40001 surfaces from the raw FOR UPDATE as P2010 under Serializable.
        const err = e as { code?: string; meta?: { code?: string }; message?: string };
        const retryable = err.code === 'P2034' || (err.code === 'P2010' && (err.meta?.code === '40001' || /could not serialize|40001/.test(err.message ?? '')));
        if (!retryable) throw e;
        if (attempt === 3) throw new ConflictException('Someone else just changed this group. Refresh and try again.');
      }
    }
    throw new ConflictException('Please retry');
  }

  private async lockGroup(tx: Tx, id: string) {
    await tx.$queryRaw`SELECT id FROM "GroupOrder" WHERE id = ${id}::uuid FOR UPDATE`;
    const g = await tx.groupOrder.findUnique({ where: { id }, include: groupInclude });
    if (!g) throw new NotFoundException('Group not found');
    return this.applyExpiry(tx, g);
  }

  private member(g: LoadedGroup, userId: string) {
    const m = g.members.find((x) => x.userId === userId && x.status === 'ACTIVE');
    if (!m) throw new NotFoundException('Group not found'); // never reveal groups to non-members
    return m;
  }
  private organizer(g: LoadedGroup, userId: string) {
    this.member(g, userId);
    if (g.organizerId !== userId) throw new ForbiddenException('Only the organizer can do this');
  }
  private version(g: LoadedGroup, expected: number | undefined, field: 'version' | 'cartRevision' = 'version') {
    if (expected !== undefined && g[field] !== expected) throw new ConflictException('This group changed. Refresh and try again.');
  }
  private status(g: LoadedGroup, allowed: string[], message: string) {
    if (!allowed.includes(g.status)) throw new ConflictException(message);
  }

  /** Lazily applies group/proposal/offer expiry (persisted; called inside the locked transaction). */
  private async applyExpiry(tx: Tx, g: LoadedGroup): Promise<LoadedGroup> {
    const now = new Date();
    let changed = false;
    const live = g.proposals.find((p) => (LIVE_PROPOSAL as readonly string[]).includes(p.status));
    if (live) {
      const deadline = live.status === 'PENDING' ? live.responseExpiresAt : live.offerExpiresAt;
      if (deadline && deadline <= now) {
        await tx.groupProposal.update({ where: { id: live.id }, data: { status: 'EXPIRED' } });
        await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'LOCKED', version: { increment: 1 } } });
        changed = true;
      }
    }
    if (g.expiresAt <= now && ['OPEN', 'LOCKED', 'PROPOSED', 'COUNTERED', 'REJECTED'].includes(g.status)) {
      if (live && !changed) await tx.groupProposal.update({ where: { id: live.id }, data: { status: 'EXPIRED' } });
      await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'EXPIRED', version: { increment: 1 } } });
      changed = true;
    }
    return changed ? tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude }) : g;
  }

  /** Authoritative normal price of the group cart (existing cart pricing engine, organizer's address). */
  private async quote(tx: Tx, g: LoadedGroup) {
    if (!g.items.length) throw new UnprocessableEntityException('Add some food before asking for a price');
    const cart = {
      id: g.id, customerId: g.organizerId, restaurantId: g.restaurantId, version: g.cartRevision,
      restaurant: { id: g.restaurant.id, name: g.restaurant.name, imageKey: g.restaurant.imageKey },
      items: g.items.map((i) => ({ id: i.id, menuItemId: i.menuItemId, quantity: i.quantity, variantId: i.variantId, addOns: i.addOnIds.map((addOnId) => ({ addOnId })) })),
    };
    return this.cartPricing.calculate(tx, cart as any, g.addressId);
  }

  private notify(g: { id: string; restaurantId: string }, memberIds: string[], event: string, restaurant = false) {
    const rooms = memberIds.map((u) => 'customer:' + u);
    // Fire after the transaction commits; content-free, clients refetch with their own session.
    setImmediate(() => {
      this.gateway.notify(rooms, 'group.updated', { groupId: g.id, event });
      if (restaurant) this.gateway.notify(['restaurant:' + g.restaurantId], 'group.proposals', { groupId: g.id, event });
    });
  }
  private activeIds(g: LoadedGroup) { return g.members.filter((m) => m.status === 'ACTIVE').map((m) => m.userId); }

  // ---------------------------------------------------------------- presentation
  private async present(tx: Tx, g: LoadedGroup, viewerId: string) {
    const lines = new Map<string, { lineTotalPaise: number; variant: any; addOns: any[] }>();
    let pricing: any = null, pricingError: string | null = null;
    if (g.items.length && !['ORDERED', 'CANCELED'].includes(g.status)) {
      try {
        const q = await this.quote(tx, g);
        q.lines.forEach((l: any) => lines.set(l.id, l));
        pricing = { itemSubtotalPaise: q.basePaise, customizationTotalPaise: q.variantPaise + q.addOnPaise, packagingPaise: q.packagingPaise, deliveryPaise: q.deliveryPaise,
          platformPaise: q.platformPaise, discountPaise: q.discountPaise, taxPaise: q.taxPaise, normalTotalPaise: q.finalPayablePaise };
      } catch (e) { pricingError = e instanceof HttpException ? (e.getResponse() as any)?.message ?? e.message : 'Price unavailable right now'; }
    }
    const names = new Map(g.members.map((m) => [m.userId, m.displayName]));
    const items = g.items.map((i) => {
      const l = lines.get(i.id);
      return { id: i.id, memberId: i.memberId, memberName: names.get(i.memberId) ?? 'Member', mine: i.memberId === viewerId, menuItemId: i.menuItemId, name: i.menuItem.name,
        imageKey: i.menuItem.imageKey, isVegetarian: i.menuItem.isVegetarian, available: i.menuItem.availabilityStatus === 'AVAILABLE', quantity: i.quantity, version: i.version,
        variant: l?.variant ?? null, addOns: l?.addOns ?? [], lineTotalPaise: l?.lineTotalPaise ?? i.unitPricePaise * i.quantity };
    });
    const contributions = g.members.filter((m) => m.status === 'ACTIVE').map((m) => ({ userId: m.userId, name: m.displayName,
      itemCount: items.filter((i) => i.memberId === m.userId).reduce((n, i) => n + i.quantity, 0),
      itemTotalPaise: items.filter((i) => i.memberId === m.userId).reduce((n, i) => n + i.lineTotalPaise, 0) }));
    const isOrganizer = g.organizerId === viewerId;
    const live = g.proposals.find((p) => (LIVE_PROPOSAL as readonly string[]).includes(p.status));
    const latest = g.proposals[0] ?? null;
    const showProposal = (p: (typeof g.proposals)[number]) => ({
      id: p.id, restaurantId: p.restaurantId, status: p.status, cartRevision: p.cartRevision, normalTotalPaise: p.normalTotalPaise, proposedTotalPaise: p.proposedTotalPaise,
      requestedReductionPaise: p.normalTotalPaise - p.proposedTotalPaise, counterTotalPaise: p.counterTotalPaise, agreedTotalPaise: p.agreedTotalPaise,
      minAllowedTotalPaise: p.minAllowedTotalPaise, responseExpiresAt: p.responseExpiresAt, offerExpiresAt: p.offerExpiresAt, responseNote: p.responseNote, createdAt: p.createdAt,
      breakdown: { itemSubtotalPaise: p.itemSubtotalPaise, customizationTotalPaise: p.customizationTotalPaise, packagingPaise: p.packagingPaise, deliveryPaise: p.deliveryPaise, platformPaise: p.platformPaise, discountPaise: p.discountPaise, taxPaise: p.taxPaise },
    });
    const restaurantName = g.restaurant.name;
    return {
      id: g.id, name: g.name, status: g.status, version: g.version, cartRevision: g.cartRevision, expiresAt: g.expiresAt, orderId: g.orderId,
      restaurant: { id: g.restaurant.id, name: restaurantName, imageKey: g.restaurant.imageKey, locality: g.restaurant.locality?.name ?? null, open: g.restaurant.operatingStatus === 'OPEN' && g.restaurant.deliveryAvailability, negotiationEnabled: g.restaurant.groupNegotiationEnabled },
      organizerId: g.organizerId, isOrganizer,
      members: g.members.filter((m) => m.status === 'ACTIVE').map((m) => ({ userId: m.userId, name: m.displayName, isOrganizer: m.isOrganizer, isYou: m.userId === viewerId })),
      items, contributions, pricing, pricingError,
      memberCount: contributions.length,
      proposal: live ? showProposal(live) : latest ? showProposal(latest) : null,
      proposalAttempts: g.proposalAttempts, maxProposals: GROUP_RULES.maxProposalsPerGroup,
      negotiationRange: pricing ? { maxDiscountBps: g.restaurant.maxGroupDiscountBps, minAllowedTotalPaise: this.minAllowed(pricing.normalTotalPaise, g.restaurant.maxGroupDiscountBps) } : null,
      permissions: {
        canEditOwnItems: g.status === 'OPEN', canLock: isOrganizer && g.status === 'OPEN' && g.items.length > 0, canUnlock: isOrganizer && ['LOCKED', 'REJECTED'].includes(g.status),
        canPropose: isOrganizer && ['LOCKED', 'REJECTED'].includes(g.status) && g.proposalAttempts < GROUP_RULES.maxProposalsPerGroup,
        canRespondToCounter: isOrganizer && g.status === 'COUNTERED', canCheckout: isOrganizer && g.status === 'ACCEPTED', canLeave: !isOrganizer && ['OPEN', 'LOCKED'].includes(g.status),
        canCancel: isOrganizer && !['ORDERED', 'CANCELED', 'EXPIRED'].includes(g.status), canInvite: isOrganizer && g.status === 'OPEN',
      },
      paymentNote: 'The organizer pays the final order total. Individual amounts are for information only.',
    };
  }

  private minAllowed(normal: number, bps: number) { return Math.ceil((normal * (10000 - bps)) / 10000); }

  // ---------------------------------------------------------------- customer: lifecycle
  private newInvite() {
    const token = randomBytes(32).toString('base64url');
    const code = Array.from({ length: 8 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join('');
    return { token, code, tokenHash: sha('t:' + token), codeHash: sha('c:' + code) };
  }
  private invitePayload(groupId: string, inv: { token: string; code: string }) {
    const base = process.env.APP_LINK_BASE?.trim().replace(/\/+$/, '');
    return { groupId, inviteToken: inv.token, joinCode: `${inv.code.slice(0, 4)}-${inv.code.slice(4)}`, inviteUrl: base ? `${base}/group/${inv.token}` : null };
  }

  async create(p: AuthenticatedPrincipal, input: { restaurantId: string; addressId: string; name?: string; lifetimeMinutes?: number }) {
    const inv = this.newInvite();
    const result = await this.run(p, 'CUSTOMER', async (tx) => {
      const open = await tx.groupOrder.count({ where: { organizerId: p.userId, status: { in: ['OPEN', 'LOCKED', 'PROPOSED', 'COUNTERED', 'ACCEPTED', 'REJECTED'] }, expiresAt: { gt: new Date() } } });
      if (open >= GROUP_RULES.maxOpenGroupsPerOrganizer) throw new ConflictException(`You already have ${open} active group orders. Finish or cancel one first.`);
      const address = await tx.customerAddress.findFirst({ where: { id: input.addressId, customerId: p.userId } });
      if (!address) throw new NotFoundException('Delivery address not found');
      if (!address.localityId) throw new UnprocessableEntityException('Choose an address inside a delivery area');
      const restaurant = await tx.restaurant.findUnique({ where: { id: input.restaurantId }, select: { ...serviceabilitySelect, groupNegotiationEnabled: true } });
      if (!restaurant) throw new NotFoundException('Restaurant not found');
      if (!restaurant.groupNegotiationEnabled) throw new UnprocessableEntityException('This restaurant is not taking group orders');
      const s = evaluateServiceability(restaurant as any, address);
      if (!s.eligible) throw new UnprocessableEntityException(s.reason);
      const user = await tx.user.findUniqueOrThrow({ where: { id: p.userId }, select: { displayName: true } });
      const minutes = Math.min(240, Math.max(30, input.lifetimeMinutes ?? GROUP_RULES.defaultLifetimeMinutes));
      const g = await tx.groupOrder.create({ data: {
        organizerId: p.userId, restaurantId: input.restaurantId, addressId: address.id, localityId: address.localityId, name: input.name?.trim() || null,
        inviteTokenHash: inv.tokenHash, joinCodeHash: inv.codeHash, expiresAt: new Date(Date.now() + minutes * 60_000),
        members: { create: { userId: p.userId, displayName: user.displayName.slice(0, 80), isOrganizer: true } },
      }, include: groupInclude });
      return { invite: this.invitePayload(g.id, inv), group: await this.present(tx, g, p.userId) };
    });
    return result;
  }

  async rotateInvite(p: AuthenticatedPrincipal, id: string) {
    const inv = this.newInvite();
    return this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.organizer(g, p.userId);
      this.status(g, ['OPEN'], 'Invites can only be shared while the group is open');
      await tx.groupOrder.update({ where: { id }, data: { inviteTokenHash: inv.tokenHash, joinCodeHash: inv.codeHash } });
      return this.invitePayload(id, inv);
    });
  }

  private limitJoin(userId: string) {
    const now = Date.now();
    const times = (this.joinAttempts.get(userId) ?? []).filter((t) => t > now - 60_000);
    if (times.length >= GROUP_RULES.joinAttemptsPerMinute) throw new HttpException('Too many join attempts. Wait a minute and try again.', 429);
    times.push(now); this.joinAttempts.set(userId, times);
  }

  async join(p: AuthenticatedPrincipal, input: { token?: string; code?: string }) {
    this.limitJoin(p.userId);
    const hash = input.token ? sha('t:' + input.token.trim()) : input.code ? sha('c:' + normalizeJoinCode(input.code)) : null;
    if (!hash) throw new UnprocessableEntityException('Enter an invite code');
    const out = await this.run(p, 'CUSTOMER', async (tx) => {
      const found = await tx.groupOrder.findFirst({ where: input.token ? { inviteTokenHash: hash } : { joinCodeHash: hash }, select: { id: true } });
      if (!found) throw new NotFoundException('This invite is not valid');
      const g = await this.lockGroup(tx, found.id);
      const existing = g.members.find((m) => m.userId === p.userId);
      if (existing?.status === 'ACTIVE') return { g, joined: false };
      if (g.status === 'EXPIRED' || g.expiresAt <= new Date()) throw new GoneException('This invite has expired');
      this.status(g, ['OPEN'], 'This group is no longer accepting new members');
      if (g.members.filter((m) => m.status === 'ACTIVE').length >= GROUP_RULES.maxMembers) throw new ConflictException('This group is full');
      const user = await tx.user.findUniqueOrThrow({ where: { id: p.userId }, select: { displayName: true } });
      if (existing) await tx.groupMember.update({ where: { groupId_userId: { groupId: g.id, userId: p.userId } }, data: { status: 'ACTIVE' } });
      else await tx.groupMember.create({ data: { groupId: g.id, userId: p.userId, displayName: user.displayName.slice(0, 80) } });
      await tx.groupOrder.update({ where: { id: g.id }, data: { version: { increment: 1 } } });
      return { g: await tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude }), joined: true };
    });
    if (out.joined) this.notify(out.g, this.activeIds(out.g), 'MEMBER_JOINED');
    return this.get(p, out.g.id);
  }

  async mine(p: AuthenticatedPrincipal) {
    const groups = await this.database.client.groupOrder.findMany({
      where: { members: { some: { userId: p.userId, status: 'ACTIVE' } }, status: { notIn: ['CANCELED'] } },
      orderBy: { createdAt: 'desc' }, take: 20, include: { restaurant: { select: { name: true } }, members: { where: { status: 'ACTIVE' }, select: { userId: true } } },
    });
    return groups.map((g) => ({ id: g.id, name: g.name, status: g.expiresAt <= new Date() && !['ORDERED', 'CANCELED'].includes(g.status) ? 'EXPIRED' : g.status, restaurantName: g.restaurant.name, memberCount: g.members.length, isOrganizer: g.organizerId === p.userId, expiresAt: g.expiresAt, orderId: g.orderId }));
  }

  async get(p: AuthenticatedPrincipal, id: string) {
    return this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.member(g, p.userId);
      return this.present(tx, g, p.userId);
    });
  }

  // ---------------------------------------------------------------- customer: shared cart
  async addItem(p: AuthenticatedPrincipal, id: string, input: { menuItemId: string; quantity: number; variantId?: string; addOnIds: string[]; expectedRevision: number }) {
    const g = await this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.member(g, p.userId);
      this.status(g, ['OPEN'], 'The group is locked. Ask the organizer to reopen it to change food.');
      this.version(g, input.expectedRevision, 'cartRevision');
      const item = await tx.menuItem.findUnique({ where: { id: input.menuItemId }, include: itemInclude });
      if (!item || item.restaurantId !== g.restaurantId) throw new UnprocessableEntityException('This dish is not on the group restaurant\'s menu');
      // Existing selection validation: availability, variant and add-on compatibility (zone checked by quote).
      const sel = this.pricing.selection(item, { restaurantId: g.restaurantId, menuItemId: item.id, area: g.localityId, quantity: input.quantity, variantId: input.variantId, addOnIds: input.addOnIds }, { skipZone: true });
      const addOnIds = [...new Set(input.addOnIds)].sort();
      const key = digest({ menuItemId: item.id, variantId: sel.variant?.id ?? null, addOnIds });
      const unit = item.basePricePaise + (sel.variant?.priceAdjustmentPaise ?? 0) + sel.addOns.reduce((n, a) => n + a.pricePaise, 0);
      const existing = await tx.groupCartItem.findUnique({ where: { groupId_memberId_selectionKey: { groupId: g.id, memberId: p.userId, selectionKey: key } } });
      const quantity = Math.min(20, (existing?.quantity ?? 0) + input.quantity);
      if (existing) await tx.groupCartItem.update({ where: { id: existing.id }, data: { quantity, unitPricePaise: unit, version: { increment: 1 } } });
      else await tx.groupCartItem.create({ data: { groupId: g.id, memberId: p.userId, restaurantId: g.restaurantId, menuItemId: item.id, variantId: sel.variant?.id ?? null, addOnIds, selectionKey: key, quantity, unitPricePaise: unit } });
      await tx.groupOrder.update({ where: { id: g.id }, data: { cartRevision: { increment: 1 }, version: { increment: 1 } } });
      return tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude });
    });
    this.notify(g, this.activeIds(g), 'ITEM_ADDED');
    return this.get(p, id);
  }

  async updateItem(p: AuthenticatedPrincipal, id: string, itemId: string, input: { quantity: number; expectedRevision: number }) {
    return this.mutateOwnItem(p, id, itemId, input.expectedRevision, (tx) => tx.groupCartItem.update({ where: { id: itemId }, data: { quantity: input.quantity, version: { increment: 1 } } }), 'ITEM_UPDATED');
  }
  async removeItem(p: AuthenticatedPrincipal, id: string, itemId: string, expectedRevision: number) {
    return this.mutateOwnItem(p, id, itemId, expectedRevision, (tx) => tx.groupCartItem.delete({ where: { id: itemId } }), 'ITEM_REMOVED');
  }
  private async mutateOwnItem(p: AuthenticatedPrincipal, id: string, itemId: string, expectedRevision: number, change: (tx: Tx) => Promise<unknown>, event: string) {
    const g = await this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.member(g, p.userId);
      this.status(g, ['OPEN'], 'The group is locked. Ask the organizer to reopen it to change food.');
      this.version(g, expectedRevision, 'cartRevision');
      const item = g.items.find((i) => i.id === itemId);
      if (!item) throw new NotFoundException('Item not found in this group');
      if (item.memberId !== p.userId) throw new ForbiddenException('You can only change your own selections');
      await change(tx);
      await tx.groupOrder.update({ where: { id: g.id }, data: { cartRevision: { increment: 1 }, version: { increment: 1 } } });
      return tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude });
    });
    this.notify(g, this.activeIds(g), event);
    return this.get(p, id);
  }

  async leave(p: AuthenticatedPrincipal, id: string) {
    const g = await this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.member(g, p.userId);
      if (g.organizerId === p.userId) throw new ConflictException('The organizer cannot leave. Cancel the group instead.');
      this.status(g, ['OPEN', 'LOCKED'], 'You can no longer leave this group because a price request is in progress');
      const mine = g.items.filter((i) => i.memberId === p.userId).length;
      await tx.groupCartItem.deleteMany({ where: { groupId: g.id, memberId: p.userId } });
      await tx.groupMember.update({ where: { groupId_userId: { groupId: g.id, userId: p.userId } }, data: { status: 'LEFT' } });
      await tx.groupOrder.update({ where: { id: g.id }, data: { version: { increment: 1 }, ...(mine ? { cartRevision: { increment: 1 } } : {}) } });
      return tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude });
    });
    this.notify(g, [...this.activeIds(g), p.userId], 'MEMBER_LEFT');
    return { left: true };
  }

  async lock(p: AuthenticatedPrincipal, id: string, expectedVersion: number) {
    return this.organizerTransition(p, id, expectedVersion, ['OPEN'], 'The group is not open', async (tx, g) => {
      if (!g.items.length) throw new UnprocessableEntityException('Add some food before locking the group');
      await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'LOCKED', version: { increment: 1 } } });
    }, 'GROUP_LOCKED');
  }

  async unlock(p: AuthenticatedPrincipal, id: string, expectedVersion: number) {
    return this.organizerTransition(p, id, expectedVersion, ['LOCKED', 'REJECTED'], 'The group cannot be reopened now', async (tx, g) => {
      await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'OPEN', version: { increment: 1 } } });
    }, 'GROUP_UNLOCKED');
  }

  async cancel(p: AuthenticatedPrincipal, id: string, expectedVersion: number) {
    return this.organizerTransition(p, id, expectedVersion, ['OPEN', 'LOCKED', 'PROPOSED', 'COUNTERED', 'ACCEPTED', 'REJECTED'], 'This group can no longer be canceled', async (tx, g) => {
      await tx.groupProposal.updateMany({ where: { groupId: g.id, status: { in: ['PENDING', 'COUNTERED', 'ACCEPTED'] } }, data: { status: 'WITHDRAWN' } });
      await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'CANCELED', version: { increment: 1 } } });
    }, 'GROUP_CANCELED', true);
  }

  private async organizerTransition(p: AuthenticatedPrincipal, id: string, expectedVersion: number, allowed: string[], message: string, change: (tx: Tx, g: LoadedGroup) => Promise<void>, event: string, restaurant = false) {
    const g = await this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.organizer(g, p.userId);
      this.version(g, expectedVersion);
      this.status(g, allowed, message);
      await change(tx, g);
      return tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude });
    });
    this.notify(g, this.activeIds(g), event, restaurant);
    return this.get(p, id);
  }

  // ---------------------------------------------------------------- customer: negotiation
  async propose(p: AuthenticatedPrincipal, id: string, input: { proposedTotalPaise: number; expectedVersion: number }) {
    const g = await this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.organizer(g, p.userId);
      this.version(g, input.expectedVersion);
      this.status(g, ['LOCKED', 'REJECTED'], 'Lock the group before sending a price request');
      if (g.proposalAttempts >= GROUP_RULES.maxProposalsPerGroup) throw new HttpException('This group has used all its price requests', 429);
      const toThis = g.proposals.filter((x) => x.restaurantId === g.restaurantId).length;
      if (toThis >= GROUP_RULES.maxProposalsPerRestaurant) throw new HttpException('You have already asked this restaurant several times. Try another restaurant.', 429);
      if (!g.restaurant.groupNegotiationEnabled) throw new UnprocessableEntityException('This restaurant is not taking group price requests');
      if (g.restaurant.operatingStatus !== 'OPEN' || !g.restaurant.deliveryAvailability) throw new UnprocessableEntityException('This restaurant is not accepting orders right now');
      const q = await this.quote(tx, g); // also re-validates availability, variants, add-ons and serviceability
      const normal = q.finalPayablePaise;
      const min = this.minAllowed(normal, g.restaurant.maxGroupDiscountBps);
      if (!Number.isInteger(input.proposedTotalPaise) || input.proposedTotalPaise >= normal) throw new UnprocessableEntityException(`Your proposal must be below the normal total of ₹${normal / 100}`);
      if (input.proposedTotalPaise < min) throw new UnprocessableEntityException(`This restaurant considers requests down to ₹${Math.ceil(min / 100)} (up to ${g.restaurant.maxGroupDiscountBps / 100}% off)`);
      const snapshot = q.lines.map((l: any) => ({ name: l.name, quantity: l.quantity, variant: l.variant?.name ?? null, addOns: l.addOns.map((a: any) => a.name), lineTotalPaise: l.lineTotalPaise }));
      await tx.groupProposal.create({ data: {
        groupId: g.id, restaurantId: g.restaurantId, cartRevision: g.cartRevision, memberCount: g.members.filter((m) => m.status === 'ACTIVE').length, itemsSnapshot: json(snapshot),
        itemSubtotalPaise: q.basePaise, customizationTotalPaise: q.variantPaise + q.addOnPaise, packagingPaise: q.packagingPaise, deliveryPaise: q.deliveryPaise, platformPaise: q.platformPaise,
        discountPaise: q.discountPaise, taxPaise: q.taxPaise, normalTotalPaise: normal, proposedTotalPaise: input.proposedTotalPaise, minAllowedTotalPaise: min,
        pricingFingerprint: this.fingerprint(q), responseExpiresAt: new Date(Date.now() + GROUP_RULES.restaurantResponseMinutes * 60_000),
      } });
      await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'PROPOSED', proposalAttempts: { increment: 1 }, version: { increment: 1 } } });
      return tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude });
    });
    this.notify(g, this.activeIds(g), 'PROPOSAL_SUBMITTED', true);
    return this.get(p, id);
  }

  /** Stable fingerprint of what is being bought and its normal price (not of quote timestamps). */
  private fingerprint(q: any) {
    return digest({ lines: q.lines.map((l: any) => [l.menuItemId, l.quantity, l.variant?.id ?? null, l.addOns.map((a: any) => a.id), l.lineTotalPaise]),
      totals: [q.basePaise, q.variantPaise, q.addOnPaise, q.packagingPaise, q.deliveryPaise, q.platformPaise, q.discountPaise, q.taxPaise, q.finalPayablePaise], policy: q.pricingPolicyVersion });
  }

  async respondToCounter(p: AuthenticatedPrincipal, id: string, proposalId: string, accept: boolean, expectedVersion: number) {
    const g = await this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.organizer(g, p.userId);
      this.version(g, expectedVersion);
      this.status(g, ['COUNTERED'], 'There is no counteroffer to answer (it may have expired)');
      const prop = g.proposals.find((x) => x.id === proposalId && x.status === 'COUNTERED');
      if (!prop) throw new ConflictException('This counteroffer is no longer valid');
      if (accept) {
        await tx.groupProposal.update({ where: { id: prop.id }, data: { status: 'ACCEPTED', agreedTotalPaise: prop.counterTotalPaise, offerExpiresAt: new Date(Date.now() + GROUP_RULES.acceptedOfferMinutes * 60_000) } });
        await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'ACCEPTED', version: { increment: 1 } } });
      } else {
        await tx.groupProposal.update({ where: { id: prop.id }, data: { status: 'DECLINED' } });
        await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'LOCKED', version: { increment: 1 } } });
      }
      return tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude });
    });
    this.notify(g, this.activeIds(g), accept ? 'COUNTER_ACCEPTED' : 'COUNTER_DECLINED', true);
    return this.get(p, id);
  }

  // ---------------------------------------------------------------- customer: alternatives
  async alternatives(p: AuthenticatedPrincipal, id: string) {
    return this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.member(g, p.userId);
      return this.findAlternatives(tx, g);
    });
  }

  private async findAlternatives(tx: Tx, g: LoadedGroup) {
    if (!g.items.length) return { alternatives: [] };
    const address = await tx.customerAddress.findUniqueOrThrow({ where: { id: g.addressId } });
    const wanted = await tx.menuItem.findMany({ where: { id: { in: g.items.map((i) => i.menuItemId) } }, include: { profile: true } });
    const candidates = await tx.restaurant.findMany({
      where: { id: { not: g.restaurantId }, operatingStatus: 'OPEN', deliveryAvailability: true, groupNegotiationEnabled: true, zones: { some: { zoneId: g.localityId, isEligible: true } } },
      select: { ...serviceabilitySelect, groupNegotiationEnabled: true, maxGroupDiscountBps: true, locality: { select: { name: true } }, items: { where: { availabilityStatus: 'AVAILABLE' }, include: { profile: true } } },
    });
    const area = await this.pricing.validateArea(tx, g.localityId), now = new Date(), rules = await this.pricing.rules(tx, area.id, now);
    const out = [];
    for (const r of candidates) {
      if (!evaluateServiceability(r as any, address).eligible) continue;
      const mapping = g.items.map((line) => {
        const w = wanted.find((x) => x.id === line.menuItemId)!;
        const want = { foodFamily: w.profile?.foodFamily ?? null, dishGroup: w.profile?.dishGroup ?? null, mainIngredient: (w.profile?.mainIngredient as any) ?? null };
        let best: { item: (typeof r.items)[number]; score: number } | null = null;
        for (const it of r.items) {
          if (it.isVegetarian !== w.isVegetarian || !it.profile) continue; // never swap veg for non-veg or vice versa
          const exactName = it.name.toLowerCase() === w.name.toLowerCase();
          const score = exactName ? 1.1 : familySimilarity(want, it.profile);
          if (score >= 0.6 && (!best || score > best.score || (score === best.score && it.basePricePaise < best.item.basePricePaise))) best = { item: it, score };
        }
        return { groupItemId: line.id, memberId: line.memberId, from: w.name, quantity: line.quantity, to: best ? { menuItemId: best.item.id, name: best.item.name, unitPricePaise: best.item.basePricePaise, sameDish: best.score > 1 } : null };
      });
      const matched = mapping.filter((m) => m.to);
      if (!matched.length) continue;
      const merch = matched.reduce((n, m) => n + m.to!.unitPricePaise * m.quantity, 0);
      const { finalPayablePaise } = calculate({ basePricePaise: merch, variantPaise: 0, addOnPaise: 0, quantity: 1, restaurantId: r.id, area: area.id, rules, now });
      const quality = Math.round((100 * matched.reduce((n, m) => n + (m.to!.sameDish ? 1 : 0.7), 0)) / mapping.length);
      out.push({ restaurantId: r.id, name: r.name, locality: r.locality?.name ?? null, matchPercent: quality, matchedCount: matched.length, totalCount: mapping.length,
        estimatedNormalTotalPaise: finalPayablePaise, lowestProposalPaise: this.minAllowed(finalPayablePaise, r.maxGroupDiscountBps),
        mapping: mapping.map((m) => ({ from: m.from, quantity: m.quantity, to: m.to ? { menuItemId: m.to.menuItemId, name: m.to.name, sameDish: m.to.sameDish, unitPricePaise: m.to.unitPricePaise } : null })) });
    }
    out.sort((a, b) => b.matchPercent - a.matchPercent || a.estimatedNormalTotalPaise - b.estimatedNormalTotalPaise);
    return { alternatives: out.slice(0, 5), note: 'Estimates use each restaurant\'s menu prices and your delivery fees. No restaurant has agreed to a price until it accepts your request.' };
  }

  /** Organizer-confirmed move to another restaurant: each member's dishes are mapped as shown, unmatched dishes are dropped. */
  async switchRestaurant(p: AuthenticatedPrincipal, id: string, input: { restaurantId: string; expectedVersion: number }) {
    const g = await this.run(p, 'CUSTOMER', async (tx) => {
      const g = await this.lockGroup(tx, id);
      this.organizer(g, p.userId);
      this.version(g, input.expectedVersion);
      this.status(g, ['LOCKED', 'REJECTED'], 'You can switch restaurants only after the current restaurant declines or before sending a request');
      const alt = (await this.findAlternatives(tx, g)).alternatives.find((a) => a.restaurantId === input.restaurantId);
      if (!alt) throw new UnprocessableEntityException('That restaurant is not an eligible alternative for this group');
      const targets = await tx.menuItem.findMany({ where: { restaurantId: input.restaurantId, availabilityStatus: 'AVAILABLE' }, include: itemInclude });
      await tx.groupCartItem.deleteMany({ where: { groupId: g.id } });
      for (const [i, line] of g.items.entries()) {
        const m = alt.mapping[i];
        if (!m.to) continue;
        const target = targets.find((t) => t.id === m.to!.menuItemId);
        if (!target) continue;
        const sel = this.pricing.selection(target, { restaurantId: input.restaurantId, menuItemId: target.id, area: g.localityId, quantity: line.quantity, addOnIds: [] }, { skipZone: true });
        const key = digest({ menuItemId: target.id, variantId: sel.variant?.id ?? null, addOnIds: [] });
        const existing = await tx.groupCartItem.findUnique({ where: { groupId_memberId_selectionKey: { groupId: g.id, memberId: line.memberId, selectionKey: key } } });
        const unit = target.basePricePaise + (sel.variant?.priceAdjustmentPaise ?? 0);
        if (existing) await tx.groupCartItem.update({ where: { id: existing.id }, data: { quantity: Math.min(20, existing.quantity + line.quantity) } });
        else await tx.groupCartItem.create({ data: { groupId: g.id, memberId: line.memberId, restaurantId: input.restaurantId, menuItemId: target.id, variantId: sel.variant?.id ?? null, addOnIds: [], selectionKey: key, quantity: line.quantity, unitPricePaise: unit } });
      }
      await tx.groupOrder.update({ where: { id: g.id }, data: { restaurantId: input.restaurantId, status: 'OPEN', cartRevision: { increment: 1 }, version: { increment: 1 } } });
      return tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude });
    });
    this.notify(g, this.activeIds(g), 'RESTAURANT_SWITCHED');
    return this.get(p, id);
  }

  // ---------------------------------------------------------------- customer: checkout
  async checkout(p: AuthenticatedPrincipal, id: string, input: { proposalId: string; expectedVersion: number; idempotencyKey: string }) {
    if (!['development', 'test'].includes(process.env.NODE_ENV ?? '') || process.env.DEMO_CHECKOUT_ENABLED !== 'true') throw new ForbiddenException('No approved payment method is configured');
    const requestHash = digest({ groupId: id, proposalId: input.proposalId, paymentMethod: 'DEMO_NO_PAYMENT' });
    const out = await this.run(p, 'CUSTOMER', async (tx) => {
      await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${p.userId}::uuid FOR UPDATE`; // serializes with personal checkout
      const prior = await tx.order.findUnique({ where: { customerId_idempotencyKey: { customerId: p.userId, idempotencyKey: input.idempotencyKey } }, include: orderInclude });
      if (prior) { if (prior.requestHash !== requestHash) throw new ConflictException('This checkout request was already used'); return { order: prior, g: null }; }
      const g = await this.lockGroup(tx, id);
      this.organizer(g, p.userId);
      this.version(g, input.expectedVersion);
      if (g.status === 'ORDERED') throw new ConflictException('This group order has already been placed');
      this.status(g, ['ACCEPTED'], 'There is no accepted price to check out (it may have expired)');
      const prop = g.proposals.find((x) => x.id === input.proposalId);
      if (!prop || prop.status !== 'ACCEPTED' || prop.agreedTotalPaise == null || prop.orderId) throw new ConflictException('This offer is not valid for checkout');
      if (prop.restaurantId !== g.restaurantId || prop.cartRevision !== g.cartRevision) throw new ConflictException('The group\'s food changed after the offer. Send a new price request.');
      if (!prop.offerExpiresAt || prop.offerExpiresAt <= new Date()) throw new GoneException('The accepted offer has expired. Send a new price request.');
      if (g.restaurant.operatingStatus !== 'OPEN' || !g.restaurant.deliveryAvailability) throw new UnprocessableEntityException('The restaurant is not accepting orders right now');
      const q = await this.quote(tx, g); // availability, serviceability and price re-checked now
      if (this.fingerprint(q) !== prop.pricingFingerprint || q.finalPayablePaise !== prop.normalTotalPaise) throw new ConflictException('Prices or fees changed since the restaurant agreed. Send a new price request.');
      const negotiated = prop.normalTotalPaise - prop.agreedTotalPaise;
      if (negotiated < 0 || prop.agreedTotalPaise < prop.minAllowedTotalPaise) throw new ConflictException('This offer is outside the allowed range');
      const cart = await tx.cart.upsert({ where: { customerId: p.userId }, create: { customerId: p.userId }, update: {} });
      const order = await tx.order.create({ data: {
        orderNumber: 'FD-' + randomBytes(10).toString('hex').toUpperCase(), customerId: p.userId, restaurantId: g.restaurantId, restaurantName: g.restaurant.name,
        cartId: cart.id, cartVersion: cart.version, idempotencyKey: input.idempotencyKey, requestHash, deliveryAddressSnapshot: json(q.address), paymentMethod: 'DEMO_NO_PAYMENT', status: 'PENDING_RESTAURANT',
        itemSubtotalPaise: q.basePaise, customizationTotalPaise: q.variantPaise + q.addOnPaise, packagingPaise: q.packagingPaise, deliveryPaise: q.deliveryPaise, platformPaise: q.platformPaise,
        discountPaise: q.discountPaise + negotiated, negotiatedDiscountPaise: negotiated, taxPaise: q.taxPaise, finalPayablePaise: prop.agreedTotalPaise, groupProposalId: prop.id,
        pricingPolicyVersion: q.pricingPolicyVersion, pricingSnapshot: json({ ...q, group: { groupId: g.id, proposalId: prop.id, normalTotalPaise: prop.normalTotalPaise, agreedTotalPaise: prop.agreedTotalPaise, negotiatedDiscountPaise: negotiated, members: g.members.filter((m) => m.status === 'ACTIVE').length } }),
        items: { create: q.lines.map((l: any) => ({ menuItemId: l.menuItemId, name: l.name, imageKey: l.imageKey, baseUnitPaise: l.baseUnitPaise, quantity: l.quantity, lineTotalPaise: l.lineTotalPaise,
          ...(l.variant ? { variantSnapshot: json(l.variant) } : {}), addOns: { create: l.addOns.map((a: any) => ({ originalAddOnId: a.id, name: a.name, unitPricePaise: a.pricePaise })) } })) },
        events: { create: { actorUserId: p.userId, eventType: 'ORDER_CREATED', sequence: 1, newStatus: 'PENDING_RESTAURANT', metadata: { paymentCollected: false, groupOrder: true, negotiatedDiscountPaise: negotiated } } },
      }, include: orderInclude });
      await queueEvent(tx, order.events.find((e) => e.eventType === 'ORDER_CREATED')!.id);
      // Personal cart items are untouched; its version moves on so (cartId, cartVersion) stays unique.
      await tx.cart.update({ where: { id: cart.id }, data: { version: { increment: 1 } } });
      await tx.groupProposal.update({ where: { id: prop.id }, data: { status: 'USED', orderId: order.id } });
      await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'ORDERED', orderId: order.id, version: { increment: 1 } } });
      return { order, g: await tx.groupOrder.findUniqueOrThrow({ where: { id: g.id }, include: groupInclude }) };
    });
    if (out.g) this.notify(out.g, this.activeIds(out.g), 'GROUP_ORDER_CONFIRMED', true);
    const o = out.order;
    return { orderId: o.id, orderNumber: o.orderNumber, status: o.status, finalPayablePaise: o.finalPayablePaise, negotiatedDiscountPaise: (o as any).negotiatedDiscountPaise, normalTotalPaise: o.finalPayablePaise + (o as any).negotiatedDiscountPaise };
  }

  // ---------------------------------------------------------------- restaurant owner
  private async ownedRestaurants(tx: Tx, p: AuthenticatedPrincipal) {
    return (await tx.restaurantMembership.findMany({ where: { userId: p.userId, status: 'ACTIVE', membershipRole: 'OWNER' }, select: { restaurantId: true } })).map((m) => m.restaurantId);
  }

  async ownerList(p: AuthenticatedPrincipal, restaurantId?: string) {
    return this.run(p, 'RESTAURANT_OWNER', async (tx) => {
      const owned = await this.ownedRestaurants(tx, p);
      if (restaurantId && !owned.includes(restaurantId)) throw new ForbiddenException('No active owner membership for this restaurant');
      const ids = restaurantId ? [restaurantId] : owned;
      const stale = await tx.groupProposal.findMany({ where: { restaurantId: { in: ids }, status: { in: ['PENDING', 'COUNTERED', 'ACCEPTED'] } }, select: { groupId: true } });
      for (const s of stale) await this.lockGroup(tx, s.groupId); // applies expiry
      const rows = await tx.groupProposal.findMany({ where: { restaurantId: { in: ids } }, orderBy: { createdAt: 'desc' }, take: 50, include: { restaurant: { select: { name: true, locality: { select: { name: true } } } }, group: { select: { name: true, status: true } } } });
      return rows.map((r) => this.ownerView(r));
    });
  }

  private ownerView(r: any) {
    return { id: r.id, groupReference: 'GRP-' + r.groupId.slice(0, 8).toUpperCase(), groupName: r.group?.name ?? null, restaurantId: r.restaurantId, restaurantName: r.restaurant?.name,
      outletLocality: r.restaurant?.locality?.name ?? null, memberCount: r.memberCount, items: r.itemsSnapshot, status: r.status,
      normalTotalPaise: r.normalTotalPaise, proposedTotalPaise: r.proposedTotalPaise, requestedReductionPaise: r.normalTotalPaise - r.proposedTotalPaise,
      requestedReductionPercent: Math.round((10000 * (r.normalTotalPaise - r.proposedTotalPaise)) / r.normalTotalPaise) / 100,
      counterTotalPaise: r.counterTotalPaise, agreedTotalPaise: r.agreedTotalPaise, minAllowedTotalPaise: r.minAllowedTotalPaise,
      breakdown: { itemSubtotalPaise: r.itemSubtotalPaise, customizationTotalPaise: r.customizationTotalPaise, packagingPaise: r.packagingPaise, deliveryPaise: r.deliveryPaise, platformPaise: r.platformPaise, discountPaise: r.discountPaise, taxPaise: r.taxPaise },
      responseExpiresAt: r.responseExpiresAt, offerExpiresAt: r.offerExpiresAt, responseNote: r.responseNote, orderId: r.orderId, createdAt: r.createdAt };
  }

  async ownerRespond(p: AuthenticatedPrincipal, proposalId: string, action: 'accept' | 'reject' | 'counter', input: { counterTotalPaise?: number; note?: string }) {
    const out = await this.run(p, 'RESTAURANT_OWNER', async (tx) => {
      const found = await tx.groupProposal.findUnique({ where: { id: proposalId }, select: { groupId: true, restaurantId: true } });
      if (!found) throw new NotFoundException('Proposal not found');
      const owned = await this.ownedRestaurants(tx, p);
      if (!owned.includes(found.restaurantId)) throw new ForbiddenException('No active owner membership for this restaurant');
      const g = await this.lockGroup(tx, found.groupId);
      const prop = g.proposals.find((x) => x.id === proposalId)!;
      if (prop.status === 'EXPIRED') throw new GoneException('This request has expired');
      if (prop.status !== 'PENDING' || g.status !== 'PROPOSED' || g.restaurantId !== prop.restaurantId) throw new ConflictException('This request has already been answered or withdrawn');
      const note = input.note?.trim().slice(0, 300) || null;
      const base = { respondedById: p.userId, respondedAt: new Date(), responseNote: note };
      if (action === 'accept') {
        await tx.groupProposal.update({ where: { id: prop.id }, data: { ...base, status: 'ACCEPTED', agreedTotalPaise: prop.proposedTotalPaise, offerExpiresAt: new Date(Date.now() + GROUP_RULES.acceptedOfferMinutes * 60_000) } });
        await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'ACCEPTED', version: { increment: 1 } } });
      } else if (action === 'reject') {
        await tx.groupProposal.update({ where: { id: prop.id }, data: { ...base, status: 'REJECTED' } });
        await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'REJECTED', version: { increment: 1 } } });
      } else {
        const c = input.counterTotalPaise;
        if (!Number.isInteger(c) || c! <= prop.proposedTotalPaise || c! >= prop.normalTotalPaise) {
          throw new UnprocessableEntityException(`A counteroffer must be between ₹${prop.proposedTotalPaise / 100} (their request) and ₹${prop.normalTotalPaise / 100} (the normal total)`);
        }
        await tx.groupProposal.update({ where: { id: prop.id }, data: { ...base, status: 'COUNTERED', counterTotalPaise: c, offerExpiresAt: new Date(Date.now() + GROUP_RULES.counterResponseMinutes * 60_000) } });
        await tx.groupOrder.update({ where: { id: g.id }, data: { status: 'COUNTERED', version: { increment: 1 } } });
      }
      const fresh = await tx.groupProposal.findUniqueOrThrow({ where: { id: prop.id }, include: { restaurant: { select: { name: true, locality: { select: { name: true } } } }, group: { select: { name: true, status: true } } } });
      return { view: this.ownerView(fresh), g };
    });
    this.notify(out.g, this.activeIds(out.g), action === 'accept' ? 'PROPOSAL_ACCEPTED' : action === 'reject' ? 'PROPOSAL_REJECTED' : 'COUNTEROFFER_RECEIVED', true);
    return out.view;
  }
}
