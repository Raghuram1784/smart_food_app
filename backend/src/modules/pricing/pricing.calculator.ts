import { UnprocessableEntityException } from '@nestjs/common';
import { PricingRule, PricingComponent } from '../../generated/prisma/client';

export const PRICING_POLICY = 'single-meal-v1';
export const QUOTE_TTL_MS = 120_000;
export function exact(value: bigint): number {
  if (value < 0n || value > 100_000_000n) throw new UnprocessableEntityException('Amount is outside the supported quote range');
  return Number(value);
}
export function halfUp(base: number, basisPoints: number): number {
  return exact((BigInt(base) * BigInt(basisPoints) + 5000n) / 10000n);
}

export function calculate(input: {
  basePricePaise: number; variantPaise: number; addOnPaise: number; quantity: number;
  restaurantId: string; area: string; promotion?: string; rules: PricingRule[]; now: Date;
}) {
  const basePaise = exact(BigInt(input.basePricePaise) * BigInt(input.quantity));
  const variantPaise = exact(BigInt(input.variantPaise) * BigInt(input.quantity));
  const addOnPaise = exact(BigInt(input.addOnPaise) * BigInt(input.quantity));
  const subtotalPaise = exact(BigInt(basePaise) + BigInt(variantPaise) + BigInt(addOnPaise));
  const applicable = input.rules.filter(r => r.isActive && r.effectiveFrom <= input.now &&
    (!r.effectiveUntil || r.effectiveUntil > input.now) &&
    (!r.restaurantId || r.restaurantId === input.restaurantId) && (!r.zoneId || r.zoneId === input.area) &&
    r.minimumSubtotalPaise <= subtotalPaise && (!r.promotionCode || r.promotionCode === input.promotion));
  const specificity = (r: PricingRule) => (r.restaurantId ? 2 : 0) + (r.zoneId ? 1 : 0);
  const chosen: PricingRule[] = [];
  const adjustments: { component: string; ruleCode: string; amountPaise: number; basis: string }[] = [];
  function component(type: PricingComponent, base: number, required = false): number {
    const candidates = applicable.filter(r => r.component === type &&
      (type !== 'DISCOUNT' || !input.promotion || r.promotionCode === input.promotion));
    candidates.sort((a,b) => specificity(b)-specificity(a) || b.priority-a.priority || a.code.localeCompare(b.code, 'en'));
    const rule = candidates[0];
    if (!rule) {
      if (required) throw new UnprocessableEntityException(`No ${type.toLowerCase()} pricing is configured for this locality`);
      return 0;
    }
    let amount = rule.fixedPaise ?? halfUp(base, rule.rateBasisPoints!);
    if (rule.maximumChargePaise !== null) amount = Math.min(amount, rule.maximumChargePaise);
    if (type === 'DISCOUNT') amount = Math.min(amount, subtotalPaise);
    chosen.push(rule);
    adjustments.push({ component: type, ruleCode: rule.code, amountPaise: amount,
      basis: type === 'TAX' ? 'items after discount; HALF_UP per component' : type === 'DISCOUNT' ? 'item subtotal; capped at subtotal' : 'once per single-restaurant quote' });
    return amount;
  }
  // Fees apply once per restaurant quote, never once per unit. Percentage fees use item subtotal.
  const packagingPaise = component('PACKAGING', subtotalPaise, true);
  const deliveryPaise = component('DELIVERY', subtotalPaise, true);
  const platformPaise = component('PLATFORM', subtotalPaise, true);
  const discountPaise = component('DISCOUNT', subtotalPaise);
  if (input.promotion && !chosen.some(r => r.component === 'DISCOUNT' && r.promotionCode === input.promotion)) {
    throw new UnprocessableEntityException('Promotion is not eligible for this quote');
  }
  const taxPaise = component('TAX', subtotalPaise - discountPaise);
  const finalPayablePaise = exact(BigInt(subtotalPaise) - BigInt(discountPaise) + BigInt(packagingPaise) + BigInt(deliveryPaise) + BigInt(platformPaise) + BigInt(taxPaise));
  return { basePaise, variantPaise, addOnPaise, subtotalPaise, packagingPaise, deliveryPaise,
    platformPaise, discountPaise, taxPaise, finalPayablePaise, adjustments, chosen };
}
