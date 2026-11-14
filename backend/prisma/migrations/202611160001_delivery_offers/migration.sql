-- Additive: persisted rider delivery invitations. No existing rows change.
CREATE TYPE "DeliveryOfferStatus" AS ENUM ('OFFERED', 'ACCEPTED', 'DECLINED', 'CLOSED');

CREATE TABLE "DeliveryOffer" (
    "id" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "riderId" UUID NOT NULL,
    "status" "DeliveryOfferStatus" NOT NULL DEFAULT 'OFFERED',
    "offeredAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "respondedAt" TIMESTAMPTZ(3),
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "DeliveryOffer_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "DeliveryOffer_orderId_riderId_key" ON "DeliveryOffer"("orderId", "riderId");
CREATE INDEX "DeliveryOffer_riderId_status_expiresAt_idx" ON "DeliveryOffer"("riderId", "status", "expiresAt");
CREATE INDEX "DeliveryOffer_orderId_status_idx" ON "DeliveryOffer"("orderId", "status");
-- Backstop: at most one accepted offer per order.
CREATE UNIQUE INDEX "DeliveryOffer_one_accepted_per_order" ON "DeliveryOffer"("orderId") WHERE "status" = 'ACCEPTED';
ALTER TABLE "DeliveryOffer" ADD CONSTRAINT "DeliveryOffer_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "DeliveryOffer" ADD CONSTRAINT "DeliveryOffer_riderId_fkey" FOREIGN KEY ("riderId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
