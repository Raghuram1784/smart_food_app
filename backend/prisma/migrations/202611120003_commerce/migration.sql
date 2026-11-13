-- CreateEnum
CREATE TYPE "OrderStatus" AS ENUM ('PENDING_RESTAURANT', 'ACCEPTED', 'PREPARING', 'READY_FOR_PICKUP', 'PICKED_UP', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELED', 'REJECTED');

-- CreateEnum
CREATE TYPE "PaymentStatus" AS ENUM ('UNPAID', 'PAID', 'REFUNDED');

-- CreateEnum
CREATE TYPE "PaymentMethod" AS ENUM ('DEMO_NO_PAYMENT');





-- CreateTable
CREATE TABLE "Cart" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "restaurantId" VARCHAR(64),
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "Cart_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CartItem" (
    "id" UUID NOT NULL,
    "cartId" UUID NOT NULL,
    "menuItemId" VARCHAR(64) NOT NULL,
    "variantId" UUID,
    "selectionKey" CHAR(64) NOT NULL,
    "quantity" INTEGER NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "CartItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CartItemAddOn" (
    "cartItemId" UUID NOT NULL,
    "addOnId" UUID NOT NULL,

    CONSTRAINT "CartItemAddOn_pkey" PRIMARY KEY ("cartItemId","addOnId")
);

-- CreateTable
CREATE TABLE "CustomerAddress" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "label" VARCHAR(40) NOT NULL,
    "recipientName" VARCHAR(80) NOT NULL,
    "contactNumber" VARCHAR(20) NOT NULL,
    "addressLine1" VARCHAR(200) NOT NULL,
    "addressLine2" VARCHAR(200) NOT NULL DEFAULT '',
    "landmark" VARCHAR(120) NOT NULL DEFAULT '',
    "localityId" VARCHAR(64) NOT NULL,
    "postalCode" VARCHAR(6) NOT NULL,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "CustomerAddress_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CartQuote" (
    "id" UUID NOT NULL,
    "cartId" UUID NOT NULL,
    "cartVersion" INTEGER NOT NULL,
    "addressId" UUID NOT NULL,
    "fingerprint" CHAR(64) NOT NULL,
    "promotion" VARCHAR(80),
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CartQuote_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Order" (
    "id" UUID NOT NULL,
    "orderNumber" VARCHAR(32) NOT NULL,
    "customerId" UUID NOT NULL,
    "restaurantId" VARCHAR(64) NOT NULL,
    "restaurantName" VARCHAR(160) NOT NULL,
    "cartId" UUID NOT NULL,
    "cartVersion" INTEGER NOT NULL,
    "idempotencyKey" UUID NOT NULL,
    "requestHash" CHAR(64) NOT NULL,
    "deliveryAddressSnapshot" JSONB NOT NULL,
    "status" "OrderStatus" NOT NULL DEFAULT 'PENDING_RESTAURANT',
    "paymentStatus" "PaymentStatus" NOT NULL DEFAULT 'UNPAID',
    "paymentMethod" "PaymentMethod" NOT NULL DEFAULT 'DEMO_NO_PAYMENT',
    "currency" CHAR(3) NOT NULL DEFAULT 'INR',
    "itemSubtotalPaise" INTEGER NOT NULL,
    "customizationTotalPaise" INTEGER NOT NULL,
    "packagingPaise" INTEGER NOT NULL,
    "deliveryPaise" INTEGER NOT NULL,
    "platformPaise" INTEGER NOT NULL,
    "discountPaise" INTEGER NOT NULL,
    "taxPaise" INTEGER NOT NULL,
    "finalPayablePaise" INTEGER NOT NULL,
    "pricingPolicyVersion" VARCHAR(80) NOT NULL,
    "pricingSnapshot" JSONB NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "canceledAt" TIMESTAMPTZ(3),

    CONSTRAINT "Order_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OrderItem" (
    "id" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "menuItemId" VARCHAR(64) NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "imageKey" VARCHAR(64) NOT NULL,
    "baseUnitPaise" INTEGER NOT NULL,
    "variantSnapshot" JSONB,
    "quantity" INTEGER NOT NULL,
    "lineTotalPaise" INTEGER NOT NULL,

    CONSTRAINT "OrderItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OrderItemAddOn" (
    "id" UUID NOT NULL,
    "orderItemId" UUID NOT NULL,
    "originalAddOnId" UUID NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "unitPricePaise" INTEGER NOT NULL,

    CONSTRAINT "OrderItemAddOn_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OrderEvent" (
    "id" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "actorUserId" UUID,
    "eventType" VARCHAR(60) NOT NULL,
    "previousStatus" "OrderStatus",
    "newStatus" "OrderStatus" NOT NULL,
    "metadata" JSONB NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "publishedAt" TIMESTAMPTZ(3),

    CONSTRAINT "OrderEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Cart_customerId_key" ON "Cart"("customerId");

-- CreateIndex
CREATE UNIQUE INDEX "CartItem_cartId_selectionKey_key" ON "CartItem"("cartId", "selectionKey");

-- CreateIndex
CREATE INDEX "CustomerAddress_customerId_createdAt_idx" ON "CustomerAddress"("customerId", "createdAt");

-- CreateIndex
CREATE INDEX "CartQuote_cartId_expiresAt_idx" ON "CartQuote"("cartId", "expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "Order_orderNumber_key" ON "Order"("orderNumber");

-- CreateIndex
CREATE INDEX "Order_customerId_createdAt_id_idx" ON "Order"("customerId", "createdAt", "id");

-- CreateIndex
CREATE INDEX "Order_restaurantId_createdAt_id_idx" ON "Order"("restaurantId", "createdAt", "id");

-- CreateIndex
CREATE UNIQUE INDEX "Order_customerId_idempotencyKey_key" ON "Order"("customerId", "idempotencyKey");

-- CreateIndex
CREATE UNIQUE INDEX "Order_cartId_cartVersion_key" ON "Order"("cartId", "cartVersion");

-- CreateIndex
CREATE INDEX "OrderItem_orderId_idx" ON "OrderItem"("orderId");

-- CreateIndex
CREATE UNIQUE INDEX "OrderItemAddOn_orderItemId_originalAddOnId_key" ON "OrderItemAddOn"("orderItemId", "originalAddOnId");

-- CreateIndex
CREATE INDEX "OrderEvent_publishedAt_createdAt_id_idx" ON "OrderEvent"("publishedAt", "createdAt", "id");

-- CreateIndex
CREATE UNIQUE INDEX "OrderEvent_orderId_eventType_key" ON "OrderEvent"("orderId", "eventType");

-- AddForeignKey
ALTER TABLE "Cart" ADD CONSTRAINT "Cart_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Cart" ADD CONSTRAINT "Cart_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CartItem" ADD CONSTRAINT "CartItem_cartId_fkey" FOREIGN KEY ("cartId") REFERENCES "Cart"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CartItem" ADD CONSTRAINT "CartItem_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "MenuItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CartItem" ADD CONSTRAINT "CartItem_variantId_fkey" FOREIGN KEY ("variantId") REFERENCES "MenuItemVariant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CartItemAddOn" ADD CONSTRAINT "CartItemAddOn_cartItemId_fkey" FOREIGN KEY ("cartItemId") REFERENCES "CartItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CartItemAddOn" ADD CONSTRAINT "CartItemAddOn_addOnId_fkey" FOREIGN KEY ("addOnId") REFERENCES "AddOn"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CustomerAddress" ADD CONSTRAINT "CustomerAddress_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CustomerAddress" ADD CONSTRAINT "CustomerAddress_localityId_fkey" FOREIGN KEY ("localityId") REFERENCES "Locality"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CartQuote" ADD CONSTRAINT "CartQuote_cartId_fkey" FOREIGN KEY ("cartId") REFERENCES "Cart"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Order" ADD CONSTRAINT "Order_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Order" ADD CONSTRAINT "Order_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Order" ADD CONSTRAINT "Order_cartId_fkey" FOREIGN KEY ("cartId") REFERENCES "Cart"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OrderItem" ADD CONSTRAINT "OrderItem_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OrderItem" ADD CONSTRAINT "OrderItem_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "MenuItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OrderItemAddOn" ADD CONSTRAINT "OrderItemAddOn_orderItemId_fkey" FOREIGN KEY ("orderItemId") REFERENCES "OrderItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OrderEvent" ADD CONSTRAINT "OrderEvent_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OrderEvent" ADD CONSTRAINT "OrderEvent_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE UNIQUE INDEX "CustomerAddress_one_default" ON "CustomerAddress" ("customerId") WHERE "isDefault" = true;
ALTER TABLE "Cart" ADD CONSTRAINT "Cart_positive_version" CHECK (version > 0);
ALTER TABLE "CartItem" ADD CONSTRAINT "CartItem_valid_quantity" CHECK (quantity BETWEEN 1 AND 20);
ALTER TABLE "OrderItem" ADD CONSTRAINT "OrderItem_valid_amounts" CHECK (quantity BETWEEN 1 AND 20 AND "baseUnitPaise" >= 0 AND "lineTotalPaise" >= 0);
ALTER TABLE "OrderItemAddOn" ADD CONSTRAINT "OrderItemAddOn_valid_amount" CHECK ("unitPricePaise" >= 0);
ALTER TABLE "Order" ADD CONSTRAINT "Order_valid_amounts" CHECK ("itemSubtotalPaise" >= 0 AND "customizationTotalPaise" >= 0 AND "packagingPaise" >= 0 AND "deliveryPaise" >= 0 AND "platformPaise" >= 0 AND "discountPaise" >= 0 AND "taxPaise" >= 0 AND "finalPayablePaise" >= 0 AND "finalPayablePaise" = "itemSubtotalPaise" + "customizationTotalPaise" + "packagingPaise" + "deliveryPaise" + "platformPaise" - "discountPaise" + "taxPaise");
