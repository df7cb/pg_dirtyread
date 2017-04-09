pg_dirtyread 1.0
================

The pg_dirtyread extension provides the ability to read dead but unvacuumed
rows from a relation.

Building
--------

To build pg_dirtyread, just do this:

    make
    make install

If you encounter an error such as:

    make: pg_config: Command not found

Be sure that you have `pg_config` installed and in your path. If you used a
package management system such as RPM to install PostgreSQL, be sure that the
`-devel` package is also installed. If necessary tell the build process where
to find it:

    env PG_CONFIG=/path/to/pg_config make && make install

Loading
-------

Once pg_dirtyread is built and installed, you can add it to a database. Loading
pg_dirtyread is as simple as connecting to a database as a super user and
running:

    CREATE EXTENSION pg_dirtyread;

Using
-----

    SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint, baz text);

Where the schema of `foo` is `(bar bigint, baz text)`.
