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
INSERT INTO foo VALUES (1, 'Delete'), (2, 'Insert'), (3, 'Update');
DELETE FROM foo WHERE bar = 1;
UPDATE foo SET baz = 'Updated' WHERE bar = 3;
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint, baz text);

-- error cases
SELECT * FROM pg_dirtyread(0) as t(bar bigint, baz text);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar int, baz text);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint);
