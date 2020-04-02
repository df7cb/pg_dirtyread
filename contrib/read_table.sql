-- read all good tuples from a table, skipping over all tuples that trigger an error
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
          execute format('SELECT * FROM %I WHERE ctid=%L', relname, ctid) into r;
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
      when others then
        get stacked diagnostics sql_state := RETURNED_SQLSTATE;
        get stacked diagnostics error := MESSAGE_TEXT;
        raise notice 'Skipping page %: %: %', page, sql_state, error;
    end;

  end loop;
end;
$$ language plpgsql;

-- copy all good tuples from a table to another one (returns number of tuples copied)
create or replace function rescue_table(relname regclass, savename name, "create" boolean default true)
returns bigint
as $$
declare
  pages int;
  page int;
  ctid tid;
  row_count bigint;
  rows bigint := 0;
  sql_state text;
  error text;
begin
  if rescue_table.create then
    execute format('CREATE TABLE %I (LIKE %I)', savename, relname);
  end if;

  select pg_relation_size(relname) / current_setting('block_size')::int into pages;

  for page in 0 .. pages-1 loop
    if page % 10000 = 0 then
      raise notice '%: page % of %', relname, page, pages;
    end if;

    begin

      for ctid in select t_ctid from heap_page_items(get_raw_page(relname::text, page)) loop
        begin
          execute format('INSERT INTO %I SELECT * FROM %I WHERE ctid=%L', savename, relname, ctid);
          get diagnostics row_count = ROW_COUNT;
          rows := rows + row_count;
        exception -- bad tuple
          when others then
            get stacked diagnostics sql_state := RETURNED_SQLSTATE;
            get stacked diagnostics error := MESSAGE_TEXT;
            raise notice 'Skipping ctid %: %: %', ctid, sql_state, error;
        end;
      end loop;

    exception -- bad page
      when others then
        get stacked diagnostics sql_state := RETURNED_SQLSTATE;
        get stacked diagnostics error := MESSAGE_TEXT;
        raise notice 'Skipping page %: %: %', page, sql_state, error;
    end;

  end loop;

  return rows;
end;
$$ language plpgsql;

-- return ctids of all tuples in a table that trigger an error
create or replace function bad_tuples(relname regclass)
returns table (page int, ctid tid, sqlstate text, sqlerrm text)
as $$
declare
  pages int;
  page int;
  ctid tid;
  r record;
begin
  select pg_relation_size(relname) / current_setting('block_size')::int into pages;

  for page in 0 .. pages-1 loop
    if page % 10000 = 0 then
      raise notice '%: page % of %', relname, page, pages;
    end if;

    begin

      for ctid in select t_ctid from heap_page_items(get_raw_page(relname::text, page)) loop
        begin
          execute format('SELECT * FROM %I WHERE ctid=%L', relname, ctid) into r;
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
      when others then
        bad_tuples.page := page;
        bad_tuples.sqlstate := sqlstate;
        bad_tuples.sqlerrm := sqlerrm;
        return next;
    end;

  end loop;
end;
$$ language plpgsql;

