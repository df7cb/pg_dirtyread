CREATE EXTENSION pg_dirtyread;

-- create a non-superuser role, ignoring any output/errors, it might already exist
DO $$
	BEGIN
		CREATE ROLE luser;
	EXCEPTION WHEN duplicate_object THEN
		NULL;
	END;
$$;
