-- Decimal division is presentation only; all stored money is integer paise.
SELECT id,name,"basePricePaise",("basePricePaise"::numeric/100)::numeric(12,2) AS sample_rupees FROM "MenuItem" ORDER BY "displayOrder";
SELECT id FROM "MenuItem" WHERE "basePricePaise"<0; -- Expect zero rows.
SELECT code,component,"fixedPaise","rateBasisPoints","isActive" FROM "PricingRule"; -- No invented fees seeded.
