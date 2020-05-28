create or replace function read_table(relname regclass)
returns setof record
as $$
declare
  pages int;
  page int;
  ctid tid;
  r record;
  sql_state text;
  error text;
begin
  select pg_relation_size(relname) / current_setting('block_size')::int into pages;

  for page in 0 .. pages-1 loop

    begin

      for ctid in select t_ctid from heap_page_items(get_raw_page(relname::text, page)) loop
        begin
          execute format('SELECT * FROM %s WHERE ctid=%L', relname, ctid) into r;
          if r is not null then
            return next r;
          end if;
        exception -- bad tuple
          when others then
            get stacked diagnostics sql_state := RETURNED_SQLSTATE;
            get stacked diagnostics error := MESSAGE_TEXT;
            raise notice 'Skipping ctid %: %: %', ctid, sql_state, error;
        end;
      end loop;

    exception -- bad page
      when undefined_function then
        raise exception undefined_function
          using message = SQLERRM,
                hint = 'Use CREATE EXTENSION pageinspect; to create it';
      when others then
        get stacked diagnostics sql_state := RETURNED_SQLSTATE;
        get stacked diagnostics error := MESSAGE_TEXT;
        raise notice 'Skipping page %: %: %', page, sql_state, error;
    end;

  end loop;
end;
$$ language plpgsql;

comment on function read_table(regclass) is
  'read all good tuples from a table, skipping over all tuples that trigger an error';
