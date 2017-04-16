CREATE EXTENSION pg_dirtyread;

-- create a non-superuser role, ignoring any output/errors, it might already exist
SET client_min_messages = fatal;
\set QUIET on
CREATE ROLE luser;
