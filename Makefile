MODULES = pg_dirtyread

EXTENSION = pg_dirtyread
DATA = pg_dirtyread--1.0.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
