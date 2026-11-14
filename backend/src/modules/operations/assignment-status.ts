import type { OrderStatus } from '../../generated/prisma/client';

/**
 * Delivery-assignment states in which the rider is still responsible for the order.
 * Terminal states (DELIVERED, CANCELED, REJECTED) never make a rider busy.
 */
export const ACTIVE_ASSIGNMENT_STATUSES: OrderStatus[] = [
  'READY_FOR_PICKUP',
  'PICKED_UP',
  'OUT_FOR_DELIVERY',
];
