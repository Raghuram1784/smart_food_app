-- Run against postgres as administrator. Query Tool must have Auto-commit ON.
-- PostgreSQL has no CREATE DATABASE IF NOT EXISTS and CREATE DATABASE cannot run in DO/transactions.
-- Execute this read-only query, then execute the returned command alone in a new Query Tool tab.
SELECT 'CREATE DATABASE food_delivery_dev OWNER food_app_user;' AS command_to_run
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'food_delivery_dev');
-- Zero rows means the database already exists: reuse it; do not drop or recreate it.
-- For tests, repeat with food_delivery_test only if a dedicated test database is wanted.
