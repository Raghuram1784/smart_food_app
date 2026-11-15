-- F2 "Order for friends": the organizer can add participants by name only (no account, invite or OTP).
-- GroupMember.userId stays the participant id used by cart items and bill splits; for account holders
-- it equals accountId (FK to User), for guests it is a random id and accountId is NULL.
ALTER TABLE "GroupMember" ADD COLUMN "isGuest" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "GroupMember" ADD COLUMN "accountId" UUID;
UPDATE "GroupMember" SET "accountId" = "userId";
ALTER TABLE "GroupMember" DROP CONSTRAINT "GroupMember_userId_fkey";
ALTER TABLE "GroupMember" ADD CONSTRAINT "GroupMember_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "GroupMember" ADD CONSTRAINT "GroupMember_guest_account_check"
  CHECK (("isGuest" AND "accountId" IS NULL) OR (NOT "isGuest" AND "accountId" = "userId"));
ALTER TABLE "GroupMember" ADD CONSTRAINT "GroupMember_displayName_check" CHECK (length(btrim("displayName")) BETWEEN 1 AND 80);
CREATE INDEX "GroupMember_accountId_idx" ON "GroupMember"("accountId");
