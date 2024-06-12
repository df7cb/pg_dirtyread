create table toast (
    description text,
    data text
);

insert into toast values ('short inline', 'xxx');
insert into toast values ('long inline uncompressed', repeat('x', 200));

alter table toast alter column data set storage external;
insert into toast values ('external uncompressed', repeat('0123456789 8< ', 200));

alter table toast alter column data set storage extended;
insert into toast values ('inline compressed pglz', repeat('0123456789 8< ', 200));
insert into toast values ('extended compressed pglz', repeat('0123456789 8< ', 20000));

alter table toast alter column data set compression lz4;
insert into toast values ('inline compressed lz4', repeat('0123456789 8< ', 200));
insert into toast values ('extended compressed lz4', repeat('0123456789 8< ', 50000));

select description, pg_column_size(data), substring(data, 1, 50) as data from toast;
delete from toast;

-- toasted values are uncompressed after pg_dirtyread
select description, pg_column_size(data), substring(data, 1, 50) as data from pg_dirtyread('toast') as (description text, data text);
