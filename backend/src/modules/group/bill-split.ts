/**
 * Group bill splitting (informational: the organizer pays the order; members owe the organizer).
 *
 * All amounts are integer paise. Every share is non-negative and the shares always sum to
 * exactly `payablePaise` (the restaurant-agreed total, or the normal total as an estimate).
 * Remainders are distributed deterministically (largest remainder, ties by member order).
 */
export type SplitMethod = 'BY_PERSON' | 'EQUAL';

export interface SplitMember { userId: string; name: string }
export interface SplitLine { id: string; name: string; ownerId: string; sharedWith: string[]; lineTotalPaise: number }
export interface SplitInput {
  method: SplitMethod;
  members: SplitMember[];              // active members, in a stable order (join order)
  lines: SplitLine[];                  // food lines with authoritative line totals
  feesPaise: number;                   // packaging + delivery + platform + tax
  discountPaise: number;               // promotion + negotiated reduction
  payablePaise: number;                // = food + fees - discount
}
export interface MemberShare {
  userId: string; name: string; foodPaise: number; feesPaise: number; discountPaise: number; sharePaise: number;
  items: { name: string; portionPaise: number; sharedBetween: number }[];
}

/** Splits `total` across `weights` so the parts sum to `total` exactly (largest remainder, ties by index). */
export function allocate(total: number, weights: number[]): number[] {
  if (!Number.isInteger(total) || total < 0) throw new Error('Total must be a non-negative integer');
  const sum = weights.reduce((n, w) => n + w, 0);
  if (sum <= 0) return weights.map(() => 0);
  const exact = weights.map((w) => (total * w) / sum);
  const parts = exact.map(Math.floor);
  let left = total - parts.reduce((n, p) => n + p, 0);
  const order = exact.map((e, i) => ({ i, r: e - Math.floor(e) })).sort((a, b) => b.r - a.r || a.i - b.i);
  for (let k = 0; left > 0; k = (k + 1) % order.length, left--) parts[order[k].i]++;
  return parts;
}

export function splitBill(input: SplitInput): { method: SplitMethod; payablePaise: number; sumPaise: number; members: MemberShare[] } {
  const { members } = input;
  const food = input.lines.reduce((n, l) => n + l.lineTotalPaise, 0);
  if (food + input.feesPaise - input.discountPaise !== input.payablePaise) throw new Error('Split inputs do not reconcile');
  const index = new Map(members.map((m, i) => [m.userId, i]));
  const shares: MemberShare[] = members.map((m) => ({ userId: m.userId, name: m.name, foodPaise: 0, feesPaise: 0, discountPaise: 0, sharePaise: 0, items: [] }));
  if (!members.length) return { method: input.method, payablePaise: input.payablePaise, sumPaise: 0, members: [] };

  if (input.method === 'EQUAL') {
    const each = allocate(input.payablePaise, members.map(() => 1));
    const fees = allocate(input.feesPaise, members.map(() => 1));
    const disc = allocate(input.discountPaise, members.map(() => 1));
    shares.forEach((s, i) => { s.sharePaise = each[i]; s.feesPaise = fees[i]; s.discountPaise = disc[i]; s.foodPaise = each[i] - fees[i] + disc[i]; });
  } else {
    // Food: each line goes to the members it is assigned to (shared lines split evenly, never charged twice).
    for (const l of input.lines) {
      const people = [...new Set(l.sharedWith.filter((u) => index.has(u)))];
      const owners = people.length ? people.sort((a, b) => index.get(a)! - index.get(b)!) : index.has(l.ownerId) ? [l.ownerId] : members.map((m) => m.userId);
      const parts = allocate(l.lineTotalPaise, owners.map(() => 1));
      owners.forEach((u, k) => {
        const s = shares[index.get(u)!];
        s.foodPaise += parts[k];
        s.items.push({ name: l.name, portionPaise: parts[k], sharedBetween: owners.length });
      });
    }
    // Fees/tax and discounts follow each person's share of the food.
    const weights = shares.map((s) => s.foodPaise);
    const fees = allocate(input.feesPaise, weights), disc = allocate(input.discountPaise, weights);
    shares.forEach((s, i) => { s.feesPaise = fees[i]; s.discountPaise = disc[i]; s.sharePaise = s.foodPaise + fees[i] - disc[i]; });
    // Rounding can only push a share below zero by a paisa or two in degenerate cases; settle it by
    // re-splitting the whole payable proportionally, which is non-negative by construction.
    if (shares.some((s) => s.sharePaise < 0)) {
      const payable = allocate(input.payablePaise, weights);
      shares.forEach((s, i) => { s.sharePaise = payable[i]; s.discountPaise = s.foodPaise + s.feesPaise - payable[i]; });
    }
  }
  const sumPaise = shares.reduce((n, s) => n + s.sharePaise, 0);
  if (sumPaise !== input.payablePaise || shares.some((s) => s.sharePaise < 0)) throw new Error('Split failed to reconcile');
  return { method: input.method, payablePaise: input.payablePaise, sumPaise, members: shares };
}
