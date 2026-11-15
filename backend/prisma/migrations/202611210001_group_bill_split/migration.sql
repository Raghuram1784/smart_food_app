-- F2 bill splitting (informational: the organizer pays the order; members owe the organizer). Additive only.
CREATE TYPE "GroupSplitMethod" AS ENUM ('BY_PERSON', 'EQUAL');
ALTER TABLE "GroupOrder" ADD COLUMN "splitMethod" "GroupSplitMethod" NOT NULL DEFAULT 'BY_PERSON';
ALTER TABLE "GroupOrder" ADD COLUMN "splitSnapshot" JSONB;
-- Members a dish is shared between (empty = only the member who added it).
ALTER TABLE "GroupCartItem" ADD COLUMN "sharedWith" UUID[] NOT NULL DEFAULT ARRAY[]::UUID[];
