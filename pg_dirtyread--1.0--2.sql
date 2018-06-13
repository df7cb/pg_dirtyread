DROP FUNCTION pg_dirtyread(oid);

CREATE FUNCTION pg_dirtyread(regclass)
	RETURNS SETOF record
	AS 'MODULE_PATHNAME'
	LANGUAGE C;
