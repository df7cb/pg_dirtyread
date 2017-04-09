-- Create table and disable autovacuum
CREATE TABLE foo (bar bigint, baz text);
ALTER TABLE foo SET (
  autovacuum_enabled = false, toast.autovacuum_enabled = false
);

INSERT INTO foo VALUES (1, 'Test'), (2, 'New Test');
DELETE FROM foo WHERE bar = 1;

SELECT * FROM foo;
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint, baz text);

-- error cases
SELECT * FROM pg_dirtyread(0) as t(bar bigint, baz text);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar int, baz text);
SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint);
