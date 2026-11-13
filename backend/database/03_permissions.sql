-- Run against food_delivery_dev as its owner or administrator.
GRANT CONNECT ON DATABASE food_delivery_dev TO food_app_user;
GRANT USAGE, CREATE ON SCHEMA public TO food_app_user;
-- Prisma creates/owns catalog objects through food_app_user in development.
-- This script grants no access to unrelated databases. Production uses separate migration/runtime roles.
