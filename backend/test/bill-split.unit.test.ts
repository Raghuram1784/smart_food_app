import { test } from 'node:test';
import assert from 'node:assert/strict';
import { allocate, splitBill } from '../src/modules/group/bill-split';

const members = [{ userId: 'r', name: 'Raghu' }, { userId: 'n', name: 'Nikitha' }, { userId: 'p', name: 'Pranav' }, { userId: 's', name: 'Sreya' }];
const lines = [
  { id: '1', name: 'Chicken Biryani', ownerId: 'r', sharedWith: [], lineTotalPaise: 22900 },
  { id: '2', name: 'Paneer Butter Masala', ownerId: 'n', sharedWith: [], lineTotalPaise: 21900 },
  { id: '3', name: 'Butter Naan', ownerId: 'n', sharedWith: [], lineTotalPaise: 9800 },
  { id: '4', name: 'Chicken Fried Rice', ownerId: 'p', sharedWith: [], lineTotalPaise: 13900 },
  { id: '5', name: 'Veg Meals', ownerId: 's', sharedWith: [], lineTotalPaise: 14900 },
  { id: '6', name: 'Farmhouse Pizza', ownerId: 'r', sharedWith: ['r', 'p'], lineTotalPaise: 34900 },
];
const food = lines.reduce((n, l) => n + l.lineTotalPaise, 0); // 118300
const fees = 3500;

test('allocate: exact sum, deterministic largest-remainder rounding', () => {
  assert.deepEqual(allocate(1000, [1, 1, 1]), [334, 333, 333]);
  assert.deepEqual(allocate(140000, [1, 1, 1, 1]), [35000, 35000, 35000, 35000]);
  assert.deepEqual(allocate(5, [0, 0]), [0, 0]);
  assert.equal(allocate(99999, [3, 7, 11]).reduce((a, b) => a + b, 0), 99999);
});

test('split by person: assigned dishes, shared pizza split once, fees and negotiated discount allocated, exact total', () => {
  const negotiated = 20000;
  const r = splitBill({ method: 'BY_PERSON', members, lines, feesPaise: fees, discountPaise: negotiated, payablePaise: food + fees - negotiated });
  assert.equal(r.sumPaise, food + fees - negotiated);
  const by = Object.fromEntries(r.members.map((m) => [m.userId, m]));
  assert.equal(by.r.foodPaise, 22900 + 17450); assert.equal(by.p.foodPaise, 13900 + 17450, 'pizza split between Raghu and Pranav');
  assert.equal(by.n.foodPaise, 21900 + 9800); assert.equal(by.s.foodPaise, 14900);
  assert.equal(r.members.reduce((n, m) => n + m.foodPaise, 0), food, 'no dish charged twice');
  assert.equal(r.members.reduce((n, m) => n + m.feesPaise, 0), fees);
  assert.equal(r.members.reduce((n, m) => n + m.discountPaise, 0), negotiated);
  assert.ok(r.members.every((m) => m.sharePaise >= 0 && m.sharePaise === m.foodPaise + m.feesPaise - m.discountPaise));
  assert.equal(by.p.items.find((i) => i.name === 'Farmhouse Pizza')!.sharedBetween, 2);
});

test('split equally: ₹1,400 across four is ₹350 each; odd paise are distributed deterministically', () => {
  const four = splitBill({ method: 'EQUAL', members, lines: [{ id: 'x', name: 'Food', ownerId: 'r', sharedWith: [], lineTotalPaise: 136500 }], feesPaise: 3500, discountPaise: 0, payablePaise: 140000 });
  assert.deepEqual(four.members.map((m) => m.sharePaise), [35000, 35000, 35000, 35000]);
  const odd = splitBill({ method: 'EQUAL', members: members.slice(0, 3), lines: [{ id: 'x', name: 'Food', ownerId: 'r', sharedWith: [], lineTotalPaise: 99501 }], feesPaise: 500, discountPaise: 0, payablePaise: 100001 });
  assert.deepEqual(odd.members.map((m) => m.sharePaise), [33334, 33334, 33333]);
});

test('zero-item members owe nothing by person; removed members are ignored in sharing', () => {
  const r = splitBill({ method: 'BY_PERSON', members: members.slice(0, 2), lines: [{ id: '1', name: 'Biryani', ownerId: 'r', sharedWith: ['r', 'gone'], lineTotalPaise: 20000 }], feesPaise: 3500, discountPaise: 0, payablePaise: 23500 });
  assert.deepEqual(r.members.map((m) => m.sharePaise), [23500, 0]);
});

test('random inputs always reconcile exactly and never go negative', () => {
  let seed = 7; const rnd = (n: number) => { seed = (seed * 1103515245 + 12345) % 2 ** 31; return seed % n; };
  for (let k = 0; k < 500; k++) {
    const ms = members.slice(0, 1 + rnd(4));
    const ls = Array.from({ length: 1 + rnd(6) }, (_, i) => ({ id: String(i), name: 'D' + i, ownerId: ms[rnd(ms.length)].userId, sharedWith: rnd(3) === 0 ? ms.map((m) => m.userId) : [], lineTotalPaise: 1 + rnd(50000) }));
    const f = ls.reduce((n, l) => n + l.lineTotalPaise, 0), fe = rnd(6000), d = rnd(Math.floor((f + fe) * 0.5));
    for (const method of ['BY_PERSON', 'EQUAL'] as const) {
      const r = splitBill({ method, members: ms, lines: ls, feesPaise: fe, discountPaise: d, payablePaise: f + fe - d });
      assert.equal(r.sumPaise, f + fe - d); assert.ok(r.members.every((m) => m.sharePaise >= 0));
    }
  }
});

test('inputs that do not reconcile are refused (no silent price change)', () => {
  assert.throws(() => splitBill({ method: 'EQUAL', members, lines, feesPaise: fees, discountPaise: 0, payablePaise: food }), /reconcile/);
});
