-- Run against food_delivery_dev. Read-only; no credentials returned.
SELECT current_database() AS database, current_user AS connected_role, version() AS postgres_version;
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname='food_app_user';
SELECT datname, pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname IN ('food_delivery_dev','food_delivery_test');
SELECT has_schema_privilege('food_app_user','public','USAGE') AS schema_usage,
       has_schema_privilege('food_app_user','public','CREATE') AS migration_access;
