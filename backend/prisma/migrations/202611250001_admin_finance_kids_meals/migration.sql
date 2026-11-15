-- v1.1: owner-curated Kids Meals flag and manual rider payout settlements. Additive only.
ALTER TABLE "MenuItem" ADD COLUMN "isKidsMeal" BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX "MenuItem_isKidsMeal_availabilityStatus_idx" ON "MenuItem"("isKidsMeal", "availabilityStatus");

CREATE TABLE "RiderPayout" (
  "id" UUID NOT NULL,
  "riderId" UUID NOT NULL,
  "amountPaise" INTEGER NOT NULL,
  "note" VARCHAR(200),
  "reference" VARCHAR(80),
  "idempotencyKey" UUID NOT NULL,
  "recordedById" UUID NOT NULL,
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "RiderPayout_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "RiderPayout_amount_positive" CHECK ("amountPaise" > 0)
);
CREATE UNIQUE INDEX "RiderPayout_idempotencyKey_key" ON "RiderPayout"("idempotencyKey");
CREATE INDEX "RiderPayout_riderId_createdAt_idx" ON "RiderPayout"("riderId", "createdAt");
ALTER TABLE "RiderPayout" ADD CONSTRAINT "RiderPayout_riderId_fkey" FOREIGN KEY ("riderId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "RiderPayout" ADD CONSTRAINT "RiderPayout_recordedById_fkey" FOREIGN KEY ("recordedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
