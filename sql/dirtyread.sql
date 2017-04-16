-- Create table and disable autovacuum
CREATE TABLE foo (bar bigint, baz text);
ALTER TABLE foo SET (
  autovacuum_enabled = false, toast.autovacuum_enabled = false
);

-- single row
INSERT INTO foo VALUES (1, 'Hello world');
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint, baz text);
DELETE FROM foo;
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint, baz text);

VACUUM foo;

-- multiple rows
INSERT INTO foo VALUES (1, 'Delete'), (2, 'Insert'), (3, 'Update'), (4, 'Not deleted'), (5, 'Not updated');
DELETE FROM foo WHERE bar = 1;
UPDATE foo SET baz = 'Updated' WHERE bar = 3;
BEGIN;
	DELETE FROM foo WHERE bar = 4;
	UPDATE foo SET baz = 'Not quite updated' where bar = 5;
	INSERT INTO foo VALUES (6, 'Not inserted');
ROLLBACK;
SELECT * FROM foo;
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint, baz text);

-- system columns (don't show tableoid and xmin, but make sure they are numbers)
SELECT CASE WHEN tableoid >= 0 THEN 0 END AS tableoid,
	ctid,
	CASE WHEN xmin::text::int >= 0 THEN 0 END AS xmin,
	CASE WHEN xmax::text <> '0' THEN xmax::text::int - xmin::text::int END AS xmax,
	cmin, cmax, dead, oid, bar, baz
	FROM pg_dirtyread('foo'::regclass)
	AS t(tableoid oid, ctid tid, xmin xid, xmax xid, cmin cid, cmax cid, dead boolean, oid oid, bar bigint, baz text);

-- error cases
SELECT pg_dirtyread('foo'::regclass);
SELECT * FROM pg_dirtyread(0) as t(bar bigint, baz text);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar int, baz text);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(moo bigint);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(tableoid bigint);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(ctid bigint);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(xmin bigint);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(xmax bigint);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(cmin bigint);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(cmax bigint);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(dead bigint);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(oid bigint);

SET ROLE luser;
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint, baz text);
