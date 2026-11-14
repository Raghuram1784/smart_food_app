-- CreateTable
CREATE TABLE "RiderPresence" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "isOnline" BOOLEAN NOT NULL DEFAULT false,
    "latitude" DECIMAL(9,6),
    "longitude" DECIMAL(9,6),
    "accuracyMeters" DOUBLE PRECISION,
    "locationTimestamp" TIMESTAMPTZ(3),
    "lastOnlineAt" TIMESTAMPTZ(3),
    "lastOfflineAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "RiderPresence_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "RiderPresence_userId_key" ON "RiderPresence"("userId");

-- CreateIndex
CREATE INDEX "RiderPresence_isOnline_updatedAt_idx" ON "RiderPresence"("isOnline", "updatedAt");

-- AddForeignKey
ALTER TABLE "RiderPresence" ADD CONSTRAINT "RiderPresence_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
