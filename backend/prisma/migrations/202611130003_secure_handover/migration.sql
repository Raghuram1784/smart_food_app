-- CreateTable
CREATE TABLE "DeliveryHandover" (
    "id" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "assignmentId" UUID NOT NULL,
    "boundRiderId" UUID NOT NULL,
    "challengeVersion" INTEGER NOT NULL,
    "verifier" CHAR(64) NOT NULL,
    "encryptedPin" VARCHAR(160),
    "keyVersion" VARCHAR(40) NOT NULL,
    "issuedAt" TIMESTAMPTZ(3) NOT NULL,
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "nextIssueAt" TIMESTAMPTZ(3) NOT NULL,
    "issueCount" INTEGER NOT NULL DEFAULT 1,
    "failedAttempts" INTEGER NOT NULL DEFAULT 0,
    "lastFailedAt" TIMESTAMPTZ(3),
    "lockedAt" TIMESTAMPTZ(3),
    "lockedUntil" TIMESTAMPTZ(3),
    "verifiedAt" TIMESTAMPTZ(3),
    "consumedAt" TIMESTAMPTZ(3),
    "invalidatedAt" TIMESTAMPTZ(3),
    "completionExpectedVersion" INTEGER,
    "completedOrderVersion" INTEGER,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "DeliveryHandover_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "HandoverAudit" (
    "id" UUID NOT NULL,
    "handoverId" UUID NOT NULL,
    "challengeVersion" INTEGER NOT NULL,
    "actorUserId" UUID NOT NULL,
    "action" VARCHAR(40) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "HandoverAudit_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "DeliveryHandover_orderId_key" ON "DeliveryHandover"("orderId");

-- CreateIndex
CREATE INDEX "HandoverAudit_handoverId_createdAt_id_idx" ON "HandoverAudit"("handoverId", "createdAt", "id");

-- AddForeignKey
ALTER TABLE "DeliveryHandover" ADD CONSTRAINT "DeliveryHandover_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeliveryHandover" ADD CONSTRAINT "DeliveryHandover_assignmentId_fkey" FOREIGN KEY ("assignmentId") REFERENCES "DeliveryAssignment"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "HandoverAudit" ADD CONSTRAINT "HandoverAudit_handoverId_fkey" FOREIGN KEY ("handoverId") REFERENCES "DeliveryHandover"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "DeliveryHandover" ADD CONSTRAINT "DeliveryHandover_limits_check" CHECK ("failedAttempts" BETWEEN 0 AND 5 AND "issueCount" BETWEEN 1 AND 3 AND "challengeVersion" > 0 AND "expiresAt" > "issuedAt");
ALTER TABLE "DeliveryHandover" ADD CONSTRAINT "DeliveryHandover_consumption_check" CHECK ("consumedAt" IS NULL OR ("verifiedAt" IS NOT NULL AND "encryptedPin" IS NULL AND "completionExpectedVersion" IS NOT NULL AND "completedOrderVersion" = "completionExpectedVersion" + 1));
