-- test oid columns (removed in PostgreSQL 12)

SELECT setting::int >= 120000 AS is_pg_12 FROM pg_settings WHERE name = 'server_version_num';

SELECT * FROM pg_dirtyread('foo') AS t(oid oid, bar bigint, baz text);

-- error cases
SELECT * FROM pg_dirtyread('foo') as t(oid bigint);
