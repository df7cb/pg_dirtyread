create or replace function bad_tuples(relname regclass)
returns table (page int, ctid tid, sqlstate text, sqlerrm text)
as $$
declare
  pages int;
  page int;
  ctid tid;
begin
  select pg_relation_size(relname) / current_setting('block_size')::int into pages;

  for page in 0 .. pages-1 loop
    if page % 10000 = 0 then
      raise notice '%: page % of %', relname, page, pages;
    end if;

    begin

      for ctid in select t_ctid from heap_page_items(get_raw_page(relname::text, page)) loop
        begin
          execute format('SELECT length(t::text) FROM %s t WHERE ctid=%L', relname, ctid);
        exception -- bad tuple
          when others then
            bad_tuples.page := page;
            bad_tuples.ctid := ctid;
            bad_tuples.sqlstate := sqlstate;
            bad_tuples.sqlerrm := sqlerrm;
            return next;
        end;
      end loop;

    exception -- bad page
      when undefined_function then
        raise exception undefined_function
          using message = SQLERRM,
                hint = 'Use CREATE EXTENSION pageinspect; to create it';
      when others then
        bad_tuples.page := page;
        bad_tuples.sqlstate := sqlstate;
        bad_tuples.sqlerrm := sqlerrm;
        return next;
    end;

  end loop;
end;
$$ language plpgsql;

comment on function bad_tuples(regclass) is
  'return ctids of all tuples in a table that trigger an error';
