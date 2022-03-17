create or replace function check_unique_index(relid regclass, max_dupes bigint default 100, dupe out text, count out text)
  returns setof record
  language plpgsql
  set enable_indexscan = off
  set enable_indexonlyscan = off
  set enable_bitmapscan = off
as $$-- Author: Christoph Berg
declare
  tbl text;
  isunique boolean;
  key text;
  query text;
  dupe_count bigint default 0;
begin
  select into strict tbl, isunique indrelid::regclass, indisunique from pg_index where indexrelid = relid;

  select into strict key string_agg(quote_ident(attname), ', ') from
    pg_index i,
    unnest(indkey) u(indcolumn),
    lateral (select attrelid, attnum, attname from pg_attribute) a
    where i.indrelid=a.attrelid and u.indcolumn = a.attnum and indexrelid = relid;

  raise notice 'Checking index % on % (%)', relid, tbl, key;
  if not isunique then
    raise warning 'Index % is not UNIQUE', relid;
  end if;

  query := format('select (%s) dupe, count(*) from %s where (%s) is not null group by %s having count(*) > 1', key, tbl, key, key);
  --raise notice '%', query;
  for dupe, count in execute query loop
    dupe_count := dupe_count + 1;
    if max_dupes is not null and dupe_count > max_dupes then
      raise notice 'Stopping after % duplicate keys', dupe_count;
      exit;
    end if;
    return next;
  end loop;

  if dupe_count > 0 then
    raise warning 'Found % duplicates in table %, index % on (%)', dupe_count, tbl, relid, key;
  end if;

  return;
end$$;

comment on function check_unique_index is 'Check UNIQUE index for duplicates';

/* Suggested usage:
\x
\t
select format('select * from check_unique_index(%L)', indexrelid::regclass) from pg_index where indisunique \gexec
*/
