-- F2 group ordering and restaurant price negotiation. Additive only; no existing rows change.
CREATE TYPE "GroupOrderStatus" AS ENUM ('OPEN', 'LOCKED', 'PROPOSED', 'COUNTERED', 'ACCEPTED', 'REJECTED', 'ORDERED', 'CANCELED', 'EXPIRED');
CREATE TYPE "GroupMemberStatus" AS ENUM ('ACTIVE', 'LEFT');
CREATE TYPE "GroupProposalStatus" AS ENUM ('PENDING', 'ACCEPTED', 'COUNTERED', 'REJECTED', 'EXPIRED', 'WITHDRAWN', 'DECLINED', 'USED');

-- Restaurant participation settings (negotiation on by default for the demo catalog; eco packaging opt-in).
ALTER TABLE "Restaurant" ADD COLUMN "groupNegotiationEnabled" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "Restaurant" ADD COLUMN "maxGroupDiscountBps" INTEGER NOT NULL DEFAULT 3000;
ALTER TABLE "Restaurant" ADD COLUMN "ecoPackagingEnabled" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Restaurant" ADD CONSTRAINT "Restaurant_group_discount_range" CHECK ("maxGroupDiscountBps" BETWEEN 0 AND 5000);

CREATE TABLE "GroupOrder" (
    "id" UUID NOT NULL,
    "organizerId" UUID NOT NULL,
    "restaurantId" VARCHAR(64) NOT NULL,
    "addressId" UUID NOT NULL,
    "localityId" VARCHAR(64) NOT NULL,
    "name" VARCHAR(80),
    "status" "GroupOrderStatus" NOT NULL DEFAULT 'OPEN',
    "version" INTEGER NOT NULL DEFAULT 1,
    "cartRevision" INTEGER NOT NULL DEFAULT 1,
    "inviteTokenHash" CHAR(64) NOT NULL,
    "joinCodeHash" CHAR(64) NOT NULL,
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "proposalAttempts" INTEGER NOT NULL DEFAULT 0,
    "orderId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "GroupOrder_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "GroupOrder_counts_check" CHECK ("version" > 0 AND "cartRevision" > 0 AND "proposalAttempts" >= 0)
);
CREATE UNIQUE INDEX "GroupOrder_inviteTokenHash_key" ON "GroupOrder"("inviteTokenHash");
CREATE UNIQUE INDEX "GroupOrder_joinCodeHash_key" ON "GroupOrder"("joinCodeHash");
CREATE UNIQUE INDEX "GroupOrder_orderId_key" ON "GroupOrder"("orderId");
CREATE INDEX "GroupOrder_organizerId_createdAt_idx" ON "GroupOrder"("organizerId", "createdAt");
CREATE INDEX "GroupOrder_restaurantId_status_idx" ON "GroupOrder"("restaurantId", "status");
ALTER TABLE "GroupOrder" ADD CONSTRAINT "GroupOrder_organizerId_fkey" FOREIGN KEY ("organizerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "GroupOrder" ADD CONSTRAINT "GroupOrder_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "GroupOrder" ADD CONSTRAINT "GroupOrder_addressId_fkey" FOREIGN KEY ("addressId") REFERENCES "CustomerAddress"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "GroupOrder" ADD CONSTRAINT "GroupOrder_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "GroupMember" (
    "groupId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "displayName" VARCHAR(80) NOT NULL,
    "isOrganizer" BOOLEAN NOT NULL DEFAULT false,
    "status" "GroupMemberStatus" NOT NULL DEFAULT 'ACTIVE',
    "joinedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "GroupMember_pkey" PRIMARY KEY ("groupId", "userId")
);
CREATE INDEX "GroupMember_userId_idx" ON "GroupMember"("userId");
ALTER TABLE "GroupMember" ADD CONSTRAINT "GroupMember_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "GroupOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GroupMember" ADD CONSTRAINT "GroupMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "GroupCartItem" (
    "id" UUID NOT NULL,
    "groupId" UUID NOT NULL,
    "memberId" UUID NOT NULL,
    "restaurantId" VARCHAR(64) NOT NULL,
    "menuItemId" VARCHAR(64) NOT NULL,
    "variantId" UUID,
    "addOnIds" UUID[] NOT NULL DEFAULT ARRAY[]::UUID[],
    "selectionKey" CHAR(64) NOT NULL,
    "quantity" INTEGER NOT NULL,
    "unitPricePaise" INTEGER NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "GroupCartItem_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "GroupCartItem_values_check" CHECK ("quantity" BETWEEN 1 AND 20 AND "unitPricePaise" >= 0 AND "version" > 0)
);
CREATE UNIQUE INDEX "GroupCartItem_groupId_memberId_selectionKey_key" ON "GroupCartItem"("groupId", "memberId", "selectionKey");
CREATE INDEX "GroupCartItem_groupId_idx" ON "GroupCartItem"("groupId");
ALTER TABLE "GroupCartItem" ADD CONSTRAINT "GroupCartItem_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "GroupOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GroupCartItem" ADD CONSTRAINT "GroupCartItem_member_fkey" FOREIGN KEY ("groupId", "memberId") REFERENCES "GroupMember"("groupId", "userId") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GroupCartItem" ADD CONSTRAINT "GroupCartItem_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "MenuItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "GroupProposal" (
    "id" UUID NOT NULL,
    "groupId" UUID NOT NULL,
    "restaurantId" VARCHAR(64) NOT NULL,
    "cartRevision" INTEGER NOT NULL,
    "memberCount" INTEGER NOT NULL,
    "itemsSnapshot" JSONB NOT NULL,
    "itemSubtotalPaise" INTEGER NOT NULL,
    "customizationTotalPaise" INTEGER NOT NULL,
    "packagingPaise" INTEGER NOT NULL,
    "deliveryPaise" INTEGER NOT NULL,
    "platformPaise" INTEGER NOT NULL,
    "discountPaise" INTEGER NOT NULL,
    "taxPaise" INTEGER NOT NULL,
    "normalTotalPaise" INTEGER NOT NULL,
    "proposedTotalPaise" INTEGER NOT NULL,
    "minAllowedTotalPaise" INTEGER NOT NULL,
    "counterTotalPaise" INTEGER,
    "agreedTotalPaise" INTEGER,
    "pricingFingerprint" CHAR(64) NOT NULL,
    "status" "GroupProposalStatus" NOT NULL DEFAULT 'PENDING',
    "responseExpiresAt" TIMESTAMPTZ(3) NOT NULL,
    "offerExpiresAt" TIMESTAMPTZ(3),
    "respondedById" UUID,
    "respondedAt" TIMESTAMPTZ(3),
    "responseNote" VARCHAR(300),
    "orderId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "GroupProposal_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "GroupProposal_amounts_check" CHECK (
      "itemSubtotalPaise" >= 0 AND "customizationTotalPaise" >= 0 AND "packagingPaise" >= 0 AND "deliveryPaise" >= 0
      AND "platformPaise" >= 0 AND "discountPaise" >= 0 AND "taxPaise" >= 0 AND "normalTotalPaise" > 0
      AND "normalTotalPaise" = "itemSubtotalPaise" + "customizationTotalPaise" + "packagingPaise" + "deliveryPaise" + "platformPaise" - "discountPaise" + "taxPaise"
      AND "proposedTotalPaise" > 0 AND "proposedTotalPaise" < "normalTotalPaise" AND "proposedTotalPaise" >= "minAllowedTotalPaise"
      AND ("counterTotalPaise" IS NULL OR ("counterTotalPaise" > "proposedTotalPaise" AND "counterTotalPaise" < "normalTotalPaise"))
      AND ("agreedTotalPaise" IS NULL OR ("agreedTotalPaise" >= "minAllowedTotalPaise" AND "agreedTotalPaise" <= "normalTotalPaise"))
    )
);
CREATE INDEX "GroupProposal_restaurantId_status_createdAt_idx" ON "GroupProposal"("restaurantId", "status", "createdAt");
CREATE INDEX "GroupProposal_groupId_createdAt_idx" ON "GroupProposal"("groupId", "createdAt");
CREATE UNIQUE INDEX "GroupProposal_orderId_key" ON "GroupProposal"("orderId");
-- At most one live proposal (awaiting the restaurant, countered, or accepted) per group.
CREATE UNIQUE INDEX "GroupProposal_one_live_per_group" ON "GroupProposal"("groupId") WHERE "status" IN ('PENDING', 'COUNTERED', 'ACCEPTED');
ALTER TABLE "GroupProposal" ADD CONSTRAINT "GroupProposal_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "GroupOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GroupProposal" ADD CONSTRAINT "GroupProposal_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "GroupProposal" ADD CONSTRAINT "GroupProposal_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Order linkage: the negotiated reduction is an explicit, auditable part of discountPaise.
ALTER TABLE "Order" ADD COLUMN "negotiatedDiscountPaise" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "groupProposalId" UUID;
ALTER TABLE "Order" ADD CONSTRAINT "Order_negotiated_discount_check" CHECK ("negotiatedDiscountPaise" >= 0 AND "negotiatedDiscountPaise" <= "discountPaise");
CREATE UNIQUE INDEX "Order_groupProposalId_key" ON "Order"("groupProposalId");
