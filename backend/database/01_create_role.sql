-- Run against postgres as a local administrator. Does not reset an existing password.
DO $$ BEGIN
 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'food_app_user') THEN
  CREATE ROLE food_app_user LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
 END IF;
END $$;
-- For a newly created role, set its password via pgAdmin Login/Group Roles > Properties > Definition.
-- Never save a real password in this file. A passwordless LOGIN role cannot authenticate by SCRAM.
