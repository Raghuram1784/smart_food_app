import { Inject, Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { DatabaseService } from '../../database/database.module';
import { Prisma, PricingRule } from '../../generated/prisma/client';
import { itemInclude, itemDto } from '../catalog/catalog.mapper';
import { QuoteInput, CompareInput } from './pricing.dto';
import { calculate, PRICING_POLICY, QUOTE_TTL_MS } from './pricing.calculator';

export type PricedItem = Prisma.MenuItemGetPayload<{ include: typeof itemInclude }>;

@Injectable()
export class PricingService {
  constructor(@Inject(DatabaseService) private readonly database: DatabaseService) {}

  async validateArea(tx: Prisma.TransactionClient, area: string) {
    const locality = await tx.locality.findFirst({ where: { id: area, isActive: true } });
    const zone = await tx.deliveryZone.findFirst({ where: { id: area, isActive: true } });
    if (!locality || !zone) throw new UnprocessableEntityException('Select an active delivery locality');
    return locality;
  }

  async rules(tx: Prisma.TransactionClient, area: string, now: Date) {
    return tx.pricingRule.findMany({ where: { isActive: true, effectiveFrom: { lte: now },
      AND: [{ OR: [{ effectiveUntil: null }, { effectiveUntil: { gt: now } }] },
        { OR: [{ zoneId: null }, { zoneId: area }] }] }, orderBy: { code: 'asc' } });
  }

  /** skipZone: serviceability is decided elsewhere (verified-distance policy, or deferred to quote/checkout). */
  selection(item: PricedItem, input: Omit<QuoteInput, 'area'> & { area?: string }, opts: { skipZone?: boolean } = {}) {
    if (item.restaurantId !== input.restaurantId) throw new UnprocessableEntityException('Item does not belong to this restaurant');
    if (item.availabilityStatus !== 'AVAILABLE' || !item.category.isActive) throw new UnprocessableEntityException(item.availabilityReason ?? 'Item is unavailable');
    const r = item.restaurant;
    const zone = r.zones.find(z => z.zoneId === input.area && z.isEligible && z.zone.isActive);
    if (r.operatingStatus !== 'OPEN' || !r.deliveryAvailability || (!zone && !opts.skipZone)) throw new UnprocessableEntityException('Restaurant cannot currently serve the selected locality');
    const variants = [...item.variants].sort((a,b) => a.priceAdjustmentPaise-b.priceAdjustmentPaise || a.id.localeCompare(b.id));
    const variant = input.variantId ? variants.find(v => v.id === input.variantId) : variants.find(v => v.isAvailable);
    if ((input.variantId || variants.length) && (!variant || !variant.isAvailable)) throw new UnprocessableEntityException('Selected variant is unavailable or incompatible');
    const additions = input.addOnIds.map(id => item.addOns.find(a => a.addOnId === id)?.addOn);
    if (additions.some(a => !a || !a.isAvailable) || new Set(input.addOnIds).size !== input.addOnIds.length) throw new UnprocessableEntityException('Selected add-on is unavailable or incompatible');
    const addOns = additions.filter((a): a is NonNullable<typeof a> => !!a);
    return {r,zone,variant,addOns};
  }

  price(item: PricedItem, input: QuoteInput, rules: PricingRule[], now: Date, areaName: string) {
    const {r,zone,variant,addOns}=this.selection(item,input);
    const result = calculate({ basePricePaise: item.basePricePaise, variantPaise: variant?.priceAdjustmentPaise ?? 0,
      addOnPaise: addOns.reduce((sum,a) => sum+a.pricePaise,0), quantity: input.quantity,
      restaurantId: r.id, area: input.area, promotion: input.promotion, rules, now });
    const { chosen, ...breakdown } = result;
    const ruleVersion = createHash('sha256').update(JSON.stringify({ policy: PRICING_POLICY, rules: chosen })).digest('hex').slice(0,24);
    const fingerprint = createHash('sha256').update(JSON.stringify({ input, itemVersion: item.version,
      itemUpdatedAt: item.updatedAt, status: item.availabilityStatus, restaurantUpdatedAt: r.updatedAt,
      zone, variant, addOns, ruleVersion, breakdown })).digest('hex');
    const expiry = Math.min(now.getTime()+QUOTE_TTL_MS, ...chosen.filter(r => r.effectiveUntil).map(r => r.effectiveUntil!.getTime()));
    return { item: itemDto(item), area: { id: input.area, name: areaName }, quantity: input.quantity,
      selectedVariant: variant ?? null, selectedAddOns: addOns, ...breakdown,
      currency: 'INR' as const, illustrative: true, orderable: true,
      estimatedMinutes: zone?.estimatedMinutes ?? r.estimatedDeliveryMaxMinutes,
      quotedAt: now.toISOString(), expiresAt: new Date(expiry).toISOString(), pricingRuleVersion: ruleVersion,
      quoteFingerprint: fingerprint, policyVersion: PRICING_POLICY,
      notice: 'Illustrative single-meal quote. No order is placed. Re-quote before any future checkout; availability and prices are not reserved.',
      taxNotice: chosen.some(r => r.component === 'TAX') ? 'Illustrative configured tax on discounted items.' : 'No tax rule configured; no tax added to this demo quote.' };
  }

  async quote(input: QuoteInput) {
    return this.database.client.$transaction(async tx => {
      const now = new Date();
      const area = await this.validateArea(tx, input.area);
      const item = await tx.menuItem.findUnique({ where: { id: input.menuItemId }, include: itemInclude });
      if (!item) throw new NotFoundException('Menu item not found');
      return this.price(item,input,await this.rules(tx,input.area,now),now,area.name);
    }, { isolationLevel: 'RepeatableRead' });
  }

  async compare(input: CompareInput) {
    return this.database.client.$transaction(async tx => {
      const now = new Date(), area = await this.validateArea(tx,input.area);
      const items = await tx.menuItem.findMany({ where: { id: { in: input.itemIds } }, include: itemInclude });
      if (items.length !== input.itemIds.length) throw new NotFoundException('A compared item no longer exists');
      const rules = await this.rules(tx,input.area,now);
      return { items: input.itemIds.map(id => {
        const item = items.find(i => i.id === id)!;
        return this.price(item,{ restaurantId:item.restaurantId,menuItemId:id,area:input.area,quantity:1,addOnIds:[] },rules,now,area.name);
      }), quotedAt: now.toISOString(), basis: 'One item per independent restaurant quote; fees included consistently.' };
    }, { isolationLevel: 'RepeatableRead' });
  }
}
