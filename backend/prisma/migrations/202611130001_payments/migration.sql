-- CreateEnum
CREATE TYPE "PaymentAttemptStatus" AS ENUM ('CREATING', 'CREATE_UNKNOWN', 'READY', 'AUTHORIZED', 'CAPTURED', 'FAILED');

-- AlterEnum
ALTER TYPE "OrderStatus" ADD VALUE 'AWAITING_PAYMENT';

-- AlterEnum
ALTER TYPE "PaymentMethod" ADD VALUE 'RAZORPAY_TEST';

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "PaymentStatus" ADD VALUE 'PAYMENT_PENDING';
ALTER TYPE "PaymentStatus" ADD VALUE 'PAYMENT_AUTHORIZED';
ALTER TYPE "PaymentStatus" ADD VALUE 'PAYMENT_FAILED';





-- CreateTable
CREATE TABLE "PaymentAttempt" (
    "id" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "provider" VARCHAR(20) NOT NULL DEFAULT 'RAZORPAY',
    "environment" VARCHAR(10) NOT NULL DEFAULT 'TEST',
    "keyId" VARCHAR(80) NOT NULL,
    "providerOrderId" VARCHAR(80),
    "providerPaymentId" VARCHAR(80),
    "receipt" VARCHAR(40) NOT NULL,
    "amountPaise" INTEGER NOT NULL,
    "currency" CHAR(3) NOT NULL DEFAULT 'INR',
    "status" "PaymentAttemptStatus" NOT NULL DEFAULT 'CREATING',
    "sequence" INTEGER NOT NULL DEFAULT 1,
    "failureCode" VARCHAR(80),
    "lastVerificationAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "PaymentAttempt_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PaymentWebhookEvent" (
    "id" UUID NOT NULL,
    "providerEventId" VARCHAR(100) NOT NULL,
    "eventType" VARCHAR(80) NOT NULL,
    "payloadHash" CHAR(64) NOT NULL,
    "providerOrderId" VARCHAR(80),
    "providerPaymentId" VARCHAR(80),
    "status" VARCHAR(20) NOT NULL DEFAULT 'RECEIVED',
    "receivedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processedAt" TIMESTAMPTZ(3),

    CONSTRAINT "PaymentWebhookEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PaymentAttempt_orderId_key" ON "PaymentAttempt"("orderId");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentAttempt_providerOrderId_key" ON "PaymentAttempt"("providerOrderId");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentAttempt_providerPaymentId_key" ON "PaymentAttempt"("providerPaymentId");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentAttempt_receipt_key" ON "PaymentAttempt"("receipt");

-- CreateIndex
CREATE INDEX "PaymentAttempt_status_updatedAt_idx" ON "PaymentAttempt"("status", "updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentWebhookEvent_providerEventId_key" ON "PaymentWebhookEvent"("providerEventId");

-- CreateIndex
CREATE INDEX "PaymentWebhookEvent_status_receivedAt_idx" ON "PaymentWebhookEvent"("status", "receivedAt");

-- AddForeignKey
ALTER TABLE "PaymentAttempt" ADD CONSTRAINT "PaymentAttempt_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PaymentAttempt" ADD CONSTRAINT "PaymentAttempt_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "PaymentAttempt" ADD CONSTRAINT "PaymentAttempt_test_amount" CHECK ("amountPaise" > 0 AND currency = 'INR' AND environment = 'TEST' AND provider = 'RAZORPAY' AND sequence > 0);
