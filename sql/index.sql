select setting::int >= 160000 as is_pg16 from pg_settings where name = 'server_version_num';

CREATE INDEX ON foo(bar);
SELECT * FROM pg_dirtyread('foo_bar_idx') as t(bar bigint);
