import { Body, ConflictException, Controller, ForbiddenException, Get, HttpCode, Inject, Injectable, Module, NotFoundException, Param, Patch, Post, Query, UnprocessableEntityException, UseGuards } from '@nestjs/common';
import { IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min } from 'class-validator';
import { AuthModule } from '../auth/auth.module';
import { AuthGuard, CurrentUser, Roles, RolesGuard } from '../auth/auth.guards';
import { AuthenticatedPrincipal } from '../auth/auth.types';
import { DatabaseService } from '../../database/database.module';
import { Prisma } from '../../generated/prisma/client';
import { itemDto, itemInclude } from '../catalog/catalog.mapper';

/** Platform commission on rider delivery earnings, in basis points (default 10%). */
export function riderCommissionBps() {
  const v = Number(process.env.RIDER_COMMISSION_BPS ?? '1000');
  return Number.isInteger(v) && v >= 0 && v <= 5000 ? v : 1000;
}
/** Per-delivery split. Integer paise; gross = the order's delivery fee. */
export function deliverySplit(grossPaise: number, bps = riderCommissionBps()) {
  const commission = Math.round((grossPaise * bps) / 10000);
  return { grossPaise, commissionPaise: commission, netPaise: grossPaise - commission };
}
export type Range = 'day' | 'week' | 'month' | 'all';
export function rangeStart(range: Range, now = new Date()): Date | null {
  if (range === 'all') return null;
  const ist = new Date(now.getTime() + 330 * 60_000); // calendar boundaries in India time
  ist.setUTCHours(0, 0, 0, 0);
  if (range === 'week') ist.setUTCDate(ist.getUTCDate() - ((ist.getUTCDay() + 6) % 7));
  if (range === 'month') ist.setUTCDate(1);
  return new Date(ist.getTime() - 330 * 60_000);
}
const CLOSED = ['DELIVERED', 'CANCELED', 'REJECTED'] as const;
const CANCELLED = ['CANCELED', 'REJECTED'] as const;
const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);
const dayKey = (d: Date) => new Date(d.getTime() + 330 * 60_000).toISOString().slice(0, 10);

class RangeQuery { @IsOptional() @IsIn(['day', 'week', 'month', 'all']) range?: Range; }
class PayoutInput {
  @IsUUID() riderId!: string;
  @IsInt() @Min(100) @Max(100_000_000) amountPaise!: number;
  @IsOptional() @IsString() @MaxLength(200) note?: string;
  @IsOptional() @IsString() @MaxLength(80) reference?: string;
  @IsUUID() idempotencyKey!: string;
}
class KidsQuery { @IsOptional() @Matches(/^[a-z0-9-]{1,64}$/) area?: string; }
class KidsFlagInput { @IsBoolean() isKidsMeal!: boolean; }

@Injectable()
export class InsightsService {
  constructor(@Inject(DatabaseService) readonly database: DatabaseService) {}
  private get db() { return this.database.client; }

  /** Earnings come only from DELIVERED orders (one assignment per order), so nothing is counted twice. */
  private async deliveries(where: Prisma.DeliveryAssignmentWhereInput) {
    const rows = await this.db.deliveryAssignment.findMany({
      where: { ...where, order: { status: 'DELIVERED' }, deliveredAt: { not: null, ...((where.deliveredAt as object) ?? {}) } },
      orderBy: { deliveredAt: 'desc' },
      select: { orderId: true, riderId: true, deliveredAt: true, order: { select: { orderNumber: true, restaurantName: true, deliveryPaise: true, finalPayablePaise: true } } },
    });
    const bps = riderCommissionBps();
    return rows.map((r) => ({ orderId: r.orderId, riderId: r.riderId, orderNumber: r.order.orderNumber, restaurantName: r.order.restaurantName, deliveredAt: r.deliveredAt!, ...deliverySplit(r.order.deliveryPaise, bps) }));
  }
  private totals(rows: { grossPaise: number; commissionPaise: number; netPaise: number }[]) {
    return { deliveries: rows.length, grossPaise: sum(rows.map((r) => r.grossPaise)), commissionPaise: sum(rows.map((r) => r.commissionPaise)), netPaise: sum(rows.map((r) => r.netPaise)) };
  }

  async riderEarnings(p: AuthenticatedPrincipal) {
    const all = await this.deliveries({ riderId: p.userId });
    const since = (r: Range) => { const s = rangeStart(r)!; return all.filter((d) => d.deliveredAt >= s); };
    const payouts = await this.db.riderPayout.findMany({ where: { riderId: p.userId }, orderBy: { createdAt: 'desc' }, take: 50, select: { id: true, amountPaise: true, note: true, reference: true, createdAt: true } });
    const lifetime = this.totals(all);
    const paidPaise = sum(payouts.map((x) => x.amountPaise));
    return {
      commissionPercent: riderCommissionBps() / 100,
      today: this.totals(since('day')), week: this.totals(since('week')), month: this.totals(since('month')), lifetime,
      payouts: { completedPaise: paidPaise, pendingPaise: Math.max(0, lifetime.netPaise - paidPaise), history: payouts },
      history: all.slice(0, 50).map(({ riderId, ...d }) => d),
      note: 'Gross = delivery fee of each completed delivery. Payouts are recorded manually by the admin; no bank transfer is made in the app.',
    };
  }

  async riderBalances() {
    const riders = await this.db.user.findMany({ where: { roles: { some: { roleName: 'DELIVERY_PARTNER' } } }, select: { id: true, displayName: true } });
    const all = await this.deliveries({});
    const paid = await this.db.riderPayout.groupBy({ by: ['riderId'], _sum: { amountPaise: true } });
    const paidBy = new Map(paid.map((x) => [x.riderId, x._sum.amountPaise ?? 0]));
    return riders.map((r) => {
      const t = this.totals(all.filter((d) => d.riderId === r.id));
      const completedPaise = paidBy.get(r.id) ?? 0;
      return { riderId: r.id, name: r.displayName, ...t, completedPayoutPaise: completedPaise, pendingPayoutPaise: Math.max(0, t.netPaise - completedPaise) };
    }).sort((a, b) => b.pendingPayoutPaise - a.pendingPayoutPaise || b.deliveries - a.deliveries);
  }

  /** Records a manual settlement. Serialized per rider; never more than the rider's unpaid net earnings. */
  async recordPayout(p: AuthenticatedPrincipal, input: PayoutInput) {
    const prior = await this.db.riderPayout.findUnique({ where: { idempotencyKey: input.idempotencyKey } });
    if (prior) { if (prior.riderId !== input.riderId || prior.amountPaise !== input.amountPaise) throw new ConflictException('This payout request was already used'); return prior; }
    return this.db.$transaction(async (tx) => {
      const rider = await tx.user.findFirst({ where: { id: input.riderId, roles: { some: { roleName: 'DELIVERY_PARTNER' } } }, select: { id: true } });
      if (!rider) throw new NotFoundException('Delivery partner not found');
      await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${input.riderId}::uuid FOR UPDATE`;
      const delivered = await tx.deliveryAssignment.findMany({ where: { riderId: input.riderId, deliveredAt: { not: null }, order: { status: 'DELIVERED' } }, select: { order: { select: { deliveryPaise: true } } } });
      const earned = sum(delivered.map((d) => deliverySplit(d.order.deliveryPaise).netPaise));
      const paid = (await tx.riderPayout.aggregate({ where: { riderId: input.riderId }, _sum: { amountPaise: true } }))._sum.amountPaise ?? 0;
      if (input.amountPaise > earned - paid) throw new UnprocessableEntityException(`Payout exceeds the pending balance of ₹${((earned - paid) / 100).toFixed(2)}`);
      return tx.riderPayout.create({ data: { riderId: input.riderId, amountPaise: input.amountPaise, note: input.note?.trim() || null, reference: input.reference?.trim() || null, idempotencyKey: input.idempotencyKey, recordedById: p.userId } });
    }, { isolationLevel: 'Serializable' });
  }

  async dashboard(range: Range) {
    const start = rangeStart(range);
    const created = start ? { createdAt: { gte: start } } : {};
    const [customers, restaurants, riders, orders] = await Promise.all([
      this.db.userRole.count({ where: { roleName: 'CUSTOMER' } }),
      this.db.restaurant.count(),
      this.db.userRole.count({ where: { roleName: 'DELIVERY_PARTNER' } }),
      this.db.order.findMany({ where: created, orderBy: { createdAt: 'desc' }, select: { id: true, orderNumber: true, restaurantId: true, restaurantName: true, status: true, paymentMethod: true, paymentStatus: true, finalPayablePaise: true, platformPaise: true, deliveryPaise: true, createdAt: true } }),
    ]);
    // Revenue counts orders that went ahead: not cancelled/rejected and not left awaiting payment.
    const counted = orders.filter((o) => !(CANCELLED as readonly string[]).includes(o.status) && o.status !== 'AWAITING_PAYMENT');
    const deliveries = await this.deliveries(start ? { deliveredAt: { gte: start } } : {});
    const rider = this.totals(deliveries);
    const platformFeesPaise = sum(counted.map((o) => o.platformPaise));
    const allNet = this.totals(await this.deliveries({})).netPaise;
    const paidAll = (await this.db.riderPayout.aggregate({ _sum: { amountPaise: true } }))._sum.amountPaise ?? 0;
    const paidInRange = (await this.db.riderPayout.aggregate({ where: start ? { createdAt: { gte: start } } : {}, _sum: { amountPaise: true } }))._sum.amountPaise ?? 0;
    const perRestaurant = new Map<string, { restaurantId: string; name: string; orders: number; completed: number; revenuePaise: number }>();
    for (const o of orders) {
      const r = perRestaurant.get(o.restaurantId) ?? { restaurantId: o.restaurantId, name: o.restaurantName, orders: 0, completed: 0, revenuePaise: 0 };
      r.orders++; if (o.status === 'DELIVERED') r.completed++;
      if (counted.includes(o)) r.revenuePaise += o.finalPayablePaise;
      perRestaurant.set(o.restaurantId, r);
    }
    const days = range === 'month' || range === 'all' ? 30 : 7;
    const series: { date: string; revenuePaise: number; orders: number }[] = [];
    for (let i = days - 1; i >= 0; i--) series.push({ date: dayKey(new Date(Date.now() - i * 86_400_000)), revenuePaise: 0, orders: 0 });
    const chartOrders = await this.db.order.findMany({ where: { createdAt: { gte: new Date(Date.now() - days * 86_400_000) }, status: { notIn: ['CANCELED', 'REJECTED', 'AWAITING_PAYMENT'] } }, select: { createdAt: true, finalPayablePaise: true } });
    for (const o of chartOrders) { const b = series.find((s) => s.date === dayKey(o.createdAt)); if (b) { b.revenuePaise += o.finalPayablePaise; b.orders++; } }
    const [payments, payouts] = await Promise.all([
      this.db.paymentAttempt.findMany({ where: { status: 'CAPTURED' }, orderBy: { updatedAt: 'desc' }, take: 10, select: { id: true, amountPaise: true, updatedAt: true, environment: true, order: { select: { orderNumber: true, restaurantName: true } } } }),
      this.db.riderPayout.findMany({ orderBy: { createdAt: 'desc' }, take: 10, select: { id: true, amountPaise: true, createdAt: true, reference: true, rider: { select: { displayName: true } } } }),
    ]);
    const transactions = [
      ...payments.map((x) => ({ id: x.id, type: 'PAYMENT', label: `${x.order.orderNumber} · ${x.order.restaurantName}`, amountPaise: x.amountPaise, at: x.updatedAt, note: `Razorpay ${x.environment}` })),
      ...payouts.map((x) => ({ id: x.id, type: 'PAYOUT', label: `Payout · ${x.rider.displayName}`, amountPaise: -x.amountPaise, at: x.createdAt, note: x.reference ?? 'Manual settlement' })),
    ].sort((a, b) => +b.at - +a.at).slice(0, 12);
    return {
      range, since: start, generatedAt: new Date(), commissionPercent: riderCommissionBps() / 100,
      people: { customers, restaurants, deliveryPartners: riders },
      orders: { total: orders.length, active: orders.filter((o) => !(CLOSED as readonly string[]).includes(o.status) && o.status !== 'AWAITING_PAYMENT').length, awaitingPayment: orders.filter((o) => o.status === 'AWAITING_PAYMENT').length, completed: orders.filter((o) => o.status === 'DELIVERED').length, cancelled: orders.filter((o) => (CANCELLED as readonly string[]).includes(o.status)).length },
      finance: {
        orderRevenuePaise: sum(counted.map((o) => o.finalPayablePaise)), paidOnlinePaise: sum(counted.filter((o) => o.paymentStatus === 'PAID').map((o) => o.finalPayablePaise)),
        platformFeesPaise, riderCommissionPaise: rider.commissionPaise, platformEarningsPaise: platformFeesPaise + rider.commissionPaise,
        riderGrossPaise: rider.grossPaise, riderNetPaise: rider.netPaise, payoutsCompletedPaise: paidInRange, payoutsPendingPaise: Math.max(0, allNet - paidAll),
      },
      series,
      restaurants: [...perRestaurant.values()].sort((a, b) => b.revenuePaise - a.revenuePaise || b.orders - a.orders).slice(0, 8),
      recentOrders: orders.slice(0, 10),
      transactions,
      definitions: 'Revenue = total payable of orders not cancelled, rejected or awaiting payment. Platform earnings = platform fees + commission on rider delivery earnings. Rider earnings = delivery fees of completed deliveries.',
    };
  }

  async kidsMeals(area?: string) {
    const items = await this.db.menuItem.findMany({
      where: { isKidsMeal: true, availabilityStatus: 'AVAILABLE', restaurant: { operatingStatus: 'OPEN', ...(area ? { zones: { some: { zoneId: area, isEligible: true } } } : {}) } },
      include: itemInclude, orderBy: [{ basePricePaise: 'asc' }, { id: 'asc' }], take: 60,
    });
    return { items: items.map(itemDto) };
  }

  async setKidsMeal(p: AuthenticatedPrincipal, id: string, flag: boolean) {
    const item = await this.db.menuItem.findUnique({ where: { id }, select: { restaurantId: true } });
    if (!item) throw new NotFoundException('Menu item not found');
    const member = await this.db.restaurantMembership.findFirst({ where: { userId: p.userId, restaurantId: item.restaurantId, status: 'ACTIVE', membershipRole: 'OWNER' } });
    if (!member) throw new ForbiddenException('No active owner membership for this restaurant');
    const updated = await this.db.menuItem.update({ where: { id }, data: { isKidsMeal: flag }, select: { id: true, name: true, isKidsMeal: true } });
    return updated;
  }
}

@Controller('admin') @UseGuards(AuthGuard, RolesGuard) @Roles('ADMIN')
class AdminInsightsController {
  constructor(@Inject(InsightsService) readonly s: InsightsService) {}
  @Get('dashboard') dashboard(@Query() q: RangeQuery) { return this.s.dashboard(q.range ?? 'week'); }
  @Get('rider-payouts') balances() { return this.s.riderBalances(); }
  @Post('rider-payouts') @HttpCode(200) pay(@CurrentUser() p: AuthenticatedPrincipal, @Body() b: PayoutInput) { return this.s.recordPayout(p, b); }
}
@Controller('rider') @UseGuards(AuthGuard, RolesGuard) @Roles('DELIVERY_PARTNER')
class RiderEarningsController {
  constructor(@Inject(InsightsService) readonly s: InsightsService) {}
  @Get('earnings') earnings(@CurrentUser() p: AuthenticatedPrincipal) { return this.s.riderEarnings(p); }
}
@Controller('kids-meals')
class KidsMealsController {
  constructor(@Inject(InsightsService) readonly s: InsightsService) {}
  @Get() list(@Query() q: KidsQuery) { return this.s.kidsMeals(q.area); }
}
@Controller('owner/menu-items') @UseGuards(AuthGuard, RolesGuard) @Roles('RESTAURANT_OWNER')
class OwnerKidsController {
  constructor(@Inject(InsightsService) readonly s: InsightsService) {}
  @Patch(':id/kids-meal') flag(@CurrentUser() p: AuthenticatedPrincipal, @Param('id') id: string, @Body() b: KidsFlagInput) {
    if (!/^[a-z0-9-]{1,64}$/.test(id)) throw new NotFoundException('Menu item not found');
    return this.s.setKidsMeal(p, id, b.isKidsMeal);
  }
}
@Module({ imports: [AuthModule], controllers: [AdminInsightsController, RiderEarningsController, KidsMealsController, OwnerKidsController], providers: [InsightsService] })
export class InsightsModule {}
