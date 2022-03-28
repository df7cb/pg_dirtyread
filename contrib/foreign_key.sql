create or replace function check_foreign_key(con_oid oid, max_missing bigint default 100, missing out text)
  returns setof text
  language plpgsql
as $$-- Author: Christoph Berg
declare
  con_name text;
  def text;
  rel text; relcols text; -- referencing table
  frel text; frelcols text; -- referenced table
  fkpred text;
  query text;
  missing_count bigint default 0;
begin
  select into strict con_name, def, rel, relcols, frel, frelcols, fkpred
    conname, pg_get_constraintdef(oid, true),
    conrelid::regclass, relcolumns,
    confrelid::regclass, frelcolumns,
    fkpredicate
  from pg_constraint,
    lateral (select
        string_agg(format('%I', a1.attname), ', ') relcolumns,
        string_agg(format('%I', a2.attname), ', ') frelcolumns,
        string_agg(format('rel.%I = frel.%I', a1.attname, a2.attname), ' and ') fkpredicate
      from generate_subscripts(conkey, 1) u,
      lateral
      (select attname from pg_attribute where attrelid = conrelid and attnum = conkey[u]) a1,
      lateral
      (select attname from pg_attribute where attrelid = confrelid and attnum = confkey[u]) a2
    ) consub
  where oid = con_oid;

  raise notice 'FK % on %: %', con_name, rel, def;

  query := format('select (%s) from %s rel where (%s) is not null and not exists (select from %s frel where %s)', relcols, rel, relcols, frel, fkpred);
  --raise notice '%', query;
  for missing in execute query loop
    missing_count := missing_count + 1;
    if max_missing is not null and missing_count > max_missing then
      raise notice 'Stopping after % missing keys', missing_count;
      exit;
    end if;
    return next;
  end loop;

  if missing_count > 0 then
    raise warning 'Found % rows in table % (%) missing in table % (%)',
      missing_count, rel, relcols, frel, frelcols;
  end if;

  return;
end$$;

comment on function check_foreign_key is 'Check FOREIGN KEY for missing rows';

/* Suggested usage:
\x
\t
select format('select * from check_foreign_key(%s)', oid) from pg_constraint where contype = 'f' \gexec
*/
